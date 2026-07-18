import 'value_summary_model.dart';

/// Thrown when a JSON payload does not match the protocol v1 wire contract
/// this extension understands (unknown `eventType`, or a required field
/// missing/mistyped). Callers must treat this as "do not interpret this
/// data", never as a heuristic to patch over — see the implementation
/// spec's ban on silent/guessed interpretation of protocol data.
final class ProtocolDecodeError extends Error {
  ProtocolDecodeError(this.message);

  final String message;

  @override
  String toString() => 'ProtocolDecodeError: $message';
}

/// Versioned envelope shared by every decoded protocol event, mirroring
/// `ObserverProtocolEvent` on the core and the `encodeEvent` wire contract
/// in the runtime bridge. `sequenceNumber` — not `timestampMicros` — is the
/// ordering source of truth; every consumer of this model must sort/apply
/// by it.
sealed class ProtocolEventModel {
  const ProtocolEventModel({
    required this.protocolVersion,
    required this.sessionId,
    required this.eventId,
    required this.sequenceNumber,
    required this.timestampMicros,
    this.stackTrace,
  });

  final int protocolVersion;
  final String sessionId;
  final String eventId;
  final int sequenceNumber;
  final int timestampMicros;
  final String? stackTrace;

  /// Node/tracker/scope identity this event is primarily about, when it has
  /// one — used to link a timeline row to a node/scope detail view. `null`
  /// for events with no single subject (there are none today, but a future
  /// event type might not have one).
  int? get primarySubjectId;

  static ProtocolEventModel fromJson(Map<String, Object?> json) {
    final Object? eventType = json['eventType'];
    if (eventType is! String) {
      throw ProtocolDecodeError(
        'Event JSON is missing a string "eventType" field: $json',
      );
    }
    return switch (eventType) {
      'nodeCreated' => NodeCreatedEventModel._fromJson(json),
      'nodeUpdated' => NodeUpdatedEventModel._fromJson(json),
      'nodeDisposed' => NodeDisposedEventModel._fromJson(json),
      'trackerRunStarted' => TrackerRunStartedEventModel._fromJson(json),
      'trackerRunFinished' => TrackerRunFinishedEventModel._fromJson(json),
      'dependenciesChanged' => DependenciesChangedEventModel._fromJson(json),
      'scopeCreated' => ScopeCreatedEventModel._fromJson(json),
      'scopeResourceRegistered' => ScopeResourceRegisteredEventModel._fromJson(
        json,
      ),
      'scopeDisposed' => ScopeDisposedEventModel._fromJson(json),
      'warningRaised' => WarningRaisedEventModel._fromJson(json),
      _ => throw ProtocolDecodeError('Unknown eventType "$eventType"'),
    };
  }
}

int _requireInt(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is int) {
    return value;
  }
  throw ProtocolDecodeError('Expected int field "$key", got: $value');
}

String _requireString(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is String) {
    return value;
  }
  throw ProtocolDecodeError('Expected string field "$key", got: $value');
}

List<int> _requireIntList(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value is List) {
    return value.cast<int>();
  }
  throw ProtocolDecodeError('Expected int list field "$key", got: $value');
}

ValueSummaryModel? _optionalValueSummary(Map<String, Object?> json, String key) {
  final Object? value = json[key];
  if (value == null) {
    return null;
  }
  if (value is Map<String, Object?>) {
    return ValueSummaryModel.fromJson(value);
  }
  throw ProtocolDecodeError('Expected value summary object at "$key", got: $value');
}

({
  int protocolVersion,
  String sessionId,
  String eventId,
  int sequenceNumber,
  int timestampMicros,
  String? stackTrace,
})
_envelope(Map<String, Object?> json) => (
  protocolVersion: _requireInt(json, 'protocolVersion'),
  sessionId: _requireString(json, 'sessionId'),
  eventId: _requireString(json, 'eventId'),
  sequenceNumber: _requireInt(json, 'sequenceNumber'),
  timestampMicros: _requireInt(json, 'timestampMicros'),
  stackTrace: json['stackTrace'] as String?,
);

