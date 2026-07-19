import 'dart:async';

import 'package:all_observer/all_observer.dart';

import '../common/service_names.dart';
import '../models/envelope.dart';
import '../models/event_batch_model.dart';
import '../models/protocol_event_model.dart';
import '../models/protocol_info_model.dart';
import '../store/devtools_store.dart';
import 'connection_state.dart';
import 'protocol_client.dart';

/// Orchestrates the connection lifecycle described in implementation spec
/// sections 12 (snapshot/event race), 16 (connection state machine), and 17
/// (hot restart / new session). Owns a [DevToolsStore] and feeds it,
/// through [ProtocolClient], everything the six screens need.
///
/// [liveEvents] must already be a broadcast-safe stream of decoded event
/// batches from the `all_observer:events` extension stream — the small VM
/// Service adapter that produces it lives outside this class so
/// [ConnectionController] itself has no direct `package:vm_service`
/// dependency and can be driven by a fake in tests.
class ConnectionController {
  ConnectionController({
    required ProtocolClient client,
    required Stream<EventBatchModel> liveEvents,
    DevToolsStore? store,
  }) : _client = client,
       _liveEvents = liveEvents,
       store = store ?? DevToolsStore();

  final ProtocolClient _client;
  final Stream<EventBatchModel> _liveEvents;

  /// Reconciled application state. Screens read this from inside
  /// `Observer`/`watch(context)`; they only need [state] for the
  /// connection banner/empty-state handling.
  final DevToolsStore store;

  static const int _maxSynchronizeAttempts = 3;

  final Observable<DevToolsConnectionState> _state =
      Observable<DevToolsConnectionState>(DevToolsConnectionState.disconnected);
  final Observable<String?> _errorMessage = Observable<String?>(null);
  final Observable<ProtocolInfoModel?> _protocolInfo =
      Observable<ProtocolInfoModel?>(null);
  final Observable<int> _decodeFailureCount = Observable<int>(0);
  StreamSubscription<EventBatchModel>? _liveSubscription;
  bool _bufferingForSnapshot = false;
  final List<ProtocolEventModel> _pendingDuringSnapshot =
      <ProtocolEventModel>[];
  Future<bool>? _activeResync;
  int _connectionGeneration = 0;
  bool _disposed = false;

  DevToolsConnectionState get state => _state.value;
  String? get errorMessage => _errorMessage.value;
  ProtocolInfoModel? get protocolInfo => _protocolInfo.value;
  int get decodeFailureCount => _decodeFailureCount.value;

