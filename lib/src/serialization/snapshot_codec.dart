import 'package:all_observer/all_observer.dart';

import 'serialization_error.dart';

/// Encodes an `ObserverProtocolSnapshot` into the deterministic JSON
/// contract described in the implementation spec (section 14). This is the
/// authoritative base state a client reconciles incremental events on top
/// of — see `firstAvailableSequence`/`lastAvailableSequence`/
/// `droppedEventCount` for gap detection.
///
/// Throws [SerializationError] if any contained node/dependency/scope entry
/// fails to encode; never partially succeeds silently.
Map<String, Object?> encodeSnapshot(ObserverProtocolSnapshot snapshot) {
  try {
    return <String, Object?>{
      'protocolVersion': snapshot.protocolVersion,
      'sessionId': snapshot.sessionId,
      'generatedAtMicros': snapshot.generatedAtMicros,
      'lastSequenceNumber': snapshot.lastSequenceNumber,
      'droppedEventCount': snapshot.droppedEventCount,
      'firstAvailableSequence': snapshot.firstAvailableSequence,
      'lastAvailableSequence': snapshot.lastAvailableSequence,
      'nodes': snapshot.nodes.map(_encodeNode).toList(),
      'dependencies': snapshot.dependencies.map(_encodeDependency).toList(),
      'scopes': snapshot.scopes.map(_encodeScope).toList(),
    };
  } on SerializationError {
    rethrow;
  } catch (error) {
    throw SerializationError('Failed to encode protocol snapshot', cause: error);
  }
}

Map<String, Object?> _encodeNode(ObserverNodeSnapshot node) => <String, Object?>{
  'objectId': node.objectId.value,
  'kind': node.kind.name,
  'debugLabel': node.debugLabel,
  'debugType': node.debugType,
  'createdAtMicros': node.createdAtMicros,
  'valueSummary': node.valueSummary == null
      ? null
      : <String, Object?>{
          'type': node.valueSummary!.type,
          'display': node.valueSummary!.display,
          'isRedacted': node.valueSummary!.isRedacted,
          'isTruncated': node.valueSummary!.isTruncated,
        },
};

Map<String, Object?> _encodeDependency(ObserverDependencySnapshot dependency) =>
    <String, Object?>{
      'trackerId': dependency.trackerId.value,
      'dependencyIds':
          (dependency.dependencyIds.map((id) => id.value).toList()..sort()),
    };

Map<String, Object?> _encodeScope(ObserverScopeSnapshot scope) => <String, Object?>{
  'scopeId': scope.scopeId.value,
  'debugLabel': scope.debugLabel,
  'resources': scope.resources
      .map(
        (resource) => <String, Object?>{
          'resourceId': resource.resourceId.value,
          'resourceKind': resource.resourceKind.name,
        },
      )
      .toList(),
};
