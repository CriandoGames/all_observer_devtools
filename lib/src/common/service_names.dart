/// Stable names and small helpers shared between the runtime bridge and
/// anything that talks to it over the VM Service. Centralized here so the
/// extension UI (a separate consumer, built in a later phase) can depend on
/// the exact same strings instead of re-typing them.
library;

/// Package version of the *protocol contract* this bridge speaks, not the
/// pub.dev package version. Bumped only when the JSON shape of events,
/// snapshots, or service-extension responses changes incompatibly.
const int devtoolsProtocolContractVersion = 1;

/// The `all_observer_devtools` pub.dev package version, reported by
/// `ext.all_observer.getProtocolInfo`. Kept in sync with `pubspec.yaml`
/// manually — there is no reliable way to read a package's own pubspec
/// version at runtime in a Flutter app.
const String devtoolsPackageVersion = '0.1.0';

/// Prefix every `ext.all_observer.*` service extension name shares.
const String serviceExtensionPrefix = 'ext.all_observer';

/// Service extension names, centralized so both the bridge (which registers
/// them) and any client (which calls them) share one source of truth.
abstract final class DevToolsServiceExtensions {
  /// Returns protocol/package version info and capabilities. Takes no
  /// parameters.
  static const String getProtocolInfo =
      '$serviceExtensionPrefix.getProtocolInfo';

  /// Returns a full `ObserverProtocolSnapshot`, encoded. Takes no
  /// parameters.
  static const String getSnapshot = '$serviceExtensionPrefix.getSnapshot';

  /// Returns buffered events with `sequenceNumber` greater than the
  /// `afterSequence` parameter (or all buffered events if omitted/absent).
  static const String getEvents = '$serviceExtensionPrefix.getEvents';

  /// Enables or disables the batching/posting of live events. Parameter:
  /// `enabled` (`"true"` / `"false"`, VM service extensions only pass
  /// string values).
  static const String setStreaming = '$serviceExtensionPrefix.setStreaming';

  /// Clears only the DevTools-side batching buffer local to this bridge
  /// instance. Does not touch the core's own ring buffer or
  /// `droppedEventCount`. Takes no parameters.
  static const String clearBuffer = '$serviceExtensionPrefix.clearBuffer';

  /// Returns lightweight bridge status: session id, streaming flag, current
  /// buffered-event count, initialization state. Takes no parameters.
  static const String getStatus = '$serviceExtensionPrefix.getStatus';

  static const List<String> all = <String>[
    getProtocolInfo,
    getSnapshot,
    getEvents,
    setStreaming,
    clearBuffer,
    getStatus,
  ];
}

/// The `dart:developer` `postEvent` extension-stream kind used to publish
/// batched events. Consumers subscribe to the VM Service `Extension` stream
/// and filter on `event.extensionKind == devtoolsEventStreamKind`.
const String devtoolsEventStreamKind = 'all_observer:events';

/// Structured error codes returned in the `error.code` field of a failed
/// service-extension response. Stable strings, not free-form messages, so a
/// client can branch on them without parsing prose.
abstract final class DevToolsErrorCode {
  static const String unsupportedProtocolVersion =
      'unsupported_protocol_version';
  static const String invalidParameter = 'invalid_parameter';
  static const String bridgeNotInitialized = 'bridge_not_initialized';
  static const String serializationFailed = 'serialization_failed';
  static const String internalError = 'internal_error';
}

/// Builds the standard success envelope:
/// `{"success": true, "protocolVersion": ..., "sessionId": ..., "data": {...}}`.
Map<String, Object?> buildSuccessEnvelope({
  required int protocolVersion,
  required String sessionId,
  required Map<String, Object?> data,
}) => <String, Object?>{
  'success': true,
  'protocolVersion': protocolVersion,
  'sessionId': sessionId,
  'data': data,
};

/// Builds the standard error envelope:
/// `{"success": false, "error": {"code": ..., "message": ...}}`.
///
/// Never includes a stack trace or other internal detail by default — see
/// section 10 of the implementation spec ("Não exponha stack traces internos
/// nas respostas por padrão").
Map<String, Object?> buildErrorEnvelope({
  required String code,
  required String message,
}) => <String, Object?>{
  'success': false,
  'error': <String, Object?>{'code': code, 'message': message},
};
