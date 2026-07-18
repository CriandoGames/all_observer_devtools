/// Raised when a service-extension response does not match the bridge's
/// `{success, protocolVersion, sessionId, data}` /
/// `{success: false, error: {code, message}}` envelope contract
/// (`buildSuccessEnvelope`/`buildErrorEnvelope` in the runtime bridge).
final class BridgeResponseError extends Error {
  BridgeResponseError(this.code, this.message);

  /// Structured error code from the bridge (see `DevToolsErrorCode`), or
  /// `'malformed_envelope'` if the response wasn't even shaped like a
  /// bridge response.
  final String code;
  final String message;

  @override
  String toString() => 'BridgeResponseError($code): $message';
}

/// Unwraps a `ext.all_observer.*` JSON response, returning the `data`
/// object on success and throwing [BridgeResponseError] on a structured
/// failure or a malformed envelope. Every service-extension call in this
/// extension goes through this — no ad hoc envelope parsing elsewhere.
Map<String, Object?> unwrapBridgeResponse(Map<String, Object?> json) {
  final Object? success = json['success'];
  if (success == true) {
    final Object? data = json['data'];
    if (data is Map<String, Object?>) {
      return data;
    }
    throw BridgeResponseError(
      'malformed_envelope',
      'Success response missing a "data" object: $json',
    );
  }
  if (success == false) {
    final Object? error = json['error'];
    if (error is Map<String, Object?>) {
      throw BridgeResponseError(
        (error['code'] as String?) ?? 'unknown',
        (error['message'] as String?) ?? 'No message provided',
      );
    }
    throw BridgeResponseError(
      'malformed_envelope',
      'Failure response missing an "error" object: $json',
    );
  }
  throw BridgeResponseError(
    'malformed_envelope',
    'Response missing a boolean "success" field: $json',
  );
}
