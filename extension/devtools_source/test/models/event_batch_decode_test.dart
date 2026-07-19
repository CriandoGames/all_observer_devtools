import 'package:all_observer_devtools_extension/src/models/event_batch_model.dart';
import 'package:all_observer_devtools_extension/src/models/protocol_event_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> event({
  String session = 's1',
  int sequence = 1,
  String type = 'nodeCreated',
}) => <String, Object?>{
  'protocolVersion': 1,
  'sessionId': session,
  'eventId': 'e$sequence',
  'sequenceNumber': sequence,
  'timestampMicros': 0,
  'eventType': type,
  'objectId': sequence,
  'kind': 'observable',
  'debugLabel': 'safe',
  'debugType': 'int',
  'initialValueSummary': null,
};

Map<String, Object?> batch({
  Object? version = 1,
  Object? session = 's1',
  Object? first = 1,
  Object? last = 1,
  Object? events,
}) => <String, Object?>{
  'protocolVersion': version,
  'sessionId': session,
  'firstSequenceNumber': first,
  'lastSequenceNumber': last,
  'events': events ?? <Object?>[event()],
};

void main() {
  test('rejects incompatible version, missing session and invalid fields', () {
    for (final json in <Map<String, Object?>>[
      batch(version: 2),
      batch(session: null),
      batch(first: 'one'),
      batch(events: 'not-a-list'),
    ]) {
      expect(
        () => EventBatchModel.fromJson(json),
        throwsA(isA<ProtocolDecodeError>()),
      );
    }
  });

  test('rejects unknown event type, mixed session and invalid sequence', () {
    expect(
      () => EventBatchModel.fromJson(
        batch(events: <Object?>[event(type: 'futureType')]),
      ),
      throwsA(isA<ProtocolDecodeError>()),
    );
    expect(
      () => EventBatchModel.fromJson(
        batch(events: <Object?>[event(session: 'other')]),
      ),
      throwsA(isA<ProtocolDecodeError>()),
    );
    expect(
      () => EventBatchModel.fromJson(
        batch(
          first: 2,
          events: <Object?>[event(sequence: 2), event(sequence: 1)],
        ),
      ),
      throwsA(isA<ProtocolDecodeError>()),
    );
    expect(
      () => EventBatchModel.fromJson(
        batch(first: 0, last: 0, events: <Object?>[event(sequence: 0)]),
      ),
      throwsA(isA<ProtocolDecodeError>()),
    );
    expect(
      () => EventBatchModel.fromJson(
        batch(first: null, last: null, events: <Object?>[]),
      ),
      throwsA(isA<ProtocolDecodeError>()),
    );
  });

  test('sanitized errors do not echo raw payload values', () {
    const secret = 'super-secret-user-value';
    for (final json in <Map<String, Object?>>[
      batch(session: null, events: secret),
      batch(
        events: <Object?>[
          <String, Object?>{'eventType': null, 'debugLabel': secret},
        ],
      ),
      batch(events: <Object?>[event(type: secret)]),
    ]) {
      try {
        EventBatchModel.fromJson(json);
        fail('decode should fail');
      } on ProtocolDecodeError catch (error) {
        expect(error.toString(), isNot(contains(secret)));
      }
    }
  });
}
