import 'dart:async';

import 'package:all_observer_devtools_extension/src/common/service_names.dart';
import 'package:all_observer_devtools_extension/src/connection/vm_service_connection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vm_service/vm_service.dart';

final class _FakeVmService implements VmService {
  final StreamController<Event> extensionEvents =
      StreamController<Event>.broadcast();
  final List<String?> calledIsolates = <String?>[];
  Object? streamListenError;
  Completer<Success>? streamListenCompleter;

  @override
  Stream<Event> get onExtensionEvent => extensionEvents.stream;

  @override
  Future<Success> streamListen(String streamId) async {
    final error = streamListenError;
    if (error != null) throw error;
    final completer = streamListenCompleter;
    if (completer != null) return completer.future;
    return Success();
  }

  @override
  Future<Response> callServiceExtension(
    String method, {
    String? isolateId,
    Map<String, dynamic>? args,
  }) async {
    calledIsolates.add(isolateId);
    final response = Response();
    response.json = <String, dynamic>{
      'success': true,
      'protocolVersion': 1,
      'sessionId': 's1',
      'data': <String, Object?>{
        'protocolVersion': 1,
        'packageVersion': 'test',
        'minimumSupportedProtocolVersion': 1,
        'maximumSupportedProtocolVersion': 1,
        'capabilities': <String>[],
      },
    };
    return response;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Event _batchEvent(String isolateId, String sessionId) {
  final data = ExtensionData()
    ..data.addAll(<String, dynamic>{
      'protocolVersion': 1,
      'sessionId': sessionId,
      'firstSequenceNumber': null,
      'lastSequenceNumber': 0,
      'events': <Object?>[],
    });
  return Event(
    kind: EventKind.kExtension,
    isolate: IsolateRef(id: isolateId),
    extensionKind: devtoolsEventStreamKind,
    extensionData: data,
  );
}

void main() {
  test('client and live stream stay bound to the selected isolate', () async {
    final service = _FakeVmService();
    addTearDown(service.extensionEvents.close);
    final adapter = VmServiceConnection(
      service: service,
      selectedIsolateId: 'isolate-1',
    );
    addTearDown(adapter.dispose);
    final receivedSessions = <String>[];
    final subscription = adapter.liveEvents.listen(
      (batch) => receivedSessions.add(batch.sessionId),
    );
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);

    service.extensionEvents
      ..add(_batchEvent('isolate-2', 'foreign-session'))
      ..add(_batchEvent('isolate-1', 'selected-session'));
    await Future<void>.delayed(Duration.zero);
    await adapter.buildProtocolClient().getProtocolInfo();

    expect(receivedSessions, <String>['selected-session']);
    expect(service.calledIsolates, <String?>['isolate-1']);
  });

  test(
    'unexpected streamListen errors surface a sanitized diagnostic',
    () async {
      final service = _FakeVmService()
        ..streamListenError = RPCError(
          'streamListen',
          999,
          'super-secret-transport-detail',
          null,
        );
      addTearDown(service.extensionEvents.close);
      final connection = VmServiceConnection(
        service: service,
        selectedIsolateId: 'isolate-1',
      );
      addTearDown(connection.dispose);
      final errors = <Object>[];

      connection.liveEvents.listen((_) {}, onError: errors.add);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<LiveBatchTransportException>());
      expect(
        connection.lastDecodeDiagnostic,
        allOf(contains('RPCError'), isNot(contains('super-secret'))),
      );
    },
  );

  test('dispose during streamListen prevents a late subscription', () async {
    final listenCompleter = Completer<Success>();
    final service = _FakeVmService()..streamListenCompleter = listenCompleter;
    addTearDown(service.extensionEvents.close);
    final connection = VmServiceConnection(
      service: service,
      selectedIsolateId: 'isolate-1',
    );

    connection.liveEvents.listen((_) {});
    await Future<void>.delayed(Duration.zero);
    connection.dispose();
    listenCompleter.complete(Success());
    await Future<void>.delayed(Duration.zero);

    expect(service.extensionEvents.hasListener, isFalse);
  });
}
