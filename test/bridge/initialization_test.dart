import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/all_observer_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AllObserverDevTools.debugReset();
    ObserverProtocol.reset();
    ObserverConfig.reset();
  });

  test('starts uninitialized', () {
    expect(AllObserverDevTools.state, BridgeLifecycleState.uninitialized);
    expect(AllObserverDevTools.debugConfig, isNull);
  });

  test('initialize enables the protocol and registers a consumer', () {
    AllObserverDevTools.initialize();

    expect(AllObserverDevTools.state, BridgeLifecycleState.initialized);
    expect(ObserverProtocol.isEnabled, isTrue);
    expect(ObserverConfig.inspectors, hasLength(1));
    expect(ObserverConfig.inspectors.single, isA<ObserverProtocolInspector>());
  });

  test('initialize forwards config knobs to ObserverProtocolConfig', () {
    AllObserverDevTools.initialize(
      config: const AllObserverDevToolsConfig(
        includeValueSummaries: false,
        includeStackTraces: true,
        eventBufferSize: 42,
      ),
    );

    expect(ObserverProtocol.config.captureValues, isFalse);
    expect(ObserverProtocol.config.captureStackTraces, isTrue);
    expect(ObserverProtocol.config.eventBufferSize, 42);
  });

  test('dispose removes the consumer but leaves the core protocol alone', () {
    AllObserverDevTools.initialize();
    AllObserverDevTools.dispose();

    expect(AllObserverDevTools.state, BridgeLifecycleState.disposed);
    expect(ObserverConfig.inspectors, isEmpty);
    // The core protocol itself is not this package's to disable; only the
    // consumer registration is undone.
    expect(ObserverProtocol.isEnabled, isTrue);
  });

  test('dispose before initialize is safe', () {
    expect(() => AllObserverDevTools.dispose(), returnsNormally);
    expect(AllObserverDevTools.state, BridgeLifecycleState.disposed);
  });
}
