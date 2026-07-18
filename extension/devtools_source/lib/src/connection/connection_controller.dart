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

  final Observable<DevToolsConnectionState> _state = Observable<DevToolsConnectionState>(
    DevToolsConnectionState.disconnected,
  );
  final Observable<String?> _errorMessage = Observable<String?>(null);
  final Observable<ProtocolInfoModel?> _protocolInfo = Observable<ProtocolInfoModel?>(null);
  StreamSubscription<EventBatchModel>? _liveSubscription;
  bool _bufferingForSnapshot = false;
  final List<ProtocolEventModel> _pendingDuringSnapshot = <ProtocolEventModel>[];
  bool _disposed = false;

  DevToolsConnectionState get state => _state.value;
  String? get errorMessage => _errorMessage.value;
  ProtocolInfoModel? get protocolInfo => _protocolInfo.value;

  /// Starts (or restarts) the connection: subscribes to live events first,
  /// then requests protocol info and a snapshot. Safe to call again after
  /// [DevToolsConnectionState.error] or [DevToolsConnectionState.incompatible]
  /// to retry.
  Future<void> connect() async {
    _errorMessage.value = null;
    _setState(DevToolsConnectionState.connecting);
    _liveSubscription?.cancel();
    _liveSubscription = _liveEvents.listen(
      _onLiveBatch,
      onError: (Object error) => _fail('Live event stream error: $error'),
    );

    try {
      _setState(DevToolsConnectionState.loadingProtocolInfo);
      final ProtocolInfoModel info = await _client.getProtocolInfo();
      _protocolInfo.value = info;
      if (!info.isCompatibleWith(extensionSupportedProtocolVersion)) {
        _setState(DevToolsConnectionState.incompatible);
        return;
      }

      _setState(DevToolsConnectionState.loadingSnapshot);
      final bool synced = await _synchronize();
      if (!synced) {
        return; // _synchronize already set state to error.
      }

      await _client.setStreaming(enabled: true);
      _setState(DevToolsConnectionState.connected);
    } on BridgeResponseError catch (error) {
      if (error.code == 'bridge_not_initialized') {
        _setState(DevToolsConnectionState.unavailable);
      } else {
        _fail('${error.code}: ${error.message}');
      }
    } catch (error) {
      _fail('$error');
    }
  }

  /// Fetches a fresh snapshot, applies it, then replays whatever arrived on
  /// the live stream while the snapshot request was in flight — the race
  /// described in spec section 12. Retries up to
  /// [_maxSynchronizeAttempts] times if the replay itself reveals another
  /// gap (e.g. very high event throughput during the resync window) before
  /// giving up and surfacing an error rather than looping forever.
  Future<bool> _synchronize() async {
    for (int attempt = 1; attempt <= _maxSynchronizeAttempts; attempt++) {
      _bufferingForSnapshot = true;
      _pendingDuringSnapshot.clear();

      final snapshot = await _client.getSnapshot();
      store.applySnapshot(snapshot);

      final List<ProtocolEventModel> buffered = List<ProtocolEventModel>.of(
        _pendingDuringSnapshot,
      );
      _pendingDuringSnapshot.clear();
      _bufferingForSnapshot = false;

      if (buffered.isNotEmpty) {
        store.applyEvents(buffered);
      }

      if (!store.needsResync) {
        return true;
      }
      _setState(DevToolsConnectionState.reconnecting);
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
        _synchronize().then((bool synced) {
          if (synced) {
            _setState(DevToolsConnectionState.connected);
          }
        }),
      );
    }
  }

  void _setState(DevToolsConnectionState newState) {
    if (!_disposed) {
      _state.value = newState;
    }
  }

  void _fail(String message) {
    _errorMessage.value = message;
    _setState(DevToolsConnectionState.error);
  }

  /// Cancels the live subscription and closes every `Observable` this
  /// controller owns, including [store]'s. Must be called exactly once,
  /// mirroring the explicit-disposal convention `all_observer` uses
  /// throughout (no garbage-collected observables).
  void dispose() {
    _disposed = true;
    unawaited(_liveSubscription?.cancel());
    _state.close();
    _errorMessage.close();
    _protocolInfo.close();
    store.dispose();
  }
}
