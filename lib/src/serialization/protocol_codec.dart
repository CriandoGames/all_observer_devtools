import 'package:all_observer/all_observer.dart';

import 'event_codec.dart';
import 'serialization_error.dart';

export 'event_codec.dart' show encodeEvent, EventTypeName;
export 'snapshot_codec.dart' show encodeSnapshot;

/// Capability identifiers a client can use to know which optional pieces of
/// the protocol this bridge actually exposes, without guessing from
/// behavior. Every capability listed here is fully implemented — do not add
/// one speculatively.
abstract final class DevToolsCapability {
  static const String snapshot = 'snapshot';
  static const String eventStream = 'event_stream';
  static const String dependencies = 'dependencies';
  static const String scopes = 'scopes';
  static const String warnings = 'warnings';
}

const List<String> _supportedCapabilities = <String>[
  DevToolsCapability.snapshot,
  DevToolsCapability.eventStream,
  DevToolsCapability.dependencies,
  DevToolsCapability.scopes,
  DevToolsCapability.warnings,
];

/// Encodes a batch of buffered/live events for transport, matching the
/// contract in section 13 of the implementation spec. `events` must already
/// be in ascending `sequenceNumber` order — this function does not sort,
/// it only encodes and reports the observed range so a client can verify
/// ordering was preserved end-to-end.
///
/// Throws [SerializationError] if `events` is empty (a batch is only ever
/// built from at least one event; callers must not flush empty batches).
Map<String, Object?> encodeEventBatch({
  required String sessionId,
  required List<ObserverProtocolEvent> events,
}) {
  if (events.isEmpty) {
    throw SerializationError('Cannot encode an empty event batch');
  }
  return <String, Object?>{
    'protocolVersion': observerProtocolVersion,
    'sessionId': sessionId,
    'firstSequenceNumber': events.first.sequenceNumber,
    'lastSequenceNumber': events.last.sequenceNumber,
    'events': events.map(encodeEvent).toList(),
  };
}

/// Empty polling response with the same schema as [encodeEventBatch].
Map<String, Object?> encodeEmptyEventBatch({
  required String sessionId,
  required int lastSequenceNumber,
}) => <String, Object?>{
  'protocolVersion': observerProtocolVersion,
  'sessionId': sessionId,
  'firstSequenceNumber': null,
  'lastSequenceNumber': lastSequenceNumber,
  'events': const <Object?>[],
};

/// Encodes the response for `ext.all_observer.getProtocolInfo`: the version
/// negotiation surface described in section 15. A client compares
/// `protocolVersion` against its own supported range before interpreting
/// any other data from this bridge.
Map<String, Object?> encodeProtocolInfo({required String packageVersion}) =>
    <String, Object?>{
      'protocolVersion': observerProtocolVersion,
      'packageVersion': packageVersion,
      'minimumSupportedProtocolVersion': observerProtocolVersion,
      'maximumSupportedProtocolVersion': observerProtocolVersion,
      'capabilities': _supportedCapabilities,
    };

/// Encodes the response for `ext.all_observer.getStatus`: lightweight
/// bridge state that does not require walking the full node registry.
///
/// `coreBufferedEventCount` is the size of `ObserverProtocol`'s own ring
/// buffer (owned by the core, survives regardless of streaming).
/// `pendingBatchCount` is how many events are queued in this bridge's live
/// batcher, waiting for the next flush — always `0` while streaming is
/// disabled. `droppedEventCount` is the core's own ring-buffer eviction
/// count (`ObserverProtocol.droppedEventCount`); `transportDroppedEventCount`
/// is separate — events this bridge itself failed to encode for live
/// transport (see `EventBatcher.transportDroppedEventCount`). Both are
/// reported so no loss, at either layer, is silent.
Map<String, Object?> encodeStatus({
  required String sessionId,
  required bool streamingEnabled,
  required int coreBufferedEventCount,
  required int pendingBatchCount,
  required int droppedEventCount,
  required int transportDroppedEventCount,
  required int transportOversizedEventCount,
  required int lastSequenceNumber,
}) => <String, Object?>{
  'sessionId': sessionId,
  'streamingEnabled': streamingEnabled,
  'coreBufferedEventCount': coreBufferedEventCount,
  'pendingBatchCount': pendingBatchCount,
  'droppedEventCount': droppedEventCount,
  'transportDroppedEventCount': transportDroppedEventCount,
  'transportOversizedEventCount': transportOversizedEventCount,
  'lastSequenceNumber': lastSequenceNumber,
};
