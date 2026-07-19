import 'dart:convert';

import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/bridge/event_batcher.dart';
import 'package:all_observer_devtools/src/configuration/devtools_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Not a real protocol event — stands in for "a subtype the codec does not
/// recognize yet" so the transport-drop path can be exercised without
/// waiting for the core to actually add one.
final class _UnknownProtocolEvent extends ObserverProtocolEvent {
  const _UnknownProtocolEvent({
    required super.sequenceNumber,
    required super.sessionId,
  }) : super(
         protocolVersion: observerProtocolVersion,
         eventId: 'unknown-$sequenceNumber',
         timestampMicros: 0,
       );
}

NodeCreatedEvent _createdEvent({
  required String sessionId,
  required int sequenceNumber,
  int id = 1,
  String? label,
  StackTrace? stackTrace,
}) => NodeCreatedEvent(
  protocolVersion: observerProtocolVersion,
  sessionId: sessionId,
  eventId: 'event-$sequenceNumber',
  sequenceNumber: sequenceNumber,
  timestampMicros: sequenceNumber * 1000,
  objectId: ObserverNodeId(id),
  kind: ObserverNodeKind.observable,
  debugLabel: label ?? 'node$id',
  debugType: 'int',
  stackTrace: stackTrace,
);

void main() {
  test('add() is a no-op while streaming is disabled (the default)', () {
    int batchCount = 0;
    final EventBatcher batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(),
      onBatch: (_) => batchCount++,
    );
    addTearDown(batcher.dispose);

    batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: 1));

    expect(batcher.pendingCount, 0);
    expect(batchCount, 0);
  });

  test(
    'flushes immediately once maxBatchSize is reached, preserving order',
    () {
      final List<Map<String, Object?>> batches = <Map<String, Object?>>[];
      final EventBatcher batcher = EventBatcher(
        config: const AllObserverDevToolsConfig(
          maxBatchSize: 3,
          batchInterval: Duration(seconds: 30),
        ),
        onBatch: batches.add,
      );
      addTearDown(batcher.dispose);
      batcher.setStreamingEnabled(true);

      for (int i = 1; i <= 3; i++) {
        batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: i));
      }

      expect(batches, hasLength(1));
      final List<Object?> events = batches.single['events'] as List<Object?>;
      expect(events, hasLength(3));
      expect(
        events
            .cast<Map<String, Object?>>()
            .map((e) => e['sequenceNumber'])
            .toList(),
        <int>[1, 2, 3],
      );
    },
  );

  test('flushes on the batch interval timer when below maxBatchSize', () async {
    final List<Map<String, Object?>> batches = <Map<String, Object?>>[];
    final EventBatcher batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(
        maxBatchSize: 100,
        batchInterval: Duration(milliseconds: 10),
      ),
      onBatch: batches.add,
    );
    addTearDown(batcher.dispose);
    batcher.setStreamingEnabled(true);

    batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: 1));
    expect(batcher.pendingCount, 1);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(batches, hasLength(1));
    expect(batcher.pendingCount, 0);
  });

  test('never mixes two sessions in one batch', () {
    final List<Map<String, Object?>> batches = <Map<String, Object?>>[];
    final EventBatcher batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(
        maxBatchSize: 100,
        batchInterval: Duration(seconds: 30),
      ),
      onBatch: batches.add,
    );
    addTearDown(batcher.dispose);
    batcher.setStreamingEnabled(true);

    batcher.add(_createdEvent(sessionId: 'session-A', sequenceNumber: 1));
    batcher.add(_createdEvent(sessionId: 'session-A', sequenceNumber: 2));
    batcher.add(_createdEvent(sessionId: 'session-B', sequenceNumber: 1));
    batcher.flush();

    expect(batches, hasLength(2));
    expect(batches[0]['sessionId'], 'session-A');
    expect((batches[0]['events'] as List<Object?>), hasLength(2));
    expect(batches[1]['sessionId'], 'session-B');
    expect((batches[1]['events'] as List<Object?>), hasLength(1));
  });

  test('splits a batch that would exceed maxPayloadBytes', () {
    final List<Map<String, Object?>> batches = <Map<String, Object?>>[];
    final EventBatcher batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(
        maxBatchSize: 1000,
        batchInterval: Duration(seconds: 30),
        // Small enough that a single encoded event roughly fills it, so 5
        // events must become multiple chunks.
        maxPayloadBytes: 400,
      ),
      onBatch: batches.add,
    );
    addTearDown(batcher.dispose);
    batcher.setStreamingEnabled(true);

    for (int i = 1; i <= 5; i++) {
      batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: i));
    }
    batcher.flush();

    expect(batches.length, greaterThan(1));
    final List<int> allSequences = batches
        .expand(
          (b) => (b['events'] as List<Object?>).cast<Map<String, Object?>>(),
        )
        .map((e) => e['sequenceNumber'] as int)
        .toList();
    expect(allSequences, <int>[1, 2, 3, 4, 5]);
  });

  test('measures the complete JSON envelope in UTF-8 bytes', () {
    final List<Map<String, Object?>> probe = <Map<String, Object?>>[];
    final event = _createdEvent(
      sessionId: 'sessão-🚀',
      sequenceNumber: 1,
      label: 'ação com acentos e emoji 😀' * 8,
    );
    final probeBatcher = EventBatcher(
      config: const AllObserverDevToolsConfig(maxPayloadBytes: 1 << 20),
      onBatch: probe.add,
    )..setStreamingEnabled(true);
    probeBatcher.add(event);
    probeBatcher.flush();
    final int exactBytes = utf8.encode(jsonEncode(probe.single)).length;
    probeBatcher.dispose();

    final List<Map<String, Object?>> exact = <Map<String, Object?>>[];
    final exactBatcher = EventBatcher(
      config: AllObserverDevToolsConfig(maxPayloadBytes: exactBytes),
      onBatch: exact.add,
    )..setStreamingEnabled(true);
    addTearDown(exactBatcher.dispose);
    exactBatcher.add(event);
    exactBatcher.flush();

    expect(exact, hasLength(1));
    expect(utf8.encode(jsonEncode(exact.single)).length, exactBytes);
    expect(exactBatcher.transportOversizedEventCount, 0);
  });

  test('accounts for ASCII, accents, emoji, long labels and stack traces', () {
    final events = <NodeCreatedEvent>[
      _createdEvent(sessionId: 's1', sequenceNumber: 1, label: 'ascii'),
      _createdEvent(sessionId: 'sessão', sequenceNumber: 2, label: 'ação'),
      _createdEvent(sessionId: 's1', sequenceNumber: 3, label: 'evento 🚀'),
      _createdEvent(
        sessionId: 's1',
        sequenceNumber: 4,
        label: 'long-label-' * 200,
      ),
      _createdEvent(
        sessionId: 's1',
        sequenceNumber: 5,
        stackTrace: StackTrace.fromString('frame.dart:1\n' * 100),
      ),
    ];

    for (final event in events) {
      final probe = <Map<String, Object?>>[];
      final probeBatcher = EventBatcher(
        config: const AllObserverDevToolsConfig(maxPayloadBytes: 1 << 20),
        onBatch: probe.add,
      )..setStreamingEnabled(true);
      probeBatcher.add(event);
      probeBatcher.flush();
      final exactBytes = utf8.encode(jsonEncode(probe.single)).length;
      probeBatcher.dispose();

      final emitted = <Map<String, Object?>>[];
      final exactBatcher = EventBatcher(
        config: AllObserverDevToolsConfig(maxPayloadBytes: exactBytes),
        onBatch: emitted.add,
      )..setStreamingEnabled(true);
      exactBatcher.add(event);
      exactBatcher.flush();

      expect(emitted, hasLength(1), reason: 'payload for ${event.debugLabel}');
      expect(utf8.encode(jsonEncode(emitted.single)).length, exactBytes);
      exactBatcher.dispose();
    }
  });

  test('drops and counts a single event one UTF-8 byte above the limit', () {
    final List<Map<String, Object?>> probe = <Map<String, Object?>>[];
    final event = _createdEvent(
      sessionId: 's1',
      sequenceNumber: 1,
      label: 'emoji 🚀' * 20,
    );
    final probeBatcher = EventBatcher(
      config: const AllObserverDevToolsConfig(maxPayloadBytes: 1 << 20),
      onBatch: probe.add,
    )..setStreamingEnabled(true);
    probeBatcher.add(event);
    probeBatcher.flush();
    final int encodedBytes = utf8.encode(jsonEncode(probe.single)).length;
    probeBatcher.dispose();

    final List<Map<String, Object?>> emitted = <Map<String, Object?>>[];
    final batcher = EventBatcher(
      config: AllObserverDevToolsConfig(maxPayloadBytes: encodedBytes - 1),
      onBatch: emitted.add,
    )..setStreamingEnabled(true);
    addTearDown(batcher.dispose);
    batcher.add(event);
    batcher.flush();

    expect(emitted, isEmpty);
    expect(batcher.transportOversizedEventCount, 1);
    expect(batcher.transportDroppedEventCount, 1);
  });

  test('disabling streaming flushes what was queued, then goes idle', () {
    final List<Map<String, Object?>> batches = <Map<String, Object?>>[];
    final EventBatcher batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(
        maxBatchSize: 100,
        batchInterval: Duration(seconds: 30),
      ),
      onBatch: batches.add,
    );
    addTearDown(batcher.dispose);
    batcher.setStreamingEnabled(true);
    batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: 1));

    batcher.setStreamingEnabled(false);

    expect(batches, hasLength(1));
    expect(batcher.streamingEnabled, isFalse);

    batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: 2));
    expect(batcher.pendingCount, 0);
    expect(batches, hasLength(1));
  });

  test('clearPending discards without emitting', () {
    int batchCount = 0;
    final EventBatcher batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(
        maxBatchSize: 100,
        batchInterval: Duration(seconds: 30),
      ),
      onBatch: (_) => batchCount++,
    );
    addTearDown(batcher.dispose);
    batcher.setStreamingEnabled(true);
    batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: 1));

    batcher.clearPending();

    expect(batcher.pendingCount, 0);
    expect(batchCount, 0);
    expect(batcher.transportClearedEventCount, 1);
  });

  test(
    'dispose cancels the pending timer so no late batch is emitted',
    () async {
      int batchCount = 0;
      final EventBatcher batcher = EventBatcher(
        config: const AllObserverDevToolsConfig(
          maxBatchSize: 100,
          batchInterval: Duration(milliseconds: 10),
        ),
        onBatch: (_) => batchCount++,
      );
      batcher.setStreamingEnabled(true);
      batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: 1));

      batcher.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(batchCount, 0);
    },
  );

  test('an unencodable event is dropped visibly, not silently', () {
    final List<Map<String, Object?>> batches = <Map<String, Object?>>[];
    final EventBatcher batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(
        maxBatchSize: 100,
        batchInterval: Duration(seconds: 30),
      ),
      onBatch: batches.add,
    );
    addTearDown(batcher.dispose);
    batcher.setStreamingEnabled(true);

    expect(batcher.transportDroppedEventCount, 0);

    batcher.add(
      const _UnknownProtocolEvent(sequenceNumber: 1, sessionId: 's1'),
    );
    batcher.add(_createdEvent(sessionId: 's1', sequenceNumber: 2));
    batcher.flush();

    expect(batcher.transportDroppedEventCount, 1);
    // The recognized event still gets through — one bad event does not sink
    // the rest of the batch.
    expect(batches, hasLength(1));
    expect((batches.single['events'] as List<Object?>), hasLength(1));
  });
}
