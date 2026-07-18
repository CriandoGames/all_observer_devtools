/// Raised when an [ObserverProtocolEvent] or `ObserverProtocolSnapshot`
/// cannot be encoded to the JSON contract — for example an unrecognized
/// event subtype (the codec is a closed `switch`, not `dynamic` dispatch, so
/// this can only happen if the core protocol adds an event type this
/// package's codec has not been updated for).
///
/// Callers (the batcher, the service-extension handlers) must catch this and
/// convert it into a dropped-event count or a structured error envelope —
/// never let it propagate into the reactive system or crash the host app.
final class SerializationError extends Error {
  SerializationError(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'SerializationError: $message'
      : 'SerializationError: $message (cause: $cause)';
}
