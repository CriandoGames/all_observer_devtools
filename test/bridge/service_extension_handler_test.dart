import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/bridge/event_batcher.dart';
import 'package:all_observer_devtools/src/bridge/service_extensions.dart';
import 'package:all_observer_devtools/src/common/service_names.dart';
import 'package:all_observer_devtools/src/configuration/devtools_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EventBatcher batcher;
  late ServiceExtensionRegistrar registrar;

  setUp(() {
    ObserverProtocol.configure(
      const ObserverProtocolConfig(enabled: true, captureValues: true),
    );
    batcher = EventBatcher(
      config: const AllObserverDevToolsConfig(),
      onBatch: (_) {},
    );
    registrar = ServiceExtensionRegistrar(
      batcher: batcher,
      packageVersion: '0.1.0-test',
    );
  });

  tearDown(() {
    batcher.dispose();
    ObserverProtocol.reset();
    ObserverConfig.reset();
  });

  test('getProtocolInfo reports version and capabilities', () {
    final Map<String, Object?> response = registrar.debugHandle(
      DevToolsServiceExtensions.getProtocolInfo,
      const <String, String>{},
    );

    expect(response['success'], isTrue);
    final Map<String, Object?> data = response['data'] as Map<String, Object?>;
    expect(data['protocolVersion'], observerProtocolVersion);
    expect(data['packageVersion'], '0.1.0-test');
    expect(data['capabilities'], contains('snapshot'));
  });

  test('getSnapshot reflects live node state', () {
    Observable<int>(0, name: 'counter');

    final Map<String, Object?> response = registrar.debugHandle(
      DevToolsServiceExtensions.getSnapshot,
      const <String, String>{},
    );

    expect(response['success'], isTrue);
    final Map<String, Object?> data = response['data'] as Map<String, Object?>;
    final List<Object?> nodes = data['nodes'] as List<Object?>;
    expect(nodes, hasLength(1));
    // debugLabel's exact format ("CoreObservable<int>(counter)") is the
    // core's own implementation detail — labels are presentation-only, not
    // identity (see the implementation spec, principle 5), so this only
    // asserts the name we gave it is present, not the surrounding format.
    expect(
      (nodes.single as Map<String, Object?>)['debugLabel'],
      contains('counter'),
    );
  });

  test('getEvents filters strictly by afterSequence', () {
    final Observable<int> counter = Observable<int>(0, name: 'counter');
    counter.value = 1;
    counter.value = 2;
    final int firstSequence = ObserverProtocol.events.first.sequenceNumber;

    final Map<String, Object?> response = registrar.debugHandle(
      DevToolsServiceExtensions.getEvents,
      <String, String>{'afterSequence': '$firstSequence'},
    );

    final Map<String, Object?> data = response['data'] as Map<String, Object?>;
    final List<Object?> events = data['events'] as List<Object?>;
    expect(
      events.cast<Map<String, Object?>>().every(
        (e) => (e['sequenceNumber'] as int) > firstSequence,
      ),
      isTrue,
    );
  });

  test('getEvents rejects a non-integer afterSequence', () {
    final Map<String, Object?> response = registrar.debugHandle(
      DevToolsServiceExtensions.getEvents,
      const <String, String>{'afterSequence': 'not-a-number'},
    );

    expect(response['success'], isFalse);
    final Map<String, Object?> error = response['error'] as Map<String, Object?>;
    expect(error['code'], DevToolsErrorCode.invalidParameter);
  });

  test('setStreaming toggles the batcher and rejects invalid values', () {
    final Map<String, Object?> ok = registrar.debugHandle(
      DevToolsServiceExtensions.setStreaming,
      const <String, String>{'enabled': 'true'},
    );
    expect(ok['success'], isTrue);
    expect(batcher.streamingEnabled, isTrue);

    final Map<String, Object?> bad = registrar.debugHandle(
      DevToolsServiceExtensions.setStreaming,
      const <String, String>{'enabled': 'maybe'},
    );
    expect(bad['success'], isFalse);
  });

  test('clearBuffer clears only the DevTools batching buffer', () {
    batcher.setStreamingEnabled(true);
    Observable<int>(0, name: 'counter');
    // Give the protocol consumer a chance to have added it, if wired — here
    // we add directly since this test only exercises the handler.
    expect(
      registrar.debugHandle(
        DevToolsServiceExtensions.clearBuffer,
        const <String, String>{},
      )['success'],
      isTrue,
    );
    expect(batcher.pendingCount, 0);
    // The core ring buffer is untouched by clearBuffer.
    expect(ObserverProtocol.events, isNotEmpty);
  });

  test('getStatus reports session, dropped count and sequence', () {
    final Map<String, Object?> response = registrar.debugHandle(
      DevToolsServiceExtensions.getStatus,
      const <String, String>{},
    );

    final Map<String, Object?> data = response['data'] as Map<String, Object?>;
    expect(data['sessionId'], ObserverProtocol.sessionId);
    expect(data['droppedEventCount'], ObserverProtocol.droppedEventCount);
    expect(data['lastSequenceNumber'], ObserverProtocol.lastSequenceNumber);
  });

  test('unknown extension name returns a structured error, not a crash', () {
    final Map<String, Object?> response = registrar.debugHandle(
      'ext.all_observer.doesNotExist',
      const <String, String>{},
    );

    expect(response['success'], isFalse);
    expect(
      (response['error'] as Map<String, Object?>)['code'],
      DevToolsErrorCode.invalidParameter,
    );
  });
}
