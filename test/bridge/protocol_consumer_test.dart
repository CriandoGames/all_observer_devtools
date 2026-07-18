import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/bridge/protocol_consumer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forwards every event verbatim, in the order received', () {
    final List<ObserverProtocolEvent> received = <ObserverProtocolEvent>[];
    final DevToolsProtocolConsumer consumer = DevToolsProtocolConsumer(
      onEvent: received.add,
    );

    final NodeCreatedEvent created = NodeCreatedEvent(
      protocolVersion: observerProtocolVersion,
      sessionId: 's1',
      eventId: 'event-1',
      sequenceNumber: 1,
      timestampMicros: 1000,
      objectId: const ObserverNodeId(1),
      kind: ObserverNodeKind.observable,
      debugLabel: 'counter',
      debugType: 'int',
    );
    final NodeDisposedEvent disposed = NodeDisposedEvent(
      protocolVersion: observerProtocolVersion,
      sessionId: 's1',
      eventId: 'event-2',
      sequenceNumber: 2,
      timestampMicros: 2000,
      objectId: const ObserverNodeId(1),
      kind: ObserverNodeKind.observable,
      listenerCount: 0,
    );

    consumer.onProtocolEvent(created);
    consumer.onProtocolEvent(disposed);

    expect(received, <ObserverProtocolEvent>[created, disposed]);
  });

  test('is registrable as an ObserverProtocolInspector via ObserverConfig', () {
    final List<ObserverProtocolEvent> received = <ObserverProtocolEvent>[];
    final DevToolsProtocolConsumer consumer = DevToolsProtocolConsumer(
      onEvent: received.add,
    );
    addTearDown(() {
      ObserverProtocol.reset();
      ObserverConfig.reset();
    });

    ObserverProtocol.configure(const ObserverProtocolConfig(enabled: true));
    ObserverConfig.inspectors.add(consumer);

    Observable<int>(0, name: 'counter');

    expect(received, hasLength(1));
    expect(received.single, isA<NodeCreatedEvent>());
  });
}
