import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/bridge/event_batcher.dart';
import 'package:all_observer_devtools/src/bridge/service_extensions.dart';
import 'package:all_observer_devtools/src/configuration/devtools_config.dart';
import 'package:all_observer_devtools_extension/src/connection/protocol_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EventBatcher batcher;
  late ServiceExtensionRegistrar registrar;
  late ProtocolClient client;

  setUp(() {
    ObserverProtocol.configure(
      const ObserverProtocolConfig(enabled: true, eventBufferSize: 2),
    );
    batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(),
      onBatch: (_) {},
    );
    registrar = ServiceExtensionRegistrar(
      batcher: batcher,
      packageVersion: 'test',
    );
    client = ProtocolClient(
      callExtension: (method, args) async =>
          registrar.debugHandle(method, args),
    );
  });

  tearDown(() {
    batcher.dispose();
    ObserverProtocol.reset();
    ObserverConfig.reset();
  });

  test(
    'registrar -> client -> model decodes empty, one and evicted ranges',
    () async {
      final empty = await client.getEvents(afterSequence: 0);
      expect(empty.events, isEmpty);
      expect(empty.sessionId, ObserverProtocol.sessionId);

      final value = Observable<int>(0, name: 'value');
      addTearDown(value.close);
      final afterCreate = ObserverProtocol.lastSequenceNumber;
      value.value = 1;
      final one = await client.getEvents(afterSequence: afterCreate);
      expect(one.events, hasLength(1));

      value.value = 2;
      value.value = 3;
      value.value = 4;
      final evicted = await client.getEvents(afterSequence: 0);
      expect(evicted.events, hasLength(2));
      expect(evicted.firstSequenceNumber, evicted.events.first.sequenceNumber);

      final oldSession = evicted.sessionId;
      ObserverProtocol.reset();
      ObserverProtocol.configure(
        const ObserverProtocolConfig(enabled: true, eventBufferSize: 2),
      );
      final changed = await client.getEvents(afterSequence: 0);
      expect(changed.events, isEmpty);
      expect(changed.sessionId, isNot(oldSession));
    },
  );

  test(
    'decodes several events and an afterSequence at the current tail',
    () async {
      ObserverProtocol.reset();
      ObserverProtocol.configure(
        const ObserverProtocolConfig(enabled: true, eventBufferSize: 10),
      );
      final value = Observable<int>(0, name: 'many-events');
      addTearDown(value.close);
      final afterCreate = ObserverProtocol.lastSequenceNumber;
      value
        ..value = 1
        ..value = 2
        ..value = 3;

      final several = await client.getEvents(afterSequence: afterCreate);
      expect(several.events, hasLength(3));
      expect(
        several.events.map((event) => event.sequenceNumber),
        orderedEquals(<int>[afterCreate + 1, afterCreate + 2, afterCreate + 3]),
      );

      final currentTail = ObserverProtocol.lastSequenceNumber;
      final atTail = await client.getEvents(afterSequence: currentTail);
      expect(atTail.events, isEmpty);
      expect(atTail.firstSequenceNumber, isNull);
      expect(atTail.lastSequenceNumber, currentTail);
    },
  );
}