final class NodeCreatedEventModel extends ProtocolEventModel {
  const NodeCreatedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.objectId,
    required this.kind,
    required this.debugLabel,
    required this.debugType,
    this.initialValueSummary,
    super.stackTrace,
  });

  factory NodeCreatedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return NodeCreatedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      objectId: _requireInt(json, 'objectId'),
      kind: _requireString(json, 'kind'),
      debugLabel: _requireString(json, 'debugLabel'),
      debugType: _requireString(json, 'debugType'),
      initialValueSummary: _optionalValueSummary(json, 'initialValueSummary'),
    );
  }

  final int objectId;
  final String kind;
  final String debugLabel;
  final String debugType;
  final ValueSummaryModel? initialValueSummary;

  @override
  int? get primarySubjectId => objectId;
}

final class NodeUpdatedEventModel extends ProtocolEventModel {
  const NodeUpdatedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.objectId,
    required this.kind,
    this.oldValueSummary,
    this.newValueSummary,
    super.stackTrace,
  });

  factory NodeUpdatedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return NodeUpdatedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      objectId: _requireInt(json, 'objectId'),
      kind: _requireString(json, 'kind'),
      oldValueSummary: _optionalValueSummary(json, 'oldValueSummary'),
      newValueSummary: _optionalValueSummary(json, 'newValueSummary'),
    );
  }

  final int objectId;
  final String kind;
  final ValueSummaryModel? oldValueSummary;
  final ValueSummaryModel? newValueSummary;

  @override
  int? get primarySubjectId => objectId;
}

final class NodeDisposedEventModel extends ProtocolEventModel {
  const NodeDisposedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.objectId,
    required this.kind,
    required this.listenerCount,
    this.disposeReason,
    super.stackTrace,
  });

  factory NodeDisposedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return NodeDisposedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      objectId: _requireInt(json, 'objectId'),
      kind: _requireString(json, 'kind'),
      listenerCount: _requireInt(json, 'listenerCount'),
      disposeReason: json['disposeReason'] as String?,
    );
  }

  final int objectId;
  final String kind;
  final int listenerCount;
  final String? disposeReason;

  @override
  int? get primarySubjectId => objectId;
}

final class TrackerRunStartedEventModel extends ProtocolEventModel {
  const TrackerRunStartedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.trackerId,
    required this.runId,
    required this.kind,
    super.stackTrace,
  });

  factory TrackerRunStartedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return TrackerRunStartedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      trackerId: _requireInt(json, 'trackerId'),
      runId: _requireString(json, 'runId'),
      kind: _requireString(json, 'kind'),
    );
  }

  final int trackerId;
  final String runId;
  final String kind;

  @override
  int? get primarySubjectId => trackerId;
}

final class TrackerRunFinishedEventModel extends ProtocolEventModel {
  const TrackerRunFinishedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.trackerId,
    required this.runId,
    required this.kind,
    required this.durationMicros,
    required this.dependencyIds,
    required this.completedWithError,
    super.stackTrace,
  });

  factory TrackerRunFinishedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return TrackerRunFinishedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      trackerId: _requireInt(json, 'trackerId'),
      runId: _requireString(json, 'runId'),
      kind: _requireString(json, 'kind'),
      durationMicros: _requireInt(json, 'durationMicros'),
      dependencyIds: _requireIntList(json, 'dependencyIds'),
      completedWithError: json['completedWithError'] as bool? ?? false,
    );
  }

  final int trackerId;
  final String runId;
  final String kind;
  final int durationMicros;
  final List<int> dependencyIds;
  final bool completedWithError;

  @override
  int? get primarySubjectId => trackerId;
}

