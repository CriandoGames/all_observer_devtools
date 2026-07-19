import 'dart:async';

import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/bridge/event_batcher.dart';
import 'package:all_observer_devtools/src/bridge/protocol_consumer.dart';
import 'package:all_observer_devtools/src/bridge/service_extensions.dart';
import 'package:all_observer_devtools/src/configuration/devtools_config.dart';
import 'package:all_observer_devtools_extension/src/connection/connection_controller.dart';
import 'package:all_observer_devtools_extension/src/connection/connection_state.dart';
import 'package:all_observer_devtools_extension/src/connection/protocol_client.dart';
import 'package:all_observer_devtools_extension/src/models/event_batch_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snapshot + backlog + real batcher stream has no loss window', () async {
    ObserverProtocol.configure(
      const ObserverProtocolConfig(
        enabled: true,
        captureValues: true,
        registryEnabled: true,
        eventBufferSize: 100,
      ),
    );
    final stream = StreamController<EventBatchModel>.broadcast();
    final batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(
        maxBatchSize: 1,
        batchInterval: Duration(days: 1),
      ),
      onBatch: (json) => stream.add(EventBatchModel.fromJson(json)),
    );
    final consumer = DevToolsProtocolConsumer(onEvent: batcher.add);
    final registrar = ServiceExtensionRegistrar(
      batcher: batcher,
      packageVersion: 'test',
    );
    Observable<int>? createdAfterSnapshot;
    int appLastSequence = 0;

    Future<Map<String, Object?>> transport(
      String method,
      Map<String, String> args,
    ) async {
      final response = registrar.debugHandle(method, args);
      if (method == 'ext.all_observer.getSnapshot') {
        // The handler already captured its snapshot. These mutations are
        // now observable only through backlog + the genuinely gated batcher.
        // The extension and observed app are separate isolates in DevTools.
        // Scope the consumer to app mutations here so this in-process test
        // does not accidentally observe the DevToolsStore's own observables.
        ObserverConfig.inspectors.add(consumer);
        try {
          createdAfterSnapshot = Observable<int>(0, name: 'after-snapshot');
          createdAfterSnapshot!.value = 7;
          appLastSequence = ObserverProtocol.lastSequenceNumber;
        } finally {
          ObserverConfig.inspectors.remove(consumer);
        }
      }
      return response;
    }

    final controller = ConnectionController(
      client: ProtocolClient(callExtension: transport),
      liveEvents: stream.stream,
    );
    // Remove protocol records created by the in-process DevToolsStore. In a
    // real DevTools session that store lives outside the observed isolate.
    ObserverProtocol.reset();
    ObserverProtocol.configure(
      const ObserverProtocolConfig(
        enabled: true,
        captureValues: true,
        registryEnabled: true,
        eventBufferSize: 100,
      ),
    );
    addTearDown(() async {
      controller.dispose();
      createdAfterSnapshot?.close();
      ObserverConfig.inspectors.remove(consumer);
      batcher.dispose();
      await stream.close();
      ObserverProtocol.reset();
      ObserverConfig.reset();
    });

    await controller.connect();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, DevToolsConnectionState.connected);
    expect(controller.store.lastAppliedSequence, appLastSequence);
    expect(controller.store.nodes, hasLength(1));
    expect(controller.store.nodes.single.valueSummary?.display, '7');
    expect(controller.store.needsResync, isFalse);
  });
}