  /// Starts (or restarts) the connection: subscribes to live events first,
  /// then requests protocol info and a snapshot. Safe to call again after
  /// [DevToolsConnectionState.error] or [DevToolsConnectionState.incompatible]
  /// to retry.
  Future<void> connect() async {
    if (_disposed) return;
    final int generation = ++_connectionGeneration;
    // Logically cancel any synchronization owned by the previous generation.
    // Its future may still complete, but generation checks prevent mutation.
    _activeResync = null;
    _bufferingForSnapshot = false;
    _pendingDuringSnapshot.clear();
    _errorMessage.value = null;
    _setState(DevToolsConnectionState.connecting);
    _liveSubscription?.cancel();
    _liveSubscription = _liveEvents.listen(_onLiveBatch, onError: _onLiveError);

    try {
      _setState(DevToolsConnectionState.loadingProtocolInfo);
      final ProtocolInfoModel info = await _client.getProtocolInfo();
      if (!_isCurrent(generation)) return;
      _protocolInfo.value = info;
      if (!info.isCompatibleWith(extensionSupportedProtocolVersion)) {
        _setState(DevToolsConnectionState.incompatible);
        return;
      }

      // Subscribe and enable the producer before taking the base snapshot.
      // Everything created from this point is either in the live buffer, the
      // protocol backlog, or both (duplicates are removed by sequence).
      await _client.setStreaming(enabled: true);
      if (!_isCurrent(generation)) return;
      _setState(DevToolsConnectionState.loadingSnapshot);
      final bool synced = await _synchronize(generation);
      if (!synced) {
        return; // _synchronize already set state to error.
      }

      if (!_isCurrent(generation)) return;
      _setState(DevToolsConnectionState.connected);
    } on BridgeResponseError catch (error) {
      if (!_isCurrent(generation)) return;
      if (error.code == 'bridge_not_initialized') {
        _setState(DevToolsConnectionState.unavailable);
      } else {
        _fail('${error.code}: ${error.message}');
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      _fail('$error');
    }
  }

  /// Fetches a fresh snapshot, applies it, then replays whatever arrived on
  /// the live stream while the snapshot request was in flight — the race
  /// described in spec section 12. Retries up to
  /// [_maxSynchronizeAttempts] times if the replay itself reveals another
  /// gap (e.g. very high event throughput during the resync window) before
  /// giving up and surfacing an error rather than looping forever.
  Future<bool> _synchronize(int generation) {
    final Future<bool>? active = _activeResync;
    if (active != null) return active;
    final Future<bool> created = _runSynchronize(generation);
    _activeResync = created;
    void release() {
      if (identical(_activeResync, created)) _activeResync = null;
    }

    unawaited(
      created.then<void>(
        (_) => release(),
        onError: (Object _, StackTrace stackTrace) {
          release();
        },
      ),
    );
    return created;
  }

  Future<bool> _runSynchronize(int generation) async {
    for (int attempt = 1; attempt <= _maxSynchronizeAttempts; attempt++) {
      if (!_isCurrent(generation)) return false;
      _bufferingForSnapshot = true;
      _pendingDuringSnapshot.clear();
      try {
        final snapshot = await _client.getSnapshot();
        if (!_isCurrent(generation)) return false;
        final EventBatchModel backlog = await _client.getEvents(
          afterSequence: snapshot.lastSequenceNumber,
        );
        if (!_isCurrent(generation)) return false;
        store.applySnapshot(snapshot);

        final Map<int, ProtocolEventModel> bySequence =
            <int, ProtocolEventModel>{};
        for (final ProtocolEventModel event in <ProtocolEventModel>[
          ...backlog.events,
          ..._pendingDuringSnapshot,
        ]) {
          if (event.sessionId == snapshot.sessionId &&
              event.sequenceNumber > snapshot.lastSequenceNumber) {
            bySequence[event.sequenceNumber] = event;
          }
        }
        final List<ProtocolEventModel> reconciled = bySequence.values.toList()
          ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
        if (reconciled.isNotEmpty) store.applyEvents(reconciled);

        if (!store.needsResync) return true;
        _setState(DevToolsConnectionState.reconnecting);
      } finally {
        if (_isCurrent(generation)) {
          _pendingDuringSnapshot.clear();
          _bufferingForSnapshot = false;
        }
      }
    }
    _fail(
      'Could not reach a consistent snapshot after '
      '$_maxSynchronizeAttempts attempts.',
    );
    return false;
  }

  void _onLiveBatch(EventBatchModel batch) {
    if (_bufferingForSnapshot) {
      _pendingDuringSnapshot.addAll(batch.events);
      return;
    }
    final result = store.applyEvents(batch.events);
    if (result.gapDetected || result.foreignSessionCount > 0) {
      unawaited(
        _synchronize(_connectionGeneration).then((bool synced) {
          if (synced && !_disposed) {
            _setState(DevToolsConnectionState.connected);
          }
        }),
      );
    }
  }

  void _onLiveError(Object error, StackTrace stackTrace) {
    if (_disposed) return;
    _decodeFailureCount.value++;
    const String message = 'A live event batch could not be decoded safely.';
    _errorMessage.value = message;
    store.markNeedsResync('decode_failure', message);
    unawaited(
      _synchronize(_connectionGeneration).then(
        (bool synced) {
          if (synced && !_disposed) {
            _setState(DevToolsConnectionState.connected);
          }
        },
        onError: (Object syncError, StackTrace syncStack) {
          _fail(
            'Resynchronization failed after a decode error '
            '(${syncError.runtimeType}).',
          );
        },
      ),
    );
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _connectionGeneration;

  void _setState(DevToolsConnectionState newState) {
    if (!_disposed) {
      _state.value = newState;
    }
  }

  void _fail(String message) {
    if (_disposed) return;
    _errorMessage.value = message;
    _setState(DevToolsConnectionState.error);
  }

  /// Cancels the live subscription and closes every `Observable` this
  /// controller owns, including [store]'s. Must be called exactly once,
  /// mirroring the explicit-disposal convention `all_observer` uses
  /// throughout (no garbage-collected observables).
  void dispose() {
    _disposed = true;
    _connectionGeneration++;
    unawaited(_liveSubscription?.cancel());
    _state.close();
    _errorMessage.close();
    _protocolInfo.close();
    _decodeFailureCount.close();
    store.dispose();
  }
}
