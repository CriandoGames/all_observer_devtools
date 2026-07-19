import 'dependency_model.dart';
import 'node_model.dart';
import 'protocol_event_model.dart';
import 'scope_model.dart';

/// Mirrors `ObserverProtocolSnapshot` / `encodeSnapshot`'s wire contract:
/// the authoritative base state the store reconciles live/buffered events
/// on top of. See `DevToolsStore` for the reconciliation rules.
final class ProtocolSnapshotModel {
  const ProtocolSnapshotModel({
    required this.protocolVersion,
    required this.sessionId,
    required this.generatedAtMicros,
    required this.lastSequenceNumber,
    required this.droppedEventCount,
    required this.firstAvailableSequence,
    required this.lastAvailableSequence,
    required this.nodes,
    required this.dependencies,
    required this.scopes,
  });

  factory ProtocolSnapshotModel.fromJson(Map<String, Object?> json) {
    final Object? protocolVersion = json['protocolVersion'];
    final Object? sessionId = json['sessionId'];
    final Object? generatedAtMicros = json['generatedAtMicros'];
    final Object? lastSequenceNumber = json['lastSequenceNumber'];
    final Object? droppedEventCount = json['droppedEventCount'];
    final Object? nodes = json['nodes'];
    final Object? dependencies = json['dependencies'];
    final Object? scopes = json['scopes'];
    if (protocolVersion is! int ||
        sessionId is! String ||
        generatedAtMicros is! int ||
        lastSequenceNumber is! int ||
        droppedEventCount is! int ||
        nodes is! List ||
        dependencies is! List ||
        scopes is! List) {
      throw ProtocolDecodeError('Malformed protocol snapshot.');
    }
    return ProtocolSnapshotModel(
      protocolVersion: protocolVersion,
      sessionId: sessionId,
      generatedAtMicros: generatedAtMicros,
      lastSequenceNumber: lastSequenceNumber,
      droppedEventCount: droppedEventCount,
      firstAvailableSequence: json['firstAvailableSequence'] as int?,
      lastAvailableSequence: json['lastAvailableSequence'] as int?,
      nodes: nodes
          .cast<Map<String, Object?>>()
          .map(NodeModel.fromSnapshotJson)
          .toList(),
      dependencies: dependencies
          .cast<Map<String, Object?>>()
          .map(DependencyModel.fromSnapshotJson)
          .toList(),
      scopes: scopes
          .cast<Map<String, Object?>>()
          .map(ScopeModel.fromSnapshotJson)
          .toList(),
    );
  }

  final int protocolVersion;
  final String sessionId;
  final int generatedAtMicros;
  final int lastSequenceNumber;
  final int droppedEventCount;
  final int? firstAvailableSequence;
  final int? lastAvailableSequence;
  final List<NodeModel> nodes;
  final List<DependencyModel> dependencies;
  final List<ScopeModel> scopes;
}
