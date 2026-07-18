import 'package:all_observer/all_observer.dart';

import 'serialization_error.dart';

/// Discriminator strings for the `eventType` field. Stable and documented —
/// this *is* the wire contract, not an implementation detail. New event
/// types must add a new value here rather than repurpose an existing one.
abstract final class EventTypeName {
  static const String nodeCreated = 'nodeCreated';
  static const String nodeUpdated = 'nodeUpdated';
  static const String nodeDisposed = 'nodeDisposed';
  static const String trackerRunStarted = 'trackerRunStarted';
  static const String trackerRunFinished = 'trackerRunFinished';
  static const String dependenciesChanged = 'dependenciesChanged';
  static const String scopeCreated = 'scopeCreated';
  static const String scopeResourceRegistered = 'scopeResourceRegistered';
  static const String scopeDisposed = 'scopeDisposed';
  static const String warningRaised = 'warningRaised';
}

/// Stack traces are only ever captured when the developer opts in
/// (`captureStackTraces: true`), which already implies they accept the
/// overhead. Even so, cap the serialized length so one pathological trace
/// cannot blow out a batch's payload budget.
const int _maxSerializedStackTraceLength = 4000;

/// Encodes any [ObserverProtocolEvent] into the deterministic JSON contract
/// described in the implementation spec (section 14). Every field name here
/// is part of the wire contract: do not rename without bumping
/// `devtoolsProtocolContractVersion`.
///
/// Throws [SerializationError] if [event] is a subtype this codec does not
/// recognize yet — callers must treat that as a dropped event, never let it
/// escape into the reactive system.
Map<String, Object?> encodeEvent(ObserverProtocolEvent event) {
  try {
    final Map<String, Object?> base = <String, Object?>{
      'protocolVersion': event.protocolVersion,
      'sessionId': event.sessionId,
      'eventId': event.eventId,
      'sequenceNumber': event.sequenceNumber,
      'timestampMicros': event.timestampMicros,
      if (event.stackTrace != null)
        'stackTrace': _encodeStackTrace(event.stackTrace!),
    };

    return switch (event) {
      NodeCreatedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.nodeCreated,
        'objectId': _encodeNodeId(e.objectId),
        'kind': _encodeKind(e.kind),
        'debugLabel': e.debugLabel,
        'debugType': e.debugType,
        'initialValueSummary': _encodeValueSummary(e.initialValueSummary),
      },
      NodeUpdatedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.nodeUpdated,
        'objectId': _encodeNodeId(e.objectId),
        'kind': _encodeKind(e.kind),
        'oldValueSummary': _encodeValueSummary(e.oldValueSummary),
        'newValueSummary': _encodeValueSummary(e.newValueSummary),
      },
      NodeDisposedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.nodeDisposed,
        'objectId': _encodeNodeId(e.objectId),
        'kind': _encodeKind(e.kind),
        'listenerCount': e.listenerCount,
        'disposeReason': e.disposeReason,
      },
      TrackerRunStartedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.trackerRunStarted,
        'trackerId': _encodeNodeId(e.trackerId),
        'runId': e.runId,
        'kind': _encodeKind(e.kind),
      },
      TrackerRunFinishedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.trackerRunFinished,
        'trackerId': _encodeNodeId(e.trackerId),
        'runId': e.runId,
        'kind': _encodeKind(e.kind),
        'durationMicros': e.durationMicros,
        'dependencyIds': _encodeNodeIdSet(e.dependencyIds),
        'completedWithError': e.completedWithError,
      },
      DependenciesChangedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.dependenciesChanged,
        'trackerId': _encodeNodeId(e.trackerId),
        'runId': e.runId,
        'currentDependencyIds': _encodeNodeIdSet(e.currentDependencyIds),
        'addedDependencyIds': _encodeNodeIdSet(e.addedDependencyIds),
        'removedDependencyIds': _encodeNodeIdSet(e.removedDependencyIds),
      },
      ScopeCreatedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.scopeCreated,
        'scopeId': _encodeNodeId(e.scopeId),
        'debugLabel': e.debugLabel,
      },
      ScopeResourceRegisteredEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.scopeResourceRegistered,
        'scopeId': _encodeNodeId(e.scopeId),
        'resourceId': _encodeNodeId(e.resourceId),
        'resourceKind': _encodeKind(e.resourceKind),
      },
      ProtocolScopeDisposedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.scopeDisposed,
        'scopeId': _encodeNodeId(e.scopeId),
        'registeredResourceCount': e.registeredResourceCount,
        'disposedResourceCount': e.disposedResourceCount,
        'failedDisposeCount': e.failedDisposeCount,
      },
      WarningRaisedEvent e => <String, Object?>{
        ...base,
        'eventType': EventTypeName.warningRaised,
        'warningCode': e.warningCode,
        'message': e.message,
        'suggestion': e.suggestion,
        'objectId': e.objectId == null ? null : _encodeNodeId(e.objectId!),
        'severity': e.severity.name,
      },
      _ => throw SerializationError(
        'Unrecognized ObserverProtocolEvent subtype: ${event.runtimeType}',
      ),
    };
  } on SerializationError {
    rethrow;
  } catch (error) {
    throw SerializationError(
      'Failed to encode event ${event.runtimeType}',
      cause: error,
    );
  }
}

int _encodeNodeId(ObserverNodeId id) => id.value;

List<int> _encodeNodeIdSet(Set<ObserverNodeId> ids) {
  final List<int> values = ids.map(_encodeNodeId).toList()..sort();
  return values;
}

String _encodeKind(ObserverNodeKind kind) => kind.name;

Map<String, Object?>? _encodeValueSummary(ObserverValueSummary? summary) {
  if (summary == null) {
    return null;
  }
  return <String, Object?>{
    'type': summary.type,
    'display': summary.display,
    'isRedacted': summary.isRedacted,
    'isTruncated': summary.isTruncated,
  };
}

String _encodeStackTrace(StackTrace stackTrace) {
  final String text = stackTrace.toString();
  return text.length > _maxSerializedStackTraceLength
      ? text.substring(0, _maxSerializedStackTraceLength)
      : text;
}
