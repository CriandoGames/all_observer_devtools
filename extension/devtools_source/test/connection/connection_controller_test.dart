import 'dart:async';

import 'package:all_observer_devtools_extension/src/connection/connection_controller.dart';
import 'package:all_observer_devtools_extension/src/connection/connection_state.dart';
import 'package:all_observer_devtools_extension/src/connection/protocol_client.dart';
import 'package:all_observer_devtools_extension/src/models/event_batch_model.dart';
import 'package:all_observer_devtools_extension/src/models/protocol_event_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _ok(Map<String, Object?> data) => <String, Object?>{
  'success': true,
  'protocolVersion': 1,
  'sessionId': 's1',
  'data': data,
};

Map<String, Object?> _protocolInfoJson({int protocolVersion = 1}) => <String, Object?>{
  'protocolVersion': protocolVersion,
  'packageVersion': '0.1.0',
  'minimumSupportedProtocolVersion': protocolVersion,
  'maximumSupportedProtocolVersion': protocolVersion,
  'capabilities': <String>['snapshot', 'event_stream'],
};

Map<String, Object?> _snapshotJson({
  required String sessionId,
  required int lastSequenceNumber,
}) => <String, Object?>{
  'protocolVersion': 1,
  'sessionId': sessionId,
  'generatedAtMicros': 0,
  'lastSequenceNumber': lastSequenceNumber,
  'droppedEventCount': 0,
  'firstAvailableSequence': null,
  'lastAvailableSequence': null,
  'nodes': const <Object?>[],
  'dependencies': const <Object?>[],
  'scopes': const <Object?>[],
};

Map<String, Object?> _nodeCreatedEventJson({
  required String sessionId,
  required int sequenceNumber,
  required int objectId,
}) => <String, Object?>{
  'protocolVersion': 1,
  'sessionId': sessionId,
  'eventId': 'event-$sequenceNumber',
  'sequenceNumber': sequenceNumber,
  'timestampMicros': sequenceNumber * 1000,
  'eventType': 'nodeCreated',
  'objectId': objectId,
  'kind': 'observable',
  'debugLabel': 'node$objectId',
  'debugType': 'int',
  'initialValueSummary': null,
};

/// Minimal fake VM Service adapter: canned protocol-info/snapshot
/// responses, with the snapshot response advancing through a queue so a
/// test can simulate "state after resync differs from state before".
final class _FakeExtensionCaller {
  _FakeExtensionCaller({
    required this.protocolInfoJson,
    required List<Map<String, Object?>> snapshotJsonQueue,
  }) : _snapshotQueue = List<Map<String, Object?>>.of(snapshotJsonQueue);

  final Map<String, Object?> protocolInfoJson;
  final List<Map<String, Object?>> _snapshotQueue;
  int getSnapshotCallCount = 0;
  bool streamingEnabled = false;

  Future<Map<String, Object?>> call(String method, Map<String, String> args) async {
    switch (method) {
      case 'ext.all_observer.getProtocolInfo':
        return _ok(protocolInfoJson);
      case 'ext.all_observer.getSnapshot':
        getSnapshotCallCount++;
        final Map<String, Object?> next = _snapshotQueue.length > 1
            ? _snapshotQueue.removeAt(0)
            : _snapshotQueue.first;
        return _ok(next);
      case 'ext.all_observer.setStreaming':
        streamingEnabled = args['enabled'] == 'true';
        return _ok(<String, Object?>{'streamingEnabled': streamingEnabled});
      default:
        throw StateError('Unexpected method in test fake: $method');
    }
  }
}

