import 'package:all_observer/all_observer.dart';

import '../models/dependency_model.dart';
import '../models/node_model.dart';
import '../models/protocol_event_model.dart';
import '../models/scope_model.dart';
import '../models/snapshot_model.dart';
import '../models/warning_model.dart';

/// One entry in [DevToolsStore.diagnostics]: an objective inconsistency the
/// store observed while reconciling — never a conclusion like "leak" or
/// "bug". See implementation spec section 21: "possíveis problemas", not a
/// leak detector.
final class ReconciliationDiagnostic {
  const ReconciliationDiagnostic({
    required this.code,
    required this.message,
    required this.atSequenceNumber,
  });

  final String code;
  final String message;
  final int? atSequenceNumber;
}

/// Outcome of one [DevToolsStore.applyEvents] call, returned so callers
/// (and tests) can assert on exactly what happened without re-deriving it
/// from store state.
final class ApplyEventsResult {
  const ApplyEventsResult({
    required this.appliedCount,
    required this.duplicateCount,
    required this.foreignSessionCount,
    required this.gapDetected,
  });

  final int appliedCount;
  final int duplicateCount;
  final int foreignSessionCount;
  final bool gapDetected;
}

/// Pure reconciliation core: `snapshot + events with sequenceNumber >
/// snapshot.lastSequenceNumber = current state` (implementation spec
/// section 12). Has no VM Service / `dart:developer` / widget dependency —
/// [ConnectionController] feeds it decoded models; this class only ever
/// decides what those models mean for the current view.
///
/// Reactivity is implemented with `all_observer` — the same library this
/// entire extension exists to observe in *other* apps. All state below is
/// `Observable`/reactive-collection fields; screens read them from inside
/// `Observer`/`watch(context)` and rebuild automatically, with no
/// `ChangeNotifier`/`notifyListeners()` of our own.
///
/// Guarantees this class enforces, all directly from the spec:
///
/// - `sequenceNumber`, never `timestampMicros`, determines applied order
///   and duplicate/gap detection (section 2, principle 8).
/// - A snapshot is always the authoritative base; events are only ever
///   layered on top of one (principle 9).
/// - Events from a session other than the current one are never applied
///   (principle 19: "sessões diferentes não devem ser misturadas").
/// - A sequence gap sets [needsResync] rather than guessing at the missing
///   state (principle 17: "toda perda de eventos deve ficar visível";
///   section 12: "lacunas de sequência provocam ressincronização").
/// - Disposed nodes are kept (marked, not deleted) so the Nodes screen can
///   still show lifecycle history; disposed scopes are removed, matching
///   `ObserverProtocol.snapshot()`'s own behavior confirmed by the core's
///   `scope_registry_contract_test.dart`.
class DevToolsStore {
  final Observable<String?> _sessionId = Observable<String?>(null);
  final Observable<int> _lastAppliedSequence = Observable<int>(0);
  final Observable<bool> _needsResync = Observable<bool>(false);
  final Observable<int> _coreDroppedEventCount = Observable<int>(0);
  final Observable<int?> _firstAvailableSequence = Observable<int?>(null);
  final Observable<int?> _lastAvailableSequence = Observable<int?>(null);
  final Observable<DateTime?> _snapshotAppliedAt = Observable<DateTime?>(null);

  // Declared as the concrete Observable* types (not the plain Map/List
  // interface) so .close() — defined on ObservableMap/ObservableList, not
  // on Map/List — is available in dispose() below.
  final ObservableMap<int, NodeModel> _nodes = <int, NodeModel>{}.obs;
  final ObservableMap<int, DependencyModel> _dependencies =
      <int, DependencyModel>{}.obs;
  final ObservableMap<int, ScopeModel> _scopes = <int, ScopeModel>{}.obs;
  final ObservableList<ProtocolEventModel> _timeline =
      <ProtocolEventModel>[].obs;
  final ObservableList<WarningModel> _warnings = <WarningModel>[].obs;
  final ObservableList<ReconciliationDiagnostic> _diagnostics =
      <ReconciliationDiagnostic>[].obs;

