import 'protocol_event_model.dart';

/// A batch of events as posted on the `all_observer:events` extension
/// stream, or returned by `ext.all_observer.getEvents`. Mirrors
/// `encodeEventBatch`'s wire contract.
final class EventBatchModel {
  const EventBatchModel({
    required this.protocolVersion,
    required this.sessionId,
    required this.firstSequenceNumber,
    required this.lastSequenceNumber,
    required this.events,
  });

  factory EventBatchModel.fromJson(Map<String, Object?> json) {
    final Object? eventsJson = json['events'];
    if (eventsJson is! List) {
      throw ProtocolDecodeError('Malformed event batch: $json');
    }
    return EventBatchModel(
      protocolVersion: json['protocolVersion'] as int,
      sessionId: json['sessionId'] as String,
      firstSequenceNumber: json['firstSequenceNumber'] as int?,
      lastSequenceNumber: json['lastSequenceNumber'] as int?,
      events: eventsJson
          .cast<Map<String, Object?>>()
          .map(ProtocolEventModel.fromJson)
          .toList(),
    );
  }

  final int protocolVersion;
  final String sessionId;
  final int? firstSequenceNumber;
  final int? lastSequenceNumber;
  final List<ProtocolEventModel> events;
}