void main() {
  group('normal connection flow', () {
    test('reaches connected after protocol info + snapshot', () async {
      final fake = _FakeExtensionCaller(
        protocolInfoJson: _protocolInfoJson(),
        snapshotJsonQueue: [_snapshotJson(sessionId: 's1', lastSequenceNumber: 0)],
      );
      final controller = ConnectionController(
        client: ProtocolClient(callExtension: fake.call),
        liveEvents: const Stream<EventBatchModel>.empty(),
      );
      addTearDown(controller.dispose);

      await controller.connect();

      expect(controller.state, DevToolsConnectionState.connected);
      expect(controller.store.sessionId, 's1');
      expect(fake.streamingEnabled, isTrue);
    });
  });

  group('protocol compatibility', () {
    test('an incompatible protocol version stops before requesting a snapshot', () async {
      final fake = _FakeExtensionCaller(
        protocolInfoJson: _protocolInfoJson(protocolVersion: 2),
        snapshotJsonQueue: [_snapshotJson(sessionId: 's1', lastSequenceNumber: 0)],
      );
      final controller = ConnectionController(
        client: ProtocolClient(callExtension: fake.call),
        liveEvents: const Stream<EventBatchModel>.empty(),
      );
      addTearDown(controller.dispose);

      await controller.connect();

      expect(controller.state, DevToolsConnectionState.incompatible);
      expect(fake.getSnapshotCallCount, 0);
    });
  });

  group('snapshot/event race (section 12)', () {
    test('an event that arrives while the snapshot is loading is buffered then applied', () async {
      final liveController = StreamController<EventBatchModel>.broadcast();
      addTearDown(liveController.close);

      // Snapshot resolves at lastSequenceNumber=0; an event for sequence 1
      // is pushed onto the live stream "during" the snapshot fetch by
      // reacting to getSnapshot being called.
      late _FakeExtensionCaller fake;
      fake = _FakeExtensionCaller(
        protocolInfoJson: _protocolInfoJson(),
        snapshotJsonQueue: [_snapshotJson(sessionId: 's1', lastSequenceNumber: 0)],
      );
      final delayedCaller = (String method, Map<String, String> args) async {
        final result = fake.call(method, args);
        if (method == 'ext.all_observer.getSnapshot') {
          liveController.add(
            EventBatchModel(
              protocolVersion: 1,
              sessionId: 's1',
              firstSequenceNumber: 1,
              lastSequenceNumber: 1,
              events: [
                ProtocolEventModel.fromJson(
                  _nodeCreatedEventJson(
                    sessionId: 's1',
                    sequenceNumber: 1,
                    objectId: 42,
                  ),
                ),
              ],
            ),
          );
        }
        return result;
      };
      final controller = ConnectionController(
        client: ProtocolClient(callExtension: delayedCaller),
        liveEvents: liveController.stream,
      );
      addTearDown(controller.dispose);

      await controller.connect();
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, DevToolsConnectionState.connected);
      expect(controller.store.lastAppliedSequence, 1);
      expect(controller.store.nodeById(42), isNotNull);
    });
  });

  group('gap-triggered resync', () {
    test('a sequence gap on the live stream triggers a fresh snapshot and recovers', () async {
      final liveController = StreamController<EventBatchModel>.broadcast();
      addTearDown(liveController.close);
      final fake = _FakeExtensionCaller(
        protocolInfoJson: _protocolInfoJson(),
        snapshotJsonQueue: [
          _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
          _snapshotJson(sessionId: 's1', lastSequenceNumber: 10),
        ],
      );
      final controller = ConnectionController(
        client: ProtocolClient(callExtension: fake.call),
        liveEvents: liveController.stream,
      );
      addTearDown(controller.dispose);

      await controller.connect();
      expect(controller.state, DevToolsConnectionState.connected);

      // Sequence 5 while the store is only caught up to 0: a gap.
      liveController.add(
        EventBatchModel(
          protocolVersion: 1,
          sessionId: 's1',
          firstSequenceNumber: 5,
          lastSequenceNumber: 5,
          events: [
            ProtocolEventModel.fromJson(
              _nodeCreatedEventJson(sessionId: 's1', sequenceNumber: 5, objectId: 7),
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(fake.getSnapshotCallCount, 2);
      expect(controller.state, DevToolsConnectionState.connected);
      expect(controller.store.lastAppliedSequence, 10);
      expect(controller.store.needsResync, isFalse);
    });
  });
}