  /// Upper bound on retained timeline events, so a long-running session
  /// with heavy traffic doesn't grow this list (and every list view built
  /// from it) without bound. Oldest events are dropped first — this is a
  /// *view* limit, distinct from and on top of the core's own ring buffer
  /// and the bridge's transport batching. See implementation spec section
  /// 22 ("Performance da interface").
  static const int maxRetainedTimelineEvents = 5000;

  String? get sessionId => _sessionId.value;
  int get lastAppliedSequence => _lastAppliedSequence.value;
  bool get needsResync => _needsResync.value;
  int get coreDroppedEventCount => _coreDroppedEventCount.value;
  int? get firstAvailableSequence => _firstAvailableSequence.value;
  int? get lastAvailableSequence => _lastAvailableSequence.value;
  DateTime? get snapshotAppliedAt => _snapshotAppliedAt.value;

  List<NodeModel> get nodes => List<NodeModel>.unmodifiable(_nodes.values);
  List<DependencyModel> get dependencies =>
      List<DependencyModel>.unmodifiable(_dependencies.values);
  List<ScopeModel> get scopes => List<ScopeModel>.unmodifiable(_scopes.values);
  List<ProtocolEventModel> get timeline =>
      List<ProtocolEventModel>.unmodifiable(_timeline);
  List<WarningModel> get warnings => List<WarningModel>.unmodifiable(_warnings);
  List<ReconciliationDiagnostic> get diagnostics =>
      List<ReconciliationDiagnostic>.unmodifiable(_diagnostics);

  NodeModel? nodeById(int objectId) => _nodes[objectId];
  ScopeModel? scopeById(int scopeId) => _scopes[scopeId];

  void markNeedsResync(String code, String message) {
    Observable.batch(() {
      _needsResync.value = true;
      _diagnostics.add(
        ReconciliationDiagnostic(
          code: code,
          message: message,
          atSequenceNumber: null,
        ),
      );
    });
  }

  /// Dependencies of [trackerId] (what it reads), resolved from the current
  /// dependency graph.
  Set<int> dependenciesOf(int trackerId) =>
      _dependencies[trackerId]?.dependencyIds ?? const <int>{};

  /// Trackers that currently depend on [objectId] — the inverse edge,
  /// recomputed on demand rather than maintained incrementally, since the
  /// dependency graph is expected to stay small enough (section 20.4
  /// explicitly allows a tabular-only view for this reason).
  Set<int> dependentsOf(int objectId) => _dependencies.entries
      .where((entry) => entry.value.dependencyIds.contains(objectId))
      .map((entry) => entry.key)
      .toSet();

  /// Replaces all state with [snapshot]: the only operation that can clear
  /// [needsResync]. Always safe to call, including for the very first
  /// connection and after detecting a gap or a session change.
  ///
  /// Wrapped in [Observable.batch] because it always touches several
  /// independent observables/collections as a single logical action —
  /// screens should never observe a snapshot applied "halfway".
  void applySnapshot(ProtocolSnapshotModel snapshot) {
    Observable.batch(() {
      final bool isNewSession =
          _sessionId.value != null && _sessionId.value != snapshot.sessionId;
      _sessionId.value = snapshot.sessionId;
      _lastAppliedSequence.value = snapshot.lastSequenceNumber;
      _coreDroppedEventCount.value = snapshot.droppedEventCount;
      _firstAvailableSequence.value = snapshot.firstAvailableSequence;
      _lastAvailableSequence.value = snapshot.lastAvailableSequence;
      _snapshotAppliedAt.value = DateTime.now();
      _needsResync.value = false;

      _nodes
        ..clear()
        ..addEntries(
          snapshot.nodes.map((node) => MapEntry(node.objectId, node)),
        );
      _dependencies
        ..clear()
        ..addEntries(
          snapshot.dependencies.map((dep) => MapEntry(dep.trackerId, dep)),
        );
      _scopes
        ..clear()
        ..addEntries(
          snapshot.scopes.map((scope) => MapEntry(scope.scopeId, scope)),
        );

      if (isNewSession) {
        // A new session has no relationship to the previous one's timeline —
        // archiving (rather than silently keeping) old rows would misrepresent
        // them as belonging to the current run.
        _timeline.clear();
        _warnings.clear();
        _diagnostics.clear();
      }
    });
  }

