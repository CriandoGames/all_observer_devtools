import 'dart:convert';
import 'dart:developer' as developer;

import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/bridge/event_batcher.dart';
import 'package:all_observer_devtools/src/bridge/service_extensions.dart';
import 'package:all_observer_devtools/src/common/service_names.dart';
import 'package:all_observer_devtools/src/configuration/devtools_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(
    () =>
        ObserverProtocol.configure(const ObserverProtocolConfig(enabled: true)),
  );
  tearDown(() {
    ObserverProtocol.reset();
    ObserverConfig.reset();
  });

  EventBatcher createBatcher() =>
      EventBatcher(config: const AllObserverDevToolsConfig(), onBatch: (_) {});

  test('successful and repeated initialization register each name once', () {
    final calls = <String>[];
    final batcher = createBatcher();
    addTearDown(batcher.dispose);
    final registrar = ServiceExtensionRegistrar(
      batcher: batcher,
      packageVersion: 'test',
      registerExtension: (name, handler) => calls.add(name),
    );
    registrar
      ..registerAll()
      ..registerAll();

    expect(calls, DevToolsServiceExtensions.all);
    expect(registrar.registrationFailures, isEmpty);
  });

  test(
    'expected duplicate is distinct from unexpected registration failure',
    () {
      final batcher = createBatcher();
      addTearDown(batcher.dispose);
      final registrar = ServiceExtensionRegistrar(
        batcher: batcher,
        packageVersion: 'test',
        registerExtension: (name, handler) {
          if (name == DevToolsServiceExtensions.getSnapshot) {
            throw ArgumentError('Extension already registered: $name');
          }
          if (name == DevToolsServiceExtensions.getEvents) {
            throw StateError('permission denied and sensitive detail');
          }
        },
      )..registerAll();

      expect(registrar.debugDuplicateNames, <String>[
        DevToolsServiceExtensions.getSnapshot,
      ]);
      expect(
        registrar.registrationFailures,
        containsPair(DevToolsServiceExtensions.getEvents, 'StateError'),
      );
      expect(
        registrar.registrationFailures.toString(),
        isNot(contains('sensitive detail')),
      );
    },
  );

  test(
    'old registered handler routes to current batcher after hot restart',
    () async {
      final handlers = <String, developer.ServiceExtensionHandler>{};
      final oldBatcher = createBatcher();
      final newBatcher = createBatcher()..setStreamingEnabled(true);
      addTearDown(oldBatcher.dispose);
      addTearDown(newBatcher.dispose);

      ServiceExtensionRegistrar(
        batcher: oldBatcher,
        packageVersion: 'old',
        registerExtension: (name, handler) => handlers[name] = handler,
      ).registerAll();
      ServiceExtensionRegistrar(
        batcher: newBatcher,
        packageVersion: 'new',
        registerExtension: (name, handler) =>
            throw ArgumentError('Extension already registered: $name'),
      ).registerAll();

      final response = await handlers[DevToolsServiceExtensions.getStatus]!(
        DevToolsServiceExtensions.getStatus,
        const <String, String>{},
      );
      final json = jsonDecode(response.result!) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;
      expect(data['streamingEnabled'], isTrue);
      expect(data['bridgeState'], 'initialized');
      expect(data['servedSessionId'], ObserverProtocol.sessionId);
    },
  );
}
