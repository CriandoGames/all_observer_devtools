import 'package:all_observer_devtools_extension/src/models/dependency_model.dart';
import 'package:all_observer_devtools_extension/src/models/node_model.dart';
import 'package:all_observer_devtools_extension/src/models/protocol_event_model.dart';
import 'package:all_observer_devtools_extension/src/models/scope_model.dart';
import 'package:all_observer_devtools_extension/src/models/snapshot_model.dart';
import 'package:all_observer_devtools_extension/src/store/devtools_store.dart';
import 'package:flutter_test/flutter_test.dart';

ProtocolSnapshotModel _emptySnapshot({
  required String sessionId,
  required int lastSequenceNumber,
  List<NodeModel> nodes = const [],
  List<DependencyModel> dependencies = const [],
  List<ScopeModel> scopes = const [],
}) => ProtocolSnapshotModel(
  protocolVersion: 1,
  sessionId: sessionId,
  generatedAtMicros: 0,
  lastSequenceNumber: lastSequenceNumber,
  droppedEventCount: 0,
  firstAvailableSequence: nodes.isEmpty ? null : 1,
  lastAvailableSequence: nodes.isEmpty ? null : lastSequenceNumber,
  nodes: nodes,
  dependencies: dependencies,
  scopes: scopes,
);

NodeCreatedEventModel _created({
  required String sessionId,
  required int sequenceNumber,
  required int objectId,
  String kind = 'observable',
}) => NodeCreatedEventModel(
  protocolVersion: 1,
  sessionId: sessionId,
  eventId: 'event-$sequenceNumber',
  sequenceNumber: sequenceNumber,
  timestampMicros: sequenceNumber * 1000,
  objectId: objectId,
  kind: kind,
  debugLabel: 'node$objectId',
  debugType: 'int',
);

NodeUpdatedEventModel _updated({
  required String sessionId,
  required int sequenceNumber,
  required int objectId,
}) => NodeUpdatedEventModel(
  protocolVersion: 1,
  sessionId: sessionId,
  eventId: 'event-$sequenceNumber',
  sequenceNumber: sequenceNumber,
  timestampMicros: sequenceNumber * 1000,
  objectId: objectId,
  kind: 'observable',
);

NodeDisposedEventModel _disposed({
  required String sessionId,
  required int sequenceNumber,
  required int objectId,
}) => NodeDisposedEventModel(
  protocolVersion: 1,
  sessionId: sessionId,
  eventId: 'event-$sequenceNumber',
  sequenceNumber: sequenceNumber,
  timestampMicros: sequenceNumber * 1000,
  objectId: objectId,
  kind: 'observable',
  listenerCount: 0,
);

DependenciesChangedEventModel _depsChanged({
  required String sessionId,
  required int sequenceNumber,
  required int trackerId,
  required List<int> current,
  List<int> added = const [],
  List<int> removed = const [],
}) => DependenciesChangedEventModel(
  protocolVersion: 1,
  sessionId: sessionId,
  eventId: 'event-$sequenceNumber',
  sequenceNumber: sequenceNumber,
  timestampMicros: sequenceNumber * 1000,
  trackerId: trackerId,
  runId: 'run-$sequenceNumber',
  currentDependencyIds: current,
  addedDependencyIds: added,
  removedDependencyIds: removed,
);