  /// Applies [events] (already decoded, in the order received) on top of
  /// the current snapshot baseline. Returns a summary of what happened —
  /// see [ApplyEventsResult]. Never throws: an event this store doesn't
  /// know how to interpret in context is recorded as a
  /// [ReconciliationDiagnostic], not a crash.
  ApplyEventsResult applyEvents(List<ProtocolEventModel> events) {
    int applied = 0;
    int duplicates = 0;
    int foreignSession = 0;
    bool gapDetectedNow = false;

    Observable.batch(() {
      for (final ProtocolEventModel event in events) {
        if (_sessionId.value == null) {
          // No snapshot applied yet — there is no baseline to reconcile
          // against. Callers must request a snapshot before streaming.
          foreignSession++;
          continue;
        }
        if (event.sessionId != _sessionId.value) {
          foreignSession++;
          continue;
        }
        if (_needsResync.value) {
          // Already dessincronizado: stop interpreting further events from
          // this session until a fresh snapshot arrives, rather than build
          // on an admittedly-incomplete state.
          continue;
        }
        if (event.sequenceNumber <= _lastAppliedSequence.value) {
          duplicates++;
          continue;
        }
        if (event.sequenceNumber != _lastAppliedSequence.value + 1) {
          _needsResync.value = true;
          gapDetectedNow = true;
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'sequence_gap',
              message:
                  'Expected sequenceNumber ${_lastAppliedSequence.value + 1}, got '
                  '${event.sequenceNumber}. A snapshot re-fetch is required.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
          break;
        }

        _applyOne(event);
        _lastAppliedSequence.value = event.sequenceNumber;
        applied++;
      }
    });

    return ApplyEventsResult(
      appliedCount: applied,
      duplicateCount: duplicates,
      foreignSessionCount: foreignSession,
      gapDetected: gapDetectedNow,
    );
  }

