import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/serialization/protocol_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'encodeProtocolInfo reports the current protocol version and capabilities',
    () {
      final Map<String, Object?> info = encodeProtocolInfo(
        packageVersion: '1.2.3',
      );

      expect(info['protocolVersion'], observerProtocolVersion);
      expect(info['packageVersion'], '1.2.3');
      expect(info['minimumSupportedProtocolVersion'], observerProtocolVersion);
      expect(info['maximumSupportedProtocolVersion'], observerProtocolVersion);
      expect(
        info['capabilities'],
        containsAll(<String>[
          DevToolsCapability.snapshot,
          DevToolsCapability.eventStream,
          DevToolsCapability.dependencies,
          DevToolsCapability.scopes,
          DevToolsCapability.warnings,
        ]),
      );
    },
  );

  test('encodeStatus reports every field the Overview panel needs', () {
    final Map<String, Object?> status = encodeStatus(
      sessionId: 'session-1',
      streamingEnabled: true,
      coreBufferedEventCount: 12,
      pendingBatchCount: 3,
      droppedEventCount: 1,
      transportDroppedEventCount: 0,
      transportOversizedEventCount: 2,
      transportClearedEventCount: 4,
      lastSequenceNumber: 42,
    );

    expect(status, <String, Object?>{
      'sessionId': 'session-1',
      'streamingEnabled': true,
      'coreBufferedEventCount': 12,
      'pendingBatchCount': 3,
      'droppedEventCount': 1,
      'transportDroppedEventCount': 0,
      'transportOversizedEventCount': 2,
      'transportClearedEventCount': 4,
      'lastSequenceNumber': 42,
    });
  });
}