void main() {
  group('snapshot followed by events (section 12/31)', () {
    test('applies only events with sequenceNumber > snapshot.lastSequenceNumber', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 's1', lastSequenceNumber: 100));

      final result = store.applyEvents([
        _created(sessionId: 's1', sequenceNumber: 99, objectId: 1),
        _created(sessionId: 's1', sequenceNumber: 100, objectId: 2),
        _created(sessionId: 's1', sequenceNumber: 101, objectId: 3),
        _created(sessionId: 's1', sequenceNumber: 102, objectId: 4),
      ]);

      expect(result.appliedCount, 2);
      expect(result.duplicateCount, 2);
      expect(store.lastAppliedSequence, 102);
      expect(store.nodes.map((n) => n.objectId), containsAll([3, 4]));
      expect(store.nodes.map((n) => n.objectId), isNot(contains(1)));
    });
  });

  group('sequence gap (section 12/17/31)', () {
    test('detects a gap, flags needsResync, and stops applying', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 's1', lastSequenceNumber: 100));

      final result = store.applyEvents([
        _created(sessionId: 's1', sequenceNumber: 105, objectId: 1),
      ]);

      expect(result.gapDetected, isTrue);
      expect(store.needsResync, isTrue);
      expect(store.lastAppliedSequence, 100); // unchanged
      expect(store.nodes, isEmpty); // the gapped event itself is not applied
      expect(store.diagnostics.single.code, 'sequence_gap');
    });

    test('further events are ignored once needsResync is set, until a new snapshot arrives', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 's1', lastSequenceNumber: 100));
      store.applyEvents([_created(sessionId: 's1', sequenceNumber: 105, objectId: 1)]);
      expect(store.needsResync, isTrue);

      store.applyEvents([_created(sessionId: 's1', sequenceNumber: 106, objectId: 2)]);
      expect(store.nodes, isEmpty);

      store.applySnapshot(
        _emptySnapshot(
          sessionId: 's1',
          lastSequenceNumber: 106,
          nodes: [
            const NodeModel(
              objectId: 2,
              kind: 'observable',
              debugLabel: 'node2',
              debugType: 'int',
              createdAtMicros: 106000,
            ),
          ],
        ),
      );
      expect(store.needsResync, isFalse);
      expect(store.nodes.single.objectId, 2);
    });
  });

  group('session isolation (section 17/19/31)', () {
    test('events from a foreign session are never applied', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 'session-A', lastSequenceNumber: 10));

      final result = store.applyEvents([
        _created(sessionId: 'session-B', sequenceNumber: 11, objectId: 1),
      ]);

      expect(result.foreignSessionCount, 1);
      expect(result.appliedCount, 0);
      expect(store.sessionId, 'session-A');
      expect(store.nodes, isEmpty);
    });

    test('a new snapshot for a different session replaces state and archives the timeline', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 'session-A', lastSequenceNumber: 10));
      store.applyEvents([_created(sessionId: 'session-A', sequenceNumber: 11, objectId: 1)]);
      expect(store.timeline, hasLength(1));

      store.applySnapshot(_emptySnapshot(sessionId: 'session-B', lastSequenceNumber: 0));

      expect(store.sessionId, 'session-B');
      expect(store.timeline, isEmpty);
      expect(store.nodes, isEmpty);
      expect(store.lastAppliedSequence, 0);
    });
  });

  group('duplicate events', () {
    test('an event already represented by the snapshot is not applied twice', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 's1', lastSequenceNumber: 5));

      final first = store.applyEvents([
        _created(sessionId: 's1', sequenceNumber: 6, objectId: 1),
      ]);
      final second = store.applyEvents([
        _created(sessionId: 's1', sequenceNumber: 6, objectId: 1),
      ]);

      expect(first.appliedCount, 1);
      expect(second.appliedCount, 0);
      expect(second.duplicateCount, 1);
      expect(store.nodes, hasLength(1));
    });
  });

  group('unknown node references (section 31)', () {
    test('update for a node the store never saw flags needsResync, not a crash', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 's1', lastSequenceNumber: 0));

      final result = store.applyEvents([
        _updated(sessionId: 's1', sequenceNumber: 1, objectId: 999),
      ]);

      expect(() => result, returnsNormally);
      expect(store.needsResync, isTrue);
      expect(
        store.diagnostics.any((d) => d.code == 'update_for_unknown_node'),
        isTrue,
      );
    });
  });

  group('dependency edges on dispose', () {
    test('disposing a node removes it from every dependency set (mirrors core registry)', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(
        _emptySnapshot(
          sessionId: 's1',
          lastSequenceNumber: 0,
          nodes: [
            const NodeModel(
              objectId: 1,
              kind: 'observable',
              debugLabel: 'source',
              debugType: 'int',
              createdAtMicros: 0,
            ),
            const NodeModel(
              objectId: 2,
              kind: 'computed',
              debugLabel: 'doubled',
              debugType: 'int',
              createdAtMicros: 0,
            ),
          ],
        ),
      );
      store.applyEvents([
        _depsChanged(sessionId: 's1', sequenceNumber: 1, trackerId: 2, current: [1]),
      ]);
      expect(store.dependenciesOf(2), {1});

      store.applyEvents([_disposed(sessionId: 's1', sequenceNumber: 2, objectId: 1)]);

      expect(store.dependenciesOf(2), isEmpty);
      expect(store.nodeById(1)!.isDisposed, isTrue);
    });
  });

  group('dependenciesChanged with an empty set', () {
    test('removes the tracker entry instead of storing an empty set', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 's1', lastSequenceNumber: 0));
      store.applyEvents([
        _depsChanged(sessionId: 's1', sequenceNumber: 1, trackerId: 5, current: [1, 2]),
      ]);
      expect(store.dependencies, hasLength(1));

      store.applyEvents([
        _depsChanged(sessionId: 's1', sequenceNumber: 2, trackerId: 5, current: const []),
      ]);

      expect(store.dependencies, isEmpty);
    });
  });

  group('clear()', () {
    test('discards the session entirely, not just the events', () {
      final store = DevToolsStore();
      addTearDown(store.dispose);
      store.applySnapshot(_emptySnapshot(sessionId: 's1', lastSequenceNumber: 10));

      store.clear();

      expect(store.sessionId, isNull);
      expect(store.lastAppliedSequence, 0);
      expect(store.nodes, isEmpty);
    });
  });
}
