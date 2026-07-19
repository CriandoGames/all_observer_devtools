import 'dart:async';
import 'dart:convert';

import 'package:all_observer/all_observer.dart';

import '../configuration/devtools_config.dart';
import '../serialization/protocol_codec.dart';
import '../serialization/serialization_error.dart';

/// Batches [ObserverProtocolEvent]s for transport, flushing on whichever of
/// three triggers happens first: [AllObserverDevToolsConfig.batchInterval]
/// elapses, [AllObserverDevToolsConfig.maxBatchSize] is reached, or the
/// approximate encoded payload would exceed
/// [AllObserverDevToolsConfig.maxPayloadBytes].
///
/// Ordering is always preserved: events are appended to a single pending
/// list and flushed in the order they arrived. A batch never mixes two
/// sessions — if an event's `sessionId` differs from the pending batch's,
/// the pending batch is flushed first under its own session before the new
/// event starts a fresh one.
///
/// When [streamingEnabled] is `false` (the default — no DevTools listener
/// implied), [add] is a single boolean check and returns immediately: no
/// list growth, no encoding, no timer. This is the "custo mínimo sem
/// DevTools conectado" requirement from the implementation spec.
final class EventBatcher {
  EventBatcher({
    required AllObserverDevToolsConfig config,
    required void Function(Map<String, Object?> batch) onBatch,
  }) : _config = config,
       _onBatch = onBatch;

  final AllObserverDevToolsConfig _config;
  final void Function(Map<String, Object?> batch) _onBatch;

  final List<ObserverProtocolEvent> _pending = <ObserverProtocolEvent>[];
  Timer? _timer;

  /// Total events dropped by *this bridge's transport*, distinct from
  /// `ObserverProtocol.droppedEventCount` (the core's own ring-buffer
  /// evictions). Only ever incremented when [encodeEvent]/[encodeEventBatch]
  /// throws `SerializationError` — i.e. an event subtype this codec does not
  /// recognize yet. Surfaced by `ext.all_observer.getStatus` so a loss here
  /// is never silent (implementation spec principle 17: "Toda perda de
  /// eventos deve ficar visível").
  int get transportDroppedEventCount => _transportDroppedEventCount;
  int _transportDroppedEventCount = 0;
  int get transportOversizedEventCount => _transportOversizedEventCount;
  int _transportOversizedEventCount = 0;
  int get transportClearedEventCount => _transportClearedEventCount;
  int _transportClearedEventCount = 0;
  bool _streamingEnabled = false;
  bool _disposed = false;

  bool get streamingEnabled => _streamingEnabled;
  bool get isDisposed => _disposed;

  /// Number of events currently buffered and not yet flushed.
  int get pendingCount => _pending.length;

  void setStreamingEnabled(bool enabled) {
    if (_disposed || _streamingEnabled == enabled) {
      return;
    }
    _streamingEnabled = enabled;
    if (!enabled) {
      // Turning streaming off flushes whatever was already queued (so no
      // event is silently swallowed) and cancels the timer; it does not
      // clear buffered state that belongs to the core.
      flush();
    }
  }

  void add(ObserverProtocolEvent event) {
    if (_disposed || !_streamingEnabled) {
      return;
    }
    if (_pending.isNotEmpty && _pending.first.sessionId != event.sessionId) {
      // Never let a single batch span two sessions.
      flush();
    }
    _pending.add(event);
    if (_pending.length >= _config.maxBatchSize) {
      flush();
      return;
    }
    _timer ??= Timer(_config.batchInterval, flush);
  }

  /// Flushes whatever is pending immediately, ignoring the batch timer.
  /// Safe to call with nothing pending (no-op).
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) {
      return;
    }
    final String sessionId = _pending.first.sessionId;
    final List<ObserverProtocolEvent> events = List<ObserverProtocolEvent>.of(
      _pending,
    );
    _pending.clear();
    _emitInChunks(sessionId, events);
  }

  void _emitInChunks(String sessionId, List<ObserverProtocolEvent> events) {
    final List<ObserverProtocolEvent> chunk = <ObserverProtocolEvent>[];
    int droppedBySerialization = 0;

    void flushChunk() {
      if (chunk.isEmpty) {
        return;
      }
      try {
        _onBatch(
          encodeEventBatch(
            sessionId: sessionId,
            events: List<ObserverProtocolEvent>.of(chunk),
          ),
        );
      } on SerializationError {
        droppedBySerialization += chunk.length;
      }
      chunk.clear();
    }

    for (final ObserverProtocolEvent event in events) {
      Map<String, Object?> candidate;
      try {
        candidate = encodeEventBatch(
          sessionId: sessionId,
          events: <ObserverProtocolEvent>[...chunk, event],
        );
      } on SerializationError {
        droppedBySerialization++;
        continue;
      }
      if (_jsonUtf8Bytes(candidate) > _config.maxPayloadBytes &&
          chunk.isNotEmpty) {
        flushChunk();
        try {
          candidate = encodeEventBatch(
            sessionId: sessionId,
            events: <ObserverProtocolEvent>[event],
          );
        } on SerializationError {
          droppedBySerialization++;
          continue;
        }
      }
      if (_jsonUtf8Bytes(candidate) > _config.maxPayloadBytes) {
        _transportOversizedEventCount++;
        droppedBySerialization++;
        continue;
      }
      chunk.add(event);
    }
    flushChunk();

    if (droppedBySerialization > 0) {
      _transportDroppedEventCount += droppedBySerialization;
    }
  }

  int _jsonUtf8Bytes(Map<String, Object?> value) =>
      utf8.encode(jsonEncode(value)).length;

  /// Discards whatever is pending without emitting it. Distinct from
  /// [flush]: this is the DevTools-local "clear buffer" action (section 10,
  /// `ext.all_observer.clearBuffer`), which must not be confused with
  /// clearing the core's own ring buffer — that buffer is owned by
  /// `ObserverProtocol` and this package never mutates it.
  void clearPending() {
    _timer?.cancel();
    _timer = null;
    _transportClearedEventCount += _pending.length;
    _pending.clear();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _transportClearedEventCount += _pending.length;
    _pending.clear();
    _disposed = true;
    _streamingEnabled = false;
  }
}
