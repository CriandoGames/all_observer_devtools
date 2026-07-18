/// Mirrors `DevToolsServiceExtensions`/`devtoolsEventStreamKind` in the
/// runtime bridge (`all_observer_devtools/lib/src/common/service_names.dart`).
/// Duplicated rather than imported: this extension app intentionally does
/// not depend on the bridge package (see the README's package-layout
/// note) — the two communicate only through the VM Service JSON wire
/// contract, never through shared Dart types.
abstract final class DevToolsServiceExtensionNames {
  static const String getProtocolInfo = 'ext.all_observer.getProtocolInfo';
  static const String getSnapshot = 'ext.all_observer.getSnapshot';
  static const String getEvents = 'ext.all_observer.getEvents';
  static const String setStreaming = 'ext.all_observer.setStreaming';
  static const String clearBuffer = 'ext.all_observer.clearBuffer';
  static const String getStatus = 'ext.all_observer.getStatus';
}

/// The `dart:developer` `postEvent` extension-stream kind the bridge posts
/// batched live events on.
const String devtoolsEventStreamKind = 'all_observer:events';

/// The only protocol contract version this extension understands. Compared
/// against `ProtocolInfoModel` on every connection — see
/// `ConnectionController._checkCompatibility`.
const int extensionSupportedProtocolVersion = 1;
