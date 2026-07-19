import '../common/service_names.dart';
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
    final Object? version = json['protocolVersion'];
    final Object? session = json['sessionId'];
    final Object? first = json['firstSequenceNumber'];
    final Object? last = json['lastSequenceNumber'];
    final Object? eventsJson = json['events'];
    if (version is! int || version != extensionSupportedProtocolVersion) {
      throw ProtocolDecodeError('Unsupported event batch protocol version.');
    }
    if (session is! String || session.isEmpty) {
      throw ProtocolDecodeError('Event batch sessionId is missing or invalid.');
    }
    if ((first != null && first is! int) || (last != null && last is! int)) {
      throw ProtocolDecodeError('Event batch sequence range is invalid.');
    }
    if (eventsJson is! List) {
      throw ProtocolDecodeError(
        'Event batch events field is missing or invalid.',
      );
    }
    try {
      final events = eventsJson.map((value) {
        if (value is! Map) {
          throw ProtocolDecodeError('Event batch contains a non-object event.');
        }
        return ProtocolEventModel.fromJson(Map<String, Object?>.from(value));
      }).toList();
      if (events.any(
        (event) =>
            event.protocolVersion != version || event.sessionId != session,
      )) {
        throw ProtocolDecodeError(
          'Event batch mixes protocol versions or sessions.',
        );
      }
      for (int index = 1; index < events.length; index++) {
        if (events[index].sequenceNumber <= events[index - 1].sequenceNumber) {
          throw ProtocolDecodeError(
            'Event batch sequence is not strictly increasing.',
          );
        }
      }
      if (events.isEmpty) {
        if (first != null) {
          throw ProtocolDecodeError(
            'Empty event batch has a non-empty first sequence.',
          );
        }
      } else if (first != events.first.sequenceNumber ||
          last != events.last.sequenceNumber) {
        throw ProtocolDecodeError(
          'Event batch range does not match its events.',
        );
      }
      return EventBatchModel(
        protocolVersion: version,
        sessionId: session,
        firstSequenceNumber: first as int?,
        lastSequenceNumber: last as int?,
        events: events,
      );
    } on ProtocolDecodeError {
      rethrow;
    } catch (error) {
      throw ProtocolDecodeError(
        'Event batch contains malformed fields (${error.runtimeType}).',
      );
    }
  }

  final int protocolVersion;
  final String sessionId;
  final int? firstSequenceNumber;
  final int? lastSequenceNumber;
  final List<ProtocolEventModel> events;
}
