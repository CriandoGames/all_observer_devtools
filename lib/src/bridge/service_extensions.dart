import 'dart:convert';
import 'dart:developer' as developer;

import 'package:all_observer/all_observer.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../common/service_names.dart';
import '../serialization/protocol_codec.dart';
import '../serialization/serialization_error.dart';
import 'event_batcher.dart';

/// Registers and handles every `ext.all_observer.*` VM Service extension
/// (section 10 of the implementation spec). Every handler:
///
/// - returns valid JSON via the standard success/error envelope
///   ([buildSuccessEnvelope]/[buildErrorEnvelope]);
/// - validates its own parameters and returns
///   [DevToolsErrorCode.invalidParameter] rather than throwing;
/// - never lets an exception escape into the reactive system — anything
///   unexpected is caught and reported as [DevToolsErrorCode.internalError];
/// - never includes a raw stack trace in its response.
///
/// The envelope-building logic lives in [debugHandle] (a plain
/// `Map<String, Object?>` in, `Map<String, Object?>` out function with no
/// `dart:developer` types), and [registerAll] wraps it for the VM Service.
/// This split is what makes the handlers testable without a running VM
/// Service.
final class ServiceExtensionRegistrar {
  ServiceExtensionRegistrar({
    required EventBatcher batcher,
    required String packageVersion,
    ExtensionRegistration registerExtension = developer.registerExtension,
  }) : _batcher = batcher,
       _packageVersion = packageVersion,
       _registerExtension = registerExtension;

  final EventBatcher _batcher;
  final String _packageVersion;
  final ExtensionRegistration _registerExtension;
  bool _registered = false;
  static ServiceExtensionRegistrar? _active;

  /// Names actually registered by this instance's last [registerAll] call,
  /// exposed for tests — not part of the public contract.
  final List<String> debugRegisteredNames = <String>[];
  final List<String> debugDuplicateNames = <String>[];
  final Map<String, String> registrationFailures = <String, String>{};

  void registerAll() {
    if (_registered) {
      return;
    }
    _active = this;
    _registered = true;
    for (final String name in DevToolsServiceExtensions.all) {
      _register(name);
    }
  }

  void _register(String name) {
    try {
      _registerExtension(
        name,
        (String method, Map<String, String> parameters) async =>
            developer.ServiceExtensionResponse.result(
              jsonEncode(
                _active?.debugHandle(name, parameters) ??
                    buildErrorEnvelope(
                      code: DevToolsErrorCode.internalError,
                      message: 'Bridge is not initialized.',
                    ),
              ),
            ),
      );
      debugRegisteredNames.add(name);
    } on ArgumentError catch (error) {
      if (error.message == 'Extension already registered: $name') {
        debugDuplicateNames.add(name);
        return;
      }
      registrationFailures[name] = 'ArgumentError';
      developer.log(
        'VM extension registration failed for $name: ArgumentError',
        name: 'all_observer_devtools',
      );
    } catch (error) {
      registrationFailures[name] = error.runtimeType.toString();
      developer.log(
        'VM extension registration failed for $name: ${error.runtimeType}',
        name: 'all_observer_devtools',
      );
    }
  }

  /// Pure request/response logic for [extensionName], independent of
  /// `dart:developer`. Exposed so tests can exercise every handler branch
  /// directly. Never throws: unexpected failures are caught and reported as
  /// [DevToolsErrorCode.internalError].
  @visibleForTesting
  Map<String, Object?> debugHandle(
    String extensionName,
    Map<String, String> parameters,
  ) {
    try {
      return switch (extensionName) {
        DevToolsServiceExtensions.getProtocolInfo => _ok(
          encodeProtocolInfo(packageVersion: _packageVersion),
        ),
        DevToolsServiceExtensions.getSnapshot => _handleGetSnapshot(),
        DevToolsServiceExtensions.getEvents => _handleGetEvents(parameters),
        DevToolsServiceExtensions.setStreaming => _handleSetStreaming(
          parameters,
        ),
        DevToolsServiceExtensions.clearBuffer => _handleClearBuffer(),
        DevToolsServiceExtensions.getStatus => _handleGetStatus(),
        _ => _err(
          DevToolsErrorCode.invalidParameter,
          'Unknown extension "$extensionName"',
        ),
      };
    } catch (error) {
      developer.log(
        'Service extension handler failed (${error.runtimeType}).',
        name: 'all_observer_devtools',
      );
      return _err(
        DevToolsErrorCode.internalError,
        'Unexpected internal bridge error (${error.runtimeType}).',
      );
    }
  }

