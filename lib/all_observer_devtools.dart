/// Opt-in Flutter DevTools integration for `all_observer`.
///
/// This library is the *runtime bridge* only: it consumes `all_observer`'s
/// Observer Protocol and exposes it over the Dart VM Service
/// (`ext.all_observer.*` service extensions plus batched live events on the
/// `all_observer:events` extension stream). It has no dependency on
/// Flutter DevTools, `devtools_extensions`, or any visual component — the
/// Flutter Web DevTools extension panel that reads this data is a separate
/// build, published alongside this package.
///
/// Usage:
///
/// ```dart
/// import 'package:all_observer_devtools/all_observer_devtools.dart';
///
/// void main() {
///   assert(() {
///     AllObserverDevTools.initialize();
///     return true;
///   }());
///   runApp(const App());
/// }
/// ```
///
/// See [AllObserverDevTools] for the full contract (idempotency, release
/// gating, disposal).
library;

export 'src/bridge/connection_state.dart' show BridgeLifecycleState;
export 'src/bridge/devtools_bridge.dart' show AllObserverDevTools;
export 'src/common/service_names.dart'
    show
        DevToolsErrorCode,
        DevToolsServiceExtensions,
        devtoolsEventStreamKind,
        devtoolsPackageVersion,
        devtoolsProtocolContractVersion;
export 'src/configuration/devtools_config.dart' show AllObserverDevToolsConfig;
export 'src/serialization/protocol_codec.dart' show DevToolsCapability;
