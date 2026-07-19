import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:vm_service/vm_service.dart';

import '../common/service_names.dart';
import '../models/event_batch_model.dart';
import 'protocol_client.dart';

/// One immutable VM Service/isolate binding.
///
/// Capturing both values prevents a selected-isolate change from splitting a
/// single handshake across two isolates. The UI replaces this object whenever
/// DevTools changes connection or selection.
final class VmServiceConnection {
  VmServiceConnection({
    required VmService? service,
    required String? selectedIsolateId,
  }) : _service = service,
       _selectedIsolateId = selectedIsolateId;

  final VmService? _service;
  final String? _selectedIsolateId;
  StreamSubscription<Event>? _extensionEventSubscription;
  StreamController<EventBatchModel>? _liveEventsController;
  bool _disposed = false;
  int decodeFailureCount = 0;
  String? lastDecodeDiagnostic;

  String? get selectedIsolateId => _selectedIsolateId;

  Stream<EventBatchModel> get liveEvents {
    _liveEventsController ??= StreamController<EventBatchModel>.broadcast(
      onListen: () => unawaited(_startListening()),
      onCancel: _stopListening,
    );
    return _liveEventsController!.stream;
  }

  Future<void> _startListening() async {
    final VmService? service = _service;
    if (service == null || _selectedIsolateId == null) return;
    try {
      await service.streamListen(EventStreams.kExtension);
    } on RPCError catch (error) {
      if (error.code != RPCErrorKind.kStreamAlreadySubscribed.code) {
        _reportTransportFailure('Extension stream subscription', error);
        return;
      }
    } catch (error) {
      _reportTransportFailure('Extension stream subscription', error);
      return;
    }
    if (_disposed) return;
    _extensionEventSubscription = service.onExtensionEvent.listen(
      _onExtensionEvent,
      onError: (Object error, StackTrace stackTrace) {
        _reportTransportFailure('Extension event stream', error);
      },
    );
  }

  void _onExtensionEvent(Event event) {
    if (_disposed) return;
    if (event.extensionKind != devtoolsEventStreamKind) return;
    if (event.isolate?.id != _selectedIsolateId) return;

    final Map<String, dynamic>? data = event.extensionData?.data;
    if (data == null) {
      _reportDecodeFailure(StateError('missing extensionData'));
      return;
    }
    try {
      _liveEventsController?.add(
        EventBatchModel.fromJson(Map<String, Object?>.from(data)),
      );
    } catch (error) {
      _reportDecodeFailure(error);
    }
  }

  void _reportDecodeFailure(Object error) {
    if (_disposed) return;
    decodeFailureCount++;
    lastDecodeDiagnostic =
        'Live event batch decode failed (${error.runtimeType}).';
    developer.log(
      lastDecodeDiagnostic!,
      name: 'all_observer_devtools.extension',
    );
    _liveEventsController?.addError(
      LiveBatchDecodeException(lastDecodeDiagnostic!),
    );
  }

  void _reportTransportFailure(String operation, Object error) {
    if (_disposed) return;
    lastDecodeDiagnostic = '$operation failed (${error.runtimeType}).';
    developer.log(
      lastDecodeDiagnostic!,
      name: 'all_observer_devtools.extension',
    );
    _liveEventsController?.addError(
      LiveBatchTransportException(lastDecodeDiagnostic!),
    );
  }

  void _stopListening() {
    unawaited(_extensionEventSubscription?.cancel());
    _extensionEventSubscription = null;
  }

  ProtocolClient buildProtocolClient() =>
      ProtocolClient(callExtension: _callExtension);

  Future<Map<String, Object?>> _callExtension(
    String method,
    Map<String, String> args,
  ) async {
    final VmService? service = _service;
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
    return jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopListening();
    unawaited(_liveEventsController?.close());
    _liveEventsController = null;
  }
}

final class LiveBatchDecodeException implements Exception {
  const LiveBatchDecodeException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class LiveBatchTransportException implements Exception {
  const LiveBatchTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}