  Map<String, Object?> _handleGetSnapshot() {
    try {
      return _ok(encodeSnapshot(ObserverProtocol.snapshot()));
    } on SerializationError catch (error) {
      return _err(DevToolsErrorCode.serializationFailed, error.message);
    }
  }

  Map<String, Object?> _handleGetEvents(Map<String, String> parameters) {
    int afterSequence = 0;
    final String? afterParam = parameters['afterSequence'];
    if (afterParam != null) {
      final int? parsed = int.tryParse(afterParam);
      if (parsed == null) {
        return _err(
          DevToolsErrorCode.invalidParameter,
          'afterSequence must be an integer, got "$afterParam"',
        );
      }
      afterSequence = parsed;
    }
    final List<ObserverProtocolEvent> events = ObserverProtocol.events
        .where((event) => event.sequenceNumber > afterSequence)
        .toList();
    if (events.isEmpty) {
      return _ok(
        encodeEmptyEventBatch(
          sessionId: ObserverProtocol.sessionId,
          lastSequenceNumber: ObserverProtocol.lastSequenceNumber,
        ),
      );
    }
    try {
      return _ok(
        encodeEventBatch(sessionId: ObserverProtocol.sessionId, events: events),
      );
    } on SerializationError catch (error) {
      return _err(DevToolsErrorCode.serializationFailed, error.message);
    }
  }

  Map<String, Object?> _handleSetStreaming(Map<String, String> parameters) {
    final String? value = parameters['enabled'];
    if (value != 'true' && value != 'false') {
      return _err(
        DevToolsErrorCode.invalidParameter,
        'enabled must be "true" or "false", got "${value ?? '<missing>'}"',
      );
    }
    _batcher.setStreamingEnabled(value == 'true');
    return _ok(<String, Object?>{
      'streamingEnabled': _batcher.streamingEnabled,
    });
  }

  Map<String, Object?> _handleClearBuffer() {
    _batcher.clearPending();
    return _ok(<String, Object?>{'cleared': true});
  }

  Map<String, Object?> _handleGetStatus() {
    final Map<String, Object?> status = encodeStatus(
      sessionId: ObserverProtocol.sessionId,
      streamingEnabled: _batcher.streamingEnabled,
      coreBufferedEventCount: ObserverProtocol.events.length,
      pendingBatchCount: _batcher.pendingCount,
      droppedEventCount: ObserverProtocol.droppedEventCount,
      transportDroppedEventCount: _batcher.transportDroppedEventCount,
      transportOversizedEventCount: _batcher.transportOversizedEventCount,
      lastSequenceNumber: ObserverProtocol.lastSequenceNumber,
    );
    status.addAll(<String, Object?>{
      'registeredExtensionNames': List<String>.unmodifiable(
        debugRegisteredNames,
      ),
      'duplicateExtensionNames': List<String>.unmodifiable(debugDuplicateNames),
      'registrationFailures': Map<String, String>.unmodifiable(
        registrationFailures,
      ),
      'servedSessionId': ObserverProtocol.sessionId,
      'bridgeState': _batcher.isDisposed ? 'disposed' : 'initialized',
      'protocolVersion': observerProtocolVersion,
    });
    return _ok(status);
  }

  Map<String, Object?> _ok(Map<String, Object?> data) => buildSuccessEnvelope(
    protocolVersion: observerProtocolVersion,
    sessionId: ObserverProtocol.sessionId,
    data: data,
  );

  /// Structured, application-level errors are returned as a normal
  /// `.result()` with `"success": false` in the body (per section 10's
  /// example envelope), not as a VM Service RPC-level error — that keeps
  /// the error shape identical for every client regardless of how the VM
  /// Service transport itself surfaces RPC failures.
  Map<String, Object?> _err(String code, String message) =>
      buildErrorEnvelope(code: code, message: message);
}

typedef ExtensionRegistration =
    void Function(String method, developer.ServiceExtensionHandler handler);
