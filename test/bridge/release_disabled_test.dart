import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/all_observer_devtools.dart';
import 'package:flutter_test/flutter_test.dart';

/// True `kReleaseMode` gating (section 9 of the implementation spec) can
/// only be exercised by actually compiling a release build — `flutter_test`
/// always runs in debug/JIT mode, so `kReleaseMode` is `false` for the
/// entire test suite and cannot be flipped from Dart code. That half of the
/// guarantee is verified by `flutter build ... --release` plus a manual
/// check that no `ext.all_observer.*` extension responds (tracked as a CI
/// step, not a unit test — see the package README's Security section).
///
/// What *is* unit-testable, and is exactly as load-bearing for "never
/// active without explicit consent", is the `enabled: false` config gate:
/// it takes the identical early-return path in
/// `AllObserverDevTools.initialize` as the release check.
void main() {
  tearDown(() {
    AllObserverDevTools.debugReset();
    ObserverProtocol.reset();
    ObserverConfig.reset();
  });

  test('enabled: false is a full no-op', () {
    AllObserverDevTools.initialize(
      config: const AllObserverDevToolsConfig(enabled: false),
    );

    expect(AllObserverDevTools.state, BridgeLifecycleState.uninitialized);
    expect(AllObserverDevTools.debugConfig, isNull);
    expect(ObserverProtocol.isEnabled, isFalse);
    expect(ObserverConfig.inspectors, isEmpty);
  });
}