  void _applyOne(ProtocolEventModel event) {
    _pushTimeline(event);
    switch (event) {
      case NodeCreatedEventModel():
        if (_nodes.containsKey(event.objectId)) {
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'duplicate_node_created',
              message: 'NodeCreated for already-known node ${event.objectId}.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
        }
        _nodes[event.objectId] = NodeModel(
          objectId: event.objectId,
          kind: event.kind,
          debugLabel: event.debugLabel,
          debugType: event.debugType,
          createdAtMicros: event.timestampMicros,
          valueSummary: event.initialValueSummary,
        );

      case NodeUpdatedEventModel():
        final NodeModel? node = _nodes[event.objectId];
        if (node == null) {
          _needsResync.value = true;
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'update_for_unknown_node',
              message: 'NodeUpdated for unrepresented node ${event.objectId}.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
          return;
        }
        _nodes[event.objectId] = node.copyWith(
          valueSummary: event.newValueSummary,
          updatedAtMicros: event.timestampMicros,
        );

      case NodeDisposedEventModel():
        final NodeModel? node = _nodes[event.objectId];
        if (node == null) {
          _needsResync.value = true;
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'dispose_for_unknown_node',
              message: 'NodeDisposed for unrepresented node ${event.objectId}.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
          return;
        }
        if (node.isDisposed) {
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'duplicate_node_disposed',
              message: 'Duplicate NodeDisposed for node ${event.objectId}.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
          return;
        }
        _nodes[event.objectId] = node.copyWith(
          isDisposed: true,
          disposedAtMicros: event.timestampMicros,
          disposeReason: event.disposeReason,
          listenerCountAtDispose: event.listenerCount,
        );
        // Mirrors ObserverProtocol.nodeDisposed on the core exactly: it
        // removes the disposed node both as a tracker key and as a
        // dependency id inside every other tracker's set. The live event
        // stream does not separately emit a DependenciesChangedEvent for
        // this, so the store must replicate it here or dependency edges to
        // a disposed node would go stale until the next snapshot.
        _dependencies.remove(event.objectId);
        for (final int trackerId in _dependencies.keys.toList()) {
          final DependencyModel dep = _dependencies[trackerId]!;
          if (dep.dependencyIds.contains(event.objectId)) {
            final Set<int> updated = Set<int>.of(dep.dependencyIds)
              ..remove(event.objectId);
            if (updated.isEmpty) {
              _dependencies.remove(trackerId);
            } else {
              _dependencies[trackerId] = DependencyModel(
                trackerId: trackerId,
                dependencyIds: updated,
              );
            }
          }
        }

      case TrackerRunStartedEventModel():
      case TrackerRunFinishedEventModel():
        // Timeline-only: no standing state to update beyond the graph
        // changes DependenciesChangedEvent already carries.
        break;

      case DependenciesChangedEventModel():
        if (event.currentDependencyIds.isEmpty) {
          // Matches ObserverProtocol.snapshot(): a tracker with no current
          // dependencies has no entry at all, not an empty one.
          _dependencies.remove(event.trackerId);
        } else {
          _dependencies[event.trackerId] = DependencyModel(
            trackerId: event.trackerId,
            dependencyIds: event.currentDependencyIds.toSet(),
          );
        }

      case ScopeCreatedEventModel():
        if (_scopes.containsKey(event.scopeId)) {
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'duplicate_scope_created',
              message: 'ScopeCreated for already-known scope ${event.scopeId}.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
        }
        _scopes[event.scopeId] = ScopeModel(
          scopeId: event.scopeId,
          debugLabel: event.debugLabel,
          resources: const [],
        );

      case ScopeResourceRegisteredEventModel():
        final ScopeModel? scope = _scopes[event.scopeId];
        if (scope == null) {
          _needsResync.value = true;
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'resource_for_unknown_scope',
              message:
                  'ScopeResourceRegistered for unrepresented scope '
                  '${event.scopeId}.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
          return;
        }
        _scopes[event.scopeId] = scope.copyWithResourceAdded(
          ScopeResourceModel(
            resourceId: event.resourceId,
            resourceKind: event.resourceKind,
          ),
        );

      case ScopeDisposedEventModel():
        if (!_scopes.containsKey(event.scopeId)) {
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'duplicate_scope_disposed',
              message:
                  'ScopeDisposed for unrepresented scope ${event.scopeId}.',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
        }
        if (event.failedDisposeCount > 0) {
          _diagnostics.add(
            ReconciliationDiagnostic(
              code: 'scope_dispose_failures',
              message:
                  'Scope ${event.scopeId} disposed with '
                  '${event.failedDisposeCount} failed resource disposer(s).',
              atSequenceNumber: event.sequenceNumber,
            ),
          );
        }
        _scopes.remove(event.scopeId);

      case WarningRaisedEventModel():
        _warnings.add(WarningModel(event));
    }
  }

  void _pushTimeline(ProtocolEventModel event) {
    _timeline.add(event);
    if (_timeline.length > maxRetainedTimelineEvents) {
      _timeline.removeAt(0);
    }
  }

  /// Discards all state, including the session id. Used when the
  /// connection to the isolate is lost entirely (not just a gap/new
  /// session), so the UI does not keep showing a stale, disconnected
  /// snapshot as if it were current.
  void clear() {
    Observable.batch(() {
      _sessionId.value = null;
      _lastAppliedSequence.value = 0;
      _needsResync.value = false;
      _coreDroppedEventCount.value = 0;
      _firstAvailableSequence.value = null;
      _lastAvailableSequence.value = null;
      _snapshotAppliedAt.value = null;
      _nodes.clear();
      _dependencies.clear();
      _scopes.clear();
      _timeline.clear();
      _warnings.clear();
      _diagnostics.clear();
    });
  }

  /// Closes every `Observable`/reactive collection this store owns. Callers
  /// (in practice, [ConnectionController]) must call this exactly once when
  /// the store is no longer needed — `all_observer` observables are not
  /// garbage-collected implicitly, per the library's explicit-disposal
  /// convention.
  void dispose() {
    _sessionId.close();
    _lastAppliedSequence.close();
    _needsResync.close();
    _coreDroppedEventCount.close();
    _firstAvailableSequence.close();
    _lastAvailableSequence.close();
    _snapshotAppliedAt.close();
    _nodes.close();
    _dependencies.close();
    _scopes.close();
    _timeline.close();
    _warnings.close();
    _diagnostics.close();
  }
}
