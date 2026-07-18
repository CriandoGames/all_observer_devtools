import 'protocol_event_model.dart';
import 'value_summary_model.dart';

/// Current-state view of one node, built by the store by folding the
/// snapshot entry (if any) with subsequent create/update/dispose events.
/// Mirrors `ObserverNodeSnapshot` plus the small amount of extra state the
/// store tracks (update/dispose timestamps) — it does not invent fields the
/// protocol does not provide.
final class NodeModel {
  const NodeModel({
    required this.objectId,
    required this.kind,
    required this.debugLabel,
    required this.debugType,
    required this.createdAtMicros,
    this.valueSummary,
    this.updatedAtMicros,
    this.isDisposed = false,
    this.disposedAtMicros,
    this.disposeReason,
    this.listenerCountAtDispose,
  });

  factory NodeModel.fromSnapshotJson(Map<String, Object?> json) {
    final Object? objectId = json['objectId'];
    final Object? kind = json['kind'];
    final Object? debugLabel = json['debugLabel'];
    final Object? debugType = json['debugType'];
    final Object? createdAtMicros = json['createdAtMicros'];
    if (objectId is! int ||
        kind is! String ||
        debugLabel is! String ||
        debugType is! String ||
        createdAtMicros is! int) {
      throw ProtocolDecodeError('Malformed node snapshot entry: $json');
    }
    final Object? valueSummaryJson = json['valueSummary'];
    return NodeModel(
      objectId: objectId,
      kind: kind,
      debugLabel: debugLabel,
      debugType: debugType,
      createdAtMicros: createdAtMicros,
      valueSummary: valueSummaryJson == null
          ? null
          : ValueSummaryModel.fromJson(valueSummaryJson as Map<String, Object?>),
    );
  }

  /// Stable identity — the only thing that should ever be used to look up
  /// or compare nodes. Never [debugLabel].
  final int objectId;
  final String kind;
  final String debugLabel;
  final String debugType;
  final int createdAtMicros;
  final ValueSummaryModel? valueSummary;
  final int? updatedAtMicros;
  final bool isDisposed;
  final int? disposedAtMicros;
  final String? disposeReason;

  /// Only known once [NodeDisposedEventModel] has been observed for this
  /// node — the protocol does not report a live listener count at any other
  /// point, so this is `null` while the node is active rather than a
  /// guessed `0`.
  final int? listenerCountAtDispose;

  NodeModel copyWith({
    ValueSummaryModel? valueSummary,
    int? updatedAtMicros,
    bool? isDisposed,
    int? disposedAtMicros,
    String? disposeReason,
    int? listenerCountAtDispose,
  }) => NodeModel(
    objectId: objectId,
    kind: kind,
    debugLabel: debugLabel,
    debugType: debugType,
    createdAtMicros: createdAtMicros,
    valueSummary: valueSummary ?? this.valueSummary,
    updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
    isDisposed: isDisposed ?? this.isDisposed,
    disposedAtMicros: disposedAtMicros ?? this.disposedAtMicros,
    disposeReason: disposeReason ?? this.disposeReason,
    listenerCountAtDispose: listenerCountAtDispose ?? this.listenerCountAtDispose,
  );
}
