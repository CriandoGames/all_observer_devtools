import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/all_observer_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AllObserverDevTools.debugReset();
    ObserverProtocol.reset();
    ObserverConfig.reset();
  });

  test('a second initialize() call is a no-op, even with a different config', () {
    AllObserverDevTools.initialize(
      config: const AllObserverDevToolsConfig(maxBatchSize: 10),
    );
    final AllObserverDevToolsConfig? firstConfig = AllObserverDevTools.debugConfig;

    AllObserverDevTools.initialize(
      config: const AllObserverDevToolsConfig(maxBatchSize: 999),
    );

    expect(AllObserverDevTools.debugConfig, same(firstConfig));
    expect(AllObserverDevTools.debugConfig!.maxBatchSize, 10);
  });

  test('repeated initialize() never registers more than one consumer', () {
    AllObserverDevTools.initialize();
    AllObserverDevTools.initialize();
    AllObserverDevTools.initialize();

    expect(ObserverConfig.inspectors, hasLength(1));
  });

  test(
    'a fresh initialize() after a debugReset() (simulating hot restart) '
    'does not throw despite the VM Service extension names already being '
    'registered in this isolate',
    () {
      AllObserverDevTools.initialize();
      AllObserverDevTools.debugReset(); // static state resets; isolate does not.

      expect(() => AllObserverDevTools.initialize(), returnsNormally);
      expect(AllObserverDevTools.state, BridgeLifecycleState.initialized);
    },
  );
}
