/// Response of `ext.all_observer.getStatus`.
final class BridgeStatusModel {
  const BridgeStatusModel({
    required this.sessionId,
    required this.streamingEnabled,
    required this.coreBufferedEventCount,
    required this.pendingBatchCount,
    required this.droppedEventCount,
    required this.transportDroppedEventCount,
    required this.transportOversizedEventCount,
    required this.transportClearedEventCount,
    required this.lastSequenceNumber,
  });

  factory BridgeStatusModel.fromJson(
    Map<String, Object?> json,
  ) => BridgeStatusModel(
    sessionId: json['sessionId'] as String,
    streamingEnabled: json['streamingEnabled'] as bool,
    coreBufferedEventCount: json['coreBufferedEventCount'] as int,
    pendingBatchCount: json['pendingBatchCount'] as int,
    droppedEventCount: json['droppedEventCount'] as int,
    // Older bridge versions (before the transport-drop counter was added)
    // won't send this field — default to 0 rather than fail the whole
    // status parse over a purely additive field.
    transportDroppedEventCount: json['transportDroppedEventCount'] as int? ?? 0,
    transportOversizedEventCount:
        json['transportOversizedEventCount'] as int? ?? 0,
    transportClearedEventCount: json['transportClearedEventCount'] as int? ?? 0,
    lastSequenceNumber: json['lastSequenceNumber'] as int,
  );

  final String sessionId;
  final bool streamingEnabled;
  final int coreBufferedEventCount;
  final int pendingBatchCount;
  final int droppedEventCount;
  final int transportDroppedEventCount;
  final int transportOversizedEventCount;
  final int transportClearedEventCount;
  final int lastSequenceNumber;
}