final class DependenciesChangedEventModel extends ProtocolEventModel {
  const DependenciesChangedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.trackerId,
    required this.runId,
    required this.currentDependencyIds,
    required this.addedDependencyIds,
    required this.removedDependencyIds,
    super.stackTrace,
  });

  factory DependenciesChangedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return DependenciesChangedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      trackerId: _requireInt(json, 'trackerId'),
      runId: _requireString(json, 'runId'),
      currentDependencyIds: _requireIntList(json, 'currentDependencyIds'),
      addedDependencyIds: _requireIntList(json, 'addedDependencyIds'),
      removedDependencyIds: _requireIntList(json, 'removedDependencyIds'),
    );
  }

  final int trackerId;
  final String runId;
  final List<int> currentDependencyIds;
  final List<int> addedDependencyIds;
  final List<int> removedDependencyIds;

  @override
  int? get primarySubjectId => trackerId;
}

final class ScopeCreatedEventModel extends ProtocolEventModel {
  const ScopeCreatedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.scopeId,
    required this.debugLabel,
    super.stackTrace,
  });

  factory ScopeCreatedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return ScopeCreatedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      scopeId: _requireInt(json, 'scopeId'),
      debugLabel: _requireString(json, 'debugLabel'),
    );
  }

  final int scopeId;
  final String debugLabel;

  @override
  int? get primarySubjectId => scopeId;
}

final class ScopeResourceRegisteredEventModel extends ProtocolEventModel {
  const ScopeResourceRegisteredEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.scopeId,
    required this.resourceId,
    required this.resourceKind,
    super.stackTrace,
  });

  factory ScopeResourceRegisteredEventModel._fromJson(
    Map<String, Object?> json,
  ) {
    final e = _envelope(json);
    return ScopeResourceRegisteredEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      scopeId: _requireInt(json, 'scopeId'),
      resourceId: _requireInt(json, 'resourceId'),
      resourceKind: _requireString(json, 'resourceKind'),
    );
  }

  final int scopeId;
  final int resourceId;
  final String resourceKind;

  @override
  int? get primarySubjectId => scopeId;
}

final class ScopeDisposedEventModel extends ProtocolEventModel {
  const ScopeDisposedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.scopeId,
    required this.registeredResourceCount,
    required this.disposedResourceCount,
    required this.failedDisposeCount,
    super.stackTrace,
  });

  factory ScopeDisposedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return ScopeDisposedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      scopeId: _requireInt(json, 'scopeId'),
      registeredResourceCount: _requireInt(json, 'registeredResourceCount'),
      disposedResourceCount: _requireInt(json, 'disposedResourceCount'),
      failedDisposeCount: _requireInt(json, 'failedDisposeCount'),
    );
  }

  final int scopeId;
  final int registeredResourceCount;
  final int disposedResourceCount;
  final int failedDisposeCount;

  @override
  int? get primarySubjectId => scopeId;
}

final class WarningRaisedEventModel extends ProtocolEventModel {
  const WarningRaisedEventModel({
    required super.protocolVersion,
    required super.sessionId,
    required super.eventId,
    required super.sequenceNumber,
    required super.timestampMicros,
    required this.warningCode,
    required this.message,
    required this.severity,
    this.suggestion,
    this.objectId,
    super.stackTrace,
  });

  factory WarningRaisedEventModel._fromJson(Map<String, Object?> json) {
    final e = _envelope(json);
    return WarningRaisedEventModel(
      protocolVersion: e.protocolVersion,
      sessionId: e.sessionId,
      eventId: e.eventId,
      sequenceNumber: e.sequenceNumber,
      timestampMicros: e.timestampMicros,
      stackTrace: e.stackTrace,
      warningCode: _requireString(json, 'warningCode'),
      message: _requireString(json, 'message'),
      severity: _requireString(json, 'severity'),
      suggestion: json['suggestion'] as String?,
      objectId: json['objectId'] as int?,
    );
  }

  final String warningCode;
  final String message;
  final String severity;
  final String? suggestion;
  final int? objectId;

  @override
  int? get primarySubjectId => objectId;
}
