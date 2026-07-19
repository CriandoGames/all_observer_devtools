import 'package:devtools_extensions/devtools_extensions.dart';

import '../models/event_batch_model.dart';
import 'protocol_client.dart';
import 'vm_service_connection.dart';

/// Web-only access to DevTools' global [serviceManager]. The transport logic
/// itself lives in [VmServiceConnection], which is VM-testable and captures a
/// single service/isolate pair for the lifetime of a handshake.
final class VmServiceAdapter {
  VmServiceAdapter()
    : _connection = VmServiceConnection(
        service: serviceManager.service,
        selectedIsolateId:
            serviceManager.isolateManager.selectedIsolate.value?.id,
      );

  final VmServiceConnection _connection;

  int get decodeFailureCount => _connection.decodeFailureCount;
  String? get lastDecodeDiagnostic => _connection.lastDecodeDiagnostic;
  Stream<EventBatchModel> get liveEvents => _connection.liveEvents;
  ProtocolClient buildProtocolClient() => _connection.buildProtocolClient();
  void dispose() => _connection.dispose();
}
