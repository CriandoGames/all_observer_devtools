import 'dart:developer' as developer;

import 'package:all_observer/all_observer.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:meta/meta.dart' show visibleForTesting;

import '../common/service_names.dart';
import '../configuration/devtools_config.dart';
import 'connection_state.dart';
import 'event_batcher.dart';
import 'protocol_consumer.dart';
import 'service_extensions.dart';

/// Public entry point for the runtime half of `all_observer_devtools`.
///
/// ```dart
/// void main() {
///   assert(() {
///     AllObserverDevTools.initialize();
///     return true;
///   }());
///   runApp(const App());
/// }
/// ```
///
/// [initialize] is deliberately the *only* thing an app needs to call: no
/// top-level widget, no `BuildContext`, no Navigator integration. It:
///
/// 1. is a no-op in release builds ([kReleaseMode]), regardless of
///    [AllObserverDevToolsConfig.enabled] — this cannot be overridden, by
///    design (section 9 of the implementation spec);
/// 2. is a no-op when [AllObserverDevToolsConfig.enabled] is `false`;
/// 3. is idempotent — a second call while already initialized does nothing,
///    including ignoring a differently-configured second call;
/// 4. enables the Observer Protocol (`ObserverProtocol.configure`) and
///    registers this bridge as the sole `ObserverProtocolInspector`;
/// 5. registers every `ext.all_observer.*` VM Service extension.
///
/// See [dispose] for the one caveat this API cannot fully honor: the Dart
/// VM Service has no `unregisterExtension`, so a disposed bridge's
/// extensions keep responding (reflecting the disposed, idle state) rather
/// than disappearing.
abstract final class AllObserverDevTools {
  static BridgeLifecycleState _state = BridgeLifecycleState.uninitialized;
  static AllObserverDevToolsConfig? _config;
  static EventBatcher? _batcher;
  static DevToolsProtocolConsumer? _consumer;
  static ServiceExtensionRegistrar? _registrar;

  /// Current lifecycle state. Exposed for tests and diagnostics — not part
  /// of the app-facing contract beyond "did initialize() take effect".
  static BridgeLifecycleState get state => _state;

  /// The config [initialize] was actually applied with, or `null` if never
  /// initialized (or disposed).
  @visibleForTesting
  static AllObserverDevToolsConfig? get debugConfig => _config;

  /// The registrar built by the last successful [initialize] call, or
  /// `null` before initialization / after [dispose]. Exposed so tests can
  /// inspect exactly which extension names got registered.
  @visibleForTesting
  static ServiceExtensionRegistrar? get debugRegistrar => _registrar;

  static void initialize({
    AllObserverDevToolsConfig config = const AllObserverDevToolsConfig(),
  }) {
    if (kReleaseMode) {
      return;
    }
    if (!config.enabled) {
      return;
    }
    if (_state == BridgeLifecycleState.initialized) {
      return;
    }

    ObserverProtocol.configure(
      ObserverProtocolConfig(
        enabled: true,
        captureValues: config.includeValueSummaries,
        captureStackTraces: config.includeStackTraces,
        eventBufferSize: config.eventBufferSize,
        registryEnabled: true,
        redactValue: config.redactValue,
      ),
    );

    final EventBatcher batcher = EventBatcher(
      config: config,
      onBatch: _postBatch,
    );
    final DevToolsProtocolConsumer consumer = DevToolsProtocolConsumer(
      onEvent: batcher.add,
    );
    ObserverConfig.inspectors.add(consumer);

    final ServiceExtensionRegistrar registrar = ServiceExtensionRegistrar(
      batcher: batcher,
      packageVersion: devtoolsPackageVersion,
    )..registerAll();

    _config = config;
    _batcher = batcher;
    _consumer = consumer;
    _registrar = registrar;
    _state = BridgeLifecycleState.initialized;
  }

  /// Stops forwarding events and cancels pending timers. Does **not**
  /// unregister VM Service extensions (the platform provides no API for
  /// that): after [dispose], `ext.all_observer.*` calls still succeed, but
  /// report an idle bridge (`streamingEnabled: false`,
  /// `pendingBatchCount: 0`) — `getSnapshot`/`getEvents`/`getStatus` still
  /// read live data straight from `ObserverProtocol`, which this package
  /// never owns or clears.
  static void dispose() {
    if (_consumer != null) {
      ObserverConfig.inspectors.remove(_consumer);
    }
    _batcher?.dispose();
    _batcher = null;
    _consumer = null;
    _registrar = null;
    _config = null;
    _state = BridgeLifecycleState.disposed;
  }

  static void _postBatch(Map<String, Object?> batch) {
    try {
      developer.postEvent(devtoolsEventStreamKind, batch);
    } catch (error) {
      developer.log(
        'Failed to post a DevTools event batch (${error.runtimeType}).',
        name: 'all_observer_devtools',
      );
    }
  }

  /// Test-only hook to fully reset static state between tests, mirroring
  /// `ObserverProtocol.reset()`/`ObserverConfig.reset()`. Not part of the
  /// public app-facing API.
  @visibleForTesting
  static void debugReset() {
    dispose();
    _state = BridgeLifecycleState.uninitialized;
  }
}
