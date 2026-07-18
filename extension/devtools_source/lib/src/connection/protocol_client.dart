import '../common/service_names.dart';
import '../models/envelope.dart';
import '../models/event_batch_model.dart';
import '../models/protocol_info_model.dart';
import '../models/snapshot_model.dart';
import '../models/status_model.dart';

/// Calls one `ext.all_observer.*` VM Service extension and returns its
/// decoded JSON response (already `jsonDecode`d, not yet envelope-unwrapped).
/// Implemented by a small adapter over `package:vm_service`'s
/// `VmService.callServiceExtension` at the call site — kept as an injected
/// function so [ProtocolClient] has no direct VM Service dependency and is
/// fully unit-testable with a fake.
typedef ExtensionCaller =
    Future<Map<String, Object?>> Function(String method, Map<String, String> args);

/// Typed request/response wrapper around the six `ext.all_observer.*`
/// extensions. Every method unwraps the bridge's success/error envelope
/// (throwing [BridgeResponseError] on failure) and decodes `data` into the
/// matching model — callers never see a raw `Map`.
final class ProtocolClient {
  const ProtocolClient({required ExtensionCaller callExtension})
    : _call = callExtension;

  final ExtensionCaller _call;

  Future<ProtocolInfoModel> getProtocolInfo() async {
    final Map<String, Object?> response = await _call(
      DevToolsServiceExtensionNames.getProtocolInfo,
      const <String, String>{},
    );
    return ProtocolInfoModel.fromJson(unwrapBridgeResponse(response));
  }

  Future<ProtocolSnapshotModel> getSnapshot() async {
    final Map<String, Object?> response = await _call(
      DevToolsServiceExtensionNames.getSnapshot,
      const <String, String>{},
    );
    return ProtocolSnapshotModel.fromJson(unwrapBridgeResponse(response));
  }

  /// Returns buffered events with `sequenceNumber > afterSequence`, or every
  /// buffered event if [afterSequence] is `null`.
  Future<EventBatchModel> getEvents({int? afterSequence}) async {
    final Map<String, Object?> response = await _call(
      DevToolsServiceExtensionNames.getEvents,
      afterSequence == null
          ? const <String, String>{}
          : <String, String>{'afterSequence': '$afterSequence'},
    );
    return EventBatchModel.fromJson(unwrapBridgeResponse(response));
  }

  Future<bool> setStreaming({required bool enabled}) async {
    final Map<String, Object?> response = await _call(
      DevToolsServiceExtensionNames.setStreaming,
      <String, String>{'enabled': '$enabled'},
    );
    final Map<String, Object?> data = unwrapBridgeResponse(response);
    return data['streamingEnabled'] as bool;
  }

  Future<void> clearBuffer() async {
    await _call(DevToolsServiceExtensionNames.clearBuffer, const <String, String>{});
  }

  Future<BridgeStatusModel> getStatus() async {
    final Map<String, Object?> response = await _call(
      DevToolsServiceExtensionNames.getStatus,
      const <String, String>{},
    );
    return BridgeStatusModel.fromJson(unwrapBridgeResponse(response));
  }
}
