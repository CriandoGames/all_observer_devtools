import 'dart:async';
import 'dart:convert';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:vm_service/vm_service.dart';

import '../common/service_names.dart';
import '../models/event_batch_model.dart';
import 'protocol_client.dart';

/// The only file in this extension that talks to `package:vm_service` /
/// `serviceManager` directly. Everything else (`ProtocolClient`,
/// `ConnectionController`, `DevToolsStore`) is decoupled from the VM
/// Service API surface and unit-testable with fakes — see
/// `test/connection/connection_controller_test.dart`.
///
/// **Verify against your installed `devtools_app_shared`/`vm_service`
/// versions.** The exact accessor names on the global `serviceManager`
/// (`isolateManager.selectedIsolate`, `service`, `connectedState`) come
/// from the documented DevTools extension pattern, but this file was
/// written without the ability to run `flutter analyze` against the real
/// packages — treat any compile error here the same way earlier
/// mismatches in this project were resolved: it's the single place to fix,
/// nothing downstream needs to change.
final class VmServiceAdapter {
  VmServiceAdapter();

  StreamSubscription<Event>? _extensionEventSubscription;
  StreamController<EventBatchModel>? _liveEventsController;

  /// The isolate this extension talks to. DevTools extensions officially
  /// support only the isolate selected when the bridge was initialized
  /// (implementation spec section 11) — this extension does not aggregate
  /// across isolates.
  String? get _selectedIsolateId => serviceManager.isolateManager.selectedIsolate.value?.id;

  VmService? get _vmService => serviceManager.service;

  /// Decoded batches from the `all_observer:events` extension stream,
  /// filtered to that kind only. Broadcast: [ConnectionController] and any
  /// diagnostics UI can both listen.
  Stream<EventBatchModel> get liveEvents {
    _liveEventsController ??= StreamController<EventBatchModel>.broadcast(
      onListen: _startListening,
      onCancel: _stopListening,
    );
    return _liveEventsController!.stream;
  }

  Future<void> _startListening() async {
    final VmService? service = _vmService;
    if (service == null) {
      return;
    }
    try {
      await service.streamListen(EventStreams.kExtension);
    } on RPCError {
      // Already subscribed elsewhere (e.g. DevTools core, or a previous
      // instance of this extension after a hot restart) — not an error.
    }
    _extensionEventSubscription = service.onExtensionEvent.listen((Event event) {
      if (event.extensionKind != devtoolsEventStreamKind) {
        return;
      }
      final Map<String, dynamic>? data = event.extensionData?.data;
      if (data == null) {
        return;
      }
      try {
        _liveEventsController?.add(
          EventBatchModel.fromJson(Map<String, Object?>.from(data)),
        );
      } catch (_) {
        // A batch this extension cannot decode must never crash the
        // stream — see the ban on silent/guessed interpretation, but a
        // decode failure here is a diagnostics-only concern, not fatal.
      }
    });
  }

  void _stopListening() {
    unawaited(_extensionEventSubscription?.cancel());
    _extensionEventSubscription = null;
  }

  /// Builds a [ProtocolClient] bound to the currently selected isolate.
  /// Call sites should rebuild this (or re-check [_selectedIsolateId]) if
  /// the selected isolate changes, per section 11.
  ProtocolClient buildProtocolClient() => ProtocolClient(callExtension: _callExtension);

  Future<Map<String, Object?>> _callExtension(
    String method,
    Map<String, String> args,
  ) async {
    final VmService? service = _vmService;
    final String? isolateId = _selectedIsolateId;
    if (service == null || isolateId == null) {
      throw StateError(
        'No connected VM Service / selected isolate to call $method on.',
      );
    }
    final Response response = await service.callServiceExtension(
      method,
      isolateId: isolateId,
      args: args,
    );
    final Map<String, dynamic>? json = response.json;
    if (json == null) {
      throw StateError('$method returned an empty response.');
    }
    // Response.json is already a decoded Map — re-encoding/decoding here
    // only normalizes nested types (e.g. List<dynamic> -> List<Object?>)
    // so downstream model parsing sees the same shape it would from a
    // plain `jsonDecode`.
    return jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  }

  void dispose() {
    _stopListening();
    unawaited(_liveEventsController?.close());
    _liveEventsController = null;
  }
}
