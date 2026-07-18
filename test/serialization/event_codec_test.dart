import 'dart:convert';
import 'dart:io';

import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/serialization/protocol_codec.dart';
import 'package:all_observer_devtools/src/serialization/serialization_error.dart';
import 'package:flutter_test/flutter_test.dart';

const ObserverValueSummary _zero = ObserverValueSummary(type: 'int', display: '0');
const ObserverValueSummary _one = ObserverValueSummary(type: 'int', display: '1');

void main() {
  test('encodeEventBatch(nodeCreated, nodeUpdated) matches the protocol v1 golden fixture', () {
    final NodeCreatedEvent created = NodeCreatedEvent(
      protocolVersion: observerProtocolVersion,
      sessionId: 'session-fixture',
      eventId: 'event-1',
      sequenceNumber: 10,
      timestampMicros: 5000,
      objectId: const ObserverNodeId(1),
      kind: ObserverNodeKind.observable,
      debugLabel: 'counter',
      debugType: 'int',
      initialValueSummary: _zero,
    );
    final NodeUpdatedEvent updated = NodeUpdatedEvent(
      protocolVersion: observerProtocolVersion,
      sessionId: 'session-fixture',
      eventId: 'event-2',
      sequenceNumber: 11,
      timestampMicros: 5100,
      objectId: const ObserverNodeId(1),
      kind: ObserverNodeKind.observable,
      oldValueSummary: _zero,
      newValueSummary: _one,
    );

    final Map<String, Object?> actual = encodeEventBatch(
      sessionId: 'session-fixture',
      events: <ObserverProtocolEvent>[created, updated],
    );

    final Map<String, Object?> expected =
        jsonDecode(File('test/fixtures/protocol_v1/events.json').readAsStringSync())
            as Map<String, Object?>;

    expect(jsonDecode(jsonEncode(actual)), expected);
  });

  test('encodeEventBatch rejects an empty event list', () {
    expect(
      () => encodeEventBatch(sessionId: 's1', events: const <ObserverProtocolEvent>[]),
      throwsA(isA<SerializationError>()),
    );
  });

  test('node id sets are encoded sorted and without duplicates', () {
    final DependenciesChangedEvent event = DependenciesChangedEvent(
      protocolVersion: observerProtocolVersion,
      sessionId: 's1',
      eventId: 'event-1',
      sequenceNumber: 1,
      timestampMicros: 1,
      trackerId: const ObserverNodeId(9),
      runId: 'run-1',
      currentDependencyIds: <ObserverNodeId>{
        const ObserverNodeId(3),
        const ObserverNodeId(1),
        const ObserverNodeId(2),
      },
      addedDependencyIds: <ObserverNodeId>{const ObserverNodeId(2)},
      removedDependencyIds: <ObserverNodeId>{},
    );

    final Map<String, Object?> encoded = encodeEvent(event);

    expect(encoded['currentDependencyIds'], <int>[1, 2, 3]);
    expect(encoded['addedDependencyIds'], <int>[2]);
    expect(encoded['removedDependencyIds'], <int>[]);
  });

  test('warning events carry a nullable objectId', () {
    final WarningRaisedEvent withObject = WarningRaisedEvent(
      protocolVersion: observerProtocolVersion,
      sessionId: 's1',
      eventId: 'event-1',
      sequenceNumber: 1,
      timestampMicros: 1,
      warningCode: 'possible_leak',
      message: 'listener count above threshold',
      severity: ObserverWarningSeverity.warning,
      objectId: const ObserverNodeId(1),
    );
    final WarningRaisedEvent withoutObject = WarningRaisedEvent(
      protocolVersion: observerProtocolVersion,
      sessionId: 's1',
      eventId: 'event-2',
      sequenceNumber: 2,
      timestampMicros: 2,
      warningCode: 'generic',
      message: 'no object attached',
      severity: ObserverWarningSeverity.info,
    );

    expect(encodeEvent(withObject)['objectId'], 1);
    expect(encodeEvent(withoutObject)['objectId'], isNull);
  });
}
