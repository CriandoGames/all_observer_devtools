import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/all_observer_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    AllObserverDevTools.debugReset();
    ObserverProtocol.reset();
    ObserverConfig.reset();
  });

  test('public API surface is exported and usable end to end', () {
    expect(AllObserverDevTools.state, BridgeLifecycleState.uninitialized);

    AllObserverDevTools.initialize(
      config: const AllObserverDevToolsConfig(includeValueSummaries: true),
    );

    expect(AllObserverDevTools.state, BridgeLifecycleState.initialized);
    expect(ObserverProtocol.isEnabled, isTrue);

    final Observable<int> counter = Observable<int>(0, name: 'counter');
    counter.value = 1;

    expect(ObserverProtocol.events, isNotEmpty);
    expect(DevToolsServiceExtensions.all, contains('ext.all_observer.getSnapshot'));
    expect(devtoolsProtocolContractVersion, 1);

    AllObserverDevTools.dispose();
    expect(AllObserverDevTools.state, BridgeLifecycleState.disposed);
  });
}
