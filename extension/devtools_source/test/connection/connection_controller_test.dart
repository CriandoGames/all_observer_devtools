import 'dart:async';

import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools_extension/src/connection/connection_controller.dart';
import 'package:all_observer_devtools_extension/src/connection/connection_state.dart';
import 'package:all_observer_devtools_extension/src/connection/protocol_client.dart';
import 'package:all_observer_devtools_extension/src/models/event_batch_model.dart';
import 'package:all_observer_devtools_extension/src/models/protocol_event_model.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _ok(Map<String, Object?> data) => <String, Object?>{
  'success': true,
  'protocolVersion': 1,
  'sessionId': 's1',
  'data': data,
};

Map<String, Object?> _protocolInfoJson({int protocolVersion = 1}) =>
    <String, Object?>{
      'protocolVersion': protocolVersion,
      'packageVersion': '0.1.0',
      'minimumSupportedProtocolVersion': protocolVersion,
      'maximumSupportedProtocolVersion': protocolVersion,
      'capabilities': <String>['snapshot', 'event_stream'],
    };

Map<String, Object?> _snapshotJson({
  required String sessionId,
  required int lastSequenceNumber,
}) => <String, Object?>{
  'protocolVersion': 1,
  'sessionId': sessionId,
  'generatedAtMicros': 0,
  'lastSequenceNumber': lastSequenceNumber,
  'droppedEventCount': 0,
  'firstAvailableSequence': null,
  'lastAvailableSequence': null,
  'nodes': const <Object?>[],
  'dependencies': const <Object?>[],
  'scopes': const <Object?>[],
};

Map<String, Object?> _nodeCreatedEventJson({
  required String sessionId,
  required int sequenceNumber,
  required int objectId,
}) => <String, Object?>{
  'protocolVersion': 1,
  'sessionId': sessionId,
  'eventId': 'event-$sequenceNumber',
  'sequenceNumber': sequenceNumber,
  'timestampMicros': sequenceNumber * 1000,
  'eventType': 'nodeCreated',
  'objectId': objectId,
  'kind': 'observable',
  'debugLabel': 'node$objectId',
  'debugType': 'int',
  'initialValueSummary': null,
};

Map<String, Object?> _nodeUpdatedEventJson({
  required String sessionId,
  required int sequenceNumber,
  required int objectId,
}) => <String, Object?>{
  'protocolVersion': 1,
  'sessionId': sessionId,
  'eventId': 'event-$sequenceNumber',
  'sequenceNumber': sequenceNumber,
  'timestampMicros': sequenceNumber * 1000,
  'eventType': 'nodeUpdated',
  'objectId': objectId,
  'kind': 'observable',
  'oldValueSummary': null,
  'newValueSummary': null,
};

/// Minimal fake VM Service adapter: canned protocol-info/snapshot
/// responses, with the snapshot response advancing through a queue so a
/// test can simulate "state after resync differs from state before".
final class _FakeExtensionCaller {
  _FakeExtensionCaller({
    required this.protocolInfoJson,
    required List<Map<String, Object?>> snapshotJsonQueue,
  }) : _snapshotQueue = List<Map<String, Object?>>.of(snapshotJsonQueue);

  final Map<String, Object?> protocolInfoJson;
  final List<Map<String, Object?>> _snapshotQueue;
  int getSnapshotCallCount = 0;
  int getEventsCallCount = 0;
  bool streamingEnabled = false;
  Map<String, Object?> eventsJson = <String, Object?>{
    'protocolVersion': 1,
    'sessionId': 's1',
    'firstSequenceNumber': null,
    'lastSequenceNumber': 0,
    'events': <Object?>[],
  };

  Future<Map<String, Object?>> call(
    String method,
    Map<String, String> args,
  ) async {
    switch (method) {
      case 'ext.all_observer.getProtocolInfo':
        return _ok(protocolInfoJson);
      case 'ext.all_observer.getSnapshot':
        getSnapshotCallCount++;
        final Map<String, Object?> next = _snapshotQueue.length > 1
            ? _snapshotQueue.removeAt(0)
            : _snapshotQueue.first;
        return _ok(next);
      case 'ext.all_observer.getEvents':
        getEventsCallCount++;
        return _ok(eventsJson);
      case 'ext.all_observer.setStreaming':
        streamingEnabled = args['enabled'] == 'true';
        return _ok(<String, Object?>{'streamingEnabled': streamingEnabled});
      default:
        throw StateError('Unexpected method in test fake: $method');
    }
  }
}

/// Deliberately non-conforming transport used to prove logical cancellation:
/// it can deliver one callback even after its subscription was cancelled.
/// Real transports may have an already-queued callback at dispose time.
final class _LateDeliveryStream extends Stream<EventBatchModel> {
  void Function(EventBatchModel)? _onData;

  @override
  StreamSubscription<EventBatchModel> listen(
    void Function(EventBatchModel)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _onData = onData;
    return _LateSubscription<EventBatchModel>();
  }

  void emit(EventBatchModel batch) => _onData?.call(batch);
}

final class _LateSubscription<T> implements StreamSubscription<T> {
  @override
  Future<void> cancel() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('normal connection flow', () {
    test('reaches connected after protocol info + snapshot', () async {
      final fake = _FakeExtensionCaller(
        protocolInfoJson: _protocolInfoJson(),
        snapshotJsonQueue: [
          _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
        ],
      );
      final controller = ConnectionController(
        client: ProtocolClient(callExtension: fake.call),
        liveEvents: const Stream<EventBatchModel>.empty(),
      );
      addTearDown(controller.dispose);

      await controller.connect();

      expect(controller.state, DevToolsConnectionState.connected);
      expect(controller.store.sessionId, 's1');
      expect(fake.streamingEnabled, isTrue);
    });
  });

  group('protocol compatibility', () {
    test(
      'an incompatible protocol version stops before requesting a snapshot',
      () async {
        final fake = _FakeExtensionCaller(
          protocolInfoJson: _protocolInfoJson(protocolVersion: 2),
          snapshotJsonQueue: [
            _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
          ],
        );
        final controller = ConnectionController(
          client: ProtocolClient(callExtension: fake.call),
          liveEvents: const Stream<EventBatchModel>.empty(),
        );
        addTearDown(controller.dispose);

        await controller.connect();

        expect(controller.state, DevToolsConnectionState.incompatible);
        expect(fake.getSnapshotCallCount, 0);
      },
    );

    test(
      'an obsolete connection failure cannot overwrite a newer connection',
      () async {
        final firstInfo = Completer<Map<String, Object?>>();
        var infoCalls = 0;
        Future<Map<String, Object?>> call(
          String method,
          Map<String, String> args,
        ) async {
          switch (method) {
            case 'ext.all_observer.getProtocolInfo':
              infoCalls++;
              if (infoCalls == 1) return firstInfo.future;
              return _ok(_protocolInfoJson());
            case 'ext.all_observer.setStreaming':
              return _ok(<String, Object?>{'streamingEnabled': true});
            case 'ext.all_observer.getSnapshot':
              return _ok(
                _snapshotJson(sessionId: 'new-session', lastSequenceNumber: 0),
              );
            case 'ext.all_observer.getEvents':
              return _ok(<String, Object?>{
                'protocolVersion': 1,
                'sessionId': 'new-session',
                'firstSequenceNumber': null,
                'lastSequenceNumber': 0,
                'events': <Object?>[],
              });
            default:
              throw StateError(method);
          }
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: call),
          liveEvents: const Stream<EventBatchModel>.empty(),
        );
        addTearDown(controller.dispose);

        final firstConnect = controller.connect();
        await Future<void>.delayed(Duration.zero);
        await controller.connect();
        firstInfo.completeError(StateError('old connection failed'));
        await firstConnect;

        expect(controller.state, DevToolsConnectionState.connected);
        expect(controller.store.sessionId, 'new-session');
        expect(controller.errorMessage, isNull);
      },
    );

    test(
      'an obsolete snapshot cannot block or overwrite a new connection',
      () async {
        final oldSnapshot = Completer<Map<String, Object?>>();
        var snapshotCalls = 0;
        Future<Map<String, Object?>> call(
          String method,
          Map<String, String> args,
        ) async {
          switch (method) {
            case 'ext.all_observer.getProtocolInfo':
              return _ok(_protocolInfoJson());
            case 'ext.all_observer.setStreaming':
              return _ok(<String, Object?>{'streamingEnabled': true});
            case 'ext.all_observer.getSnapshot':
              snapshotCalls++;
              if (snapshotCalls == 1) return oldSnapshot.future;
              return _ok(
                _snapshotJson(sessionId: 'new-session', lastSequenceNumber: 0),
              );
            case 'ext.all_observer.getEvents':
              return _ok(<String, Object?>{
                'protocolVersion': 1,
                'sessionId': 'new-session',
                'firstSequenceNumber': null,
                'lastSequenceNumber': 0,
                'events': <Object?>[],
              });
            default:
              throw StateError(method);
          }
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: call),
          liveEvents: const Stream<EventBatchModel>.empty(),
        );
        addTearDown(controller.dispose);

        final first = controller.connect();
        await Future<void>.delayed(Duration.zero);
        final second = controller.connect();
        await Future<void>.delayed(Duration.zero);
        expect(snapshotCalls, 2);
        await second;
        oldSnapshot.complete(
          _ok(_snapshotJson(sessionId: 'old-session', lastSequenceNumber: 99)),
        );
        await first;

        expect(controller.state, DevToolsConnectionState.connected);
        expect(controller.store.sessionId, 'new-session');
        expect(controller.store.lastAppliedSequence, 0);
      },
    );
  });

  group('snapshot/event race (section 12)', () {
    test(
      'retries when the polling session changed after the snapshot',
      () async {
        var snapshotCalls = 0;
        var eventsCalls = 0;

        Future<Map<String, Object?>> call(
          String method,
          Map<String, String> args,
        ) async {
          switch (method) {
            case 'ext.all_observer.getProtocolInfo':
              return _ok(_protocolInfoJson());
            case 'ext.all_observer.setStreaming':
              return _ok(<String, Object?>{'streamingEnabled': true});
            case 'ext.all_observer.getSnapshot':
              snapshotCalls++;
              return _ok(
                _snapshotJson(
                  sessionId: snapshotCalls == 1 ? 'old-session' : 'new-session',
                  lastSequenceNumber: 0,
                ),
              );
            case 'ext.all_observer.getEvents':
              eventsCalls++;
              return _ok(<String, Object?>{
                'protocolVersion': 1,
                'sessionId': 'new-session',
                'firstSequenceNumber': null,
                'lastSequenceNumber': 0,
                'events': <Object?>[],
              });
            default:
              throw StateError(method);
          }
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: call),
          liveEvents: const Stream<EventBatchModel>.empty(),
        );
        addTearDown(controller.dispose);

        await controller.connect();

        expect(controller.state, DevToolsConnectionState.connected);
        expect(controller.store.sessionId, 'new-session');
        expect(snapshotCalls, 2);
        expect(eventsCalls, 2);
      },
    );

    test(
      'retries when polling proves an unrepresented sequence tail',
      () async {
        var snapshotCalls = 0;
        Future<Map<String, Object?>> call(
          String method,
          Map<String, String> args,
        ) async {
          switch (method) {
            case 'ext.all_observer.getProtocolInfo':
              return _ok(_protocolInfoJson());
            case 'ext.all_observer.setStreaming':
              return _ok(<String, Object?>{'streamingEnabled': true});
            case 'ext.all_observer.getSnapshot':
              snapshotCalls++;
              return _ok(
                _snapshotJson(
                  sessionId: 's1',
                  lastSequenceNumber: snapshotCalls == 1 ? 0 : 1,
                ),
              );
            case 'ext.all_observer.getEvents':
              return _ok(<String, Object?>{
                'protocolVersion': 1,
                'sessionId': 's1',
                'firstSequenceNumber': null,
                'lastSequenceNumber': 1,
                'events': <Object?>[],
              });
            default:
              throw StateError(method);
          }
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: call),
          liveEvents: const Stream<EventBatchModel>.empty(),
        );
        addTearDown(controller.dispose);

        await controller.connect();

        expect(controller.state, DevToolsConnectionState.connected);
        expect(controller.store.lastAppliedSequence, 1);
        expect(snapshotCalls, 2);
      },
    );

    test(
      'enables real streaming before snapshot and closes the backlog window',
      () async {
        final liveController = StreamController<EventBatchModel>.broadcast();
        addTearDown(liveController.close);
        final fake = _FakeExtensionCaller(
          protocolInfoJson: _protocolInfoJson(),
          snapshotJsonQueue: [
            _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
          ],
        );
        final List<String> calls = <String>[];

        Future<Map<String, Object?>> transport(
          String method,
          Map<String, String> args,
        ) async {
          calls.add(method);
          final response = await fake.call(method, args);
          if (method == 'ext.all_observer.getSnapshot') {
            // This event is created after the snapshot. A real batcher only
            // puts it on the stream if setStreaming(true) already happened.
            final event = ProtocolEventModel.fromJson(
              _nodeCreatedEventJson(
                sessionId: 's1',
                sequenceNumber: 1,
                objectId: 42,
              ),
            );
            fake.eventsJson = <String, Object?>{
              'protocolVersion': 1,
              'sessionId': 's1',
              'firstSequenceNumber': 1,
              'lastSequenceNumber': 1,
              'events': <Object?>[
                _nodeCreatedEventJson(
                  sessionId: 's1',
                  sequenceNumber: 1,
                  objectId: 42,
                ),
              ],
            };
            if (fake.streamingEnabled) {
              liveController.add(
                EventBatchModel(
                  protocolVersion: 1,
                  sessionId: 's1',
                  firstSequenceNumber: 1,
                  lastSequenceNumber: 1,
                  events: <ProtocolEventModel>[event],
                ),
              );
            }
          }
          return response;
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: transport),
          liveEvents: liveController.stream,
        );
        addTearDown(controller.dispose);

        await controller.connect();
        await Future<void>.delayed(Duration.zero);

        expect(
          calls.indexOf('ext.all_observer.setStreaming'),
          lessThan(calls.indexOf('ext.all_observer.getSnapshot')),
        );
        expect(fake.getEventsCallCount, 1);
        expect(controller.store.lastAppliedSequence, 1);
        expect(controller.store.nodeById(42), isNotNull);
      },
    );

    test(
      'an event that arrives while the snapshot is loading is buffered then applied',
      () async {
        final liveController = StreamController<EventBatchModel>.broadcast();
        addTearDown(liveController.close);

        // Snapshot resolves at lastSequenceNumber=0; an event for sequence 1
        // is pushed onto the live stream "during" the snapshot fetch by
        // reacting to getSnapshot being called.
        late _FakeExtensionCaller fake;
        fake = _FakeExtensionCaller(
          protocolInfoJson: _protocolInfoJson(),
          snapshotJsonQueue: [
            _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
          ],
        );
        Future<Map<String, Object?>> delayedCaller(
          String method,
          Map<String, String> args,
        ) async {
          final result = fake.call(method, args);
          if (method == 'ext.all_observer.getSnapshot') {
            liveController.add(
              EventBatchModel(
                protocolVersion: 1,
                sessionId: 's1',
                firstSequenceNumber: 1,
                lastSequenceNumber: 1,
                events: [
                  ProtocolEventModel.fromJson(
                    _nodeCreatedEventJson(
                      sessionId: 's1',
                      sequenceNumber: 1,
                      objectId: 42,
                    ),
                  ),
                ],
              ),
            );
          }
          return result;
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: delayedCaller),
          liveEvents: liveController.stream,
        );
        addTearDown(controller.dispose);

        await controller.connect();
        await Future<void>.delayed(Duration.zero);

        expect(controller.state, DevToolsConnectionState.connected);
        expect(controller.store.lastAppliedSequence, 1);
        expect(controller.store.nodeById(42), isNotNull);
      },
    );
  });

  group('gap-triggered resync', () {
    test('a semantic inconsistency also triggers a fresh snapshot', () async {
      final liveController = StreamController<EventBatchModel>.broadcast();
      addTearDown(liveController.close);
      final fake = _FakeExtensionCaller(
        protocolInfoJson: _protocolInfoJson(),
        snapshotJsonQueue: [
          _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
          _snapshotJson(sessionId: 's1', lastSequenceNumber: 1),
        ],
      );
      final controller = ConnectionController(
        client: ProtocolClient(callExtension: fake.call),
        liveEvents: liveController.stream,
      );
      addTearDown(controller.dispose);
      await controller.connect();
      fake.eventsJson = <String, Object?>{
        'protocolVersion': 1,
        'sessionId': 's1',
        'firstSequenceNumber': null,
        'lastSequenceNumber': 1,
        'events': <Object?>[],
      };

      final update = ProtocolEventModel.fromJson(
        _nodeUpdatedEventJson(sessionId: 's1', sequenceNumber: 1, objectId: 99),
      );
      liveController.add(
        EventBatchModel(
          protocolVersion: 1,
          sessionId: 's1',
          firstSequenceNumber: 1,
          lastSequenceNumber: 1,
          events: <ProtocolEventModel>[update],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(fake.getSnapshotCallCount, 2);
      expect(controller.store.lastAppliedSequence, 1);
      expect(controller.store.needsResync, isFalse);
      expect(controller.state, DevToolsConnectionState.connected);
    });

    test(
      'a sequence gap on the live stream triggers a fresh snapshot and recovers',
      () async {
        final liveController = StreamController<EventBatchModel>.broadcast();
        addTearDown(liveController.close);
        final fake = _FakeExtensionCaller(
          protocolInfoJson: _protocolInfoJson(),
          snapshotJsonQueue: [
            _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
            _snapshotJson(sessionId: 's1', lastSequenceNumber: 10),
          ],
        );
        final controller = ConnectionController(
          client: ProtocolClient(callExtension: fake.call),
          liveEvents: liveController.stream,
        );
        addTearDown(controller.dispose);

        await controller.connect();
        expect(controller.state, DevToolsConnectionState.connected);

        // The real registrar reports the protocol's current tail even when
        // the filtered polling response is empty.
        fake.eventsJson = <String, Object?>{
          'protocolVersion': 1,
          'sessionId': 's1',
          'firstSequenceNumber': null,
          'lastSequenceNumber': 10,
          'events': <Object?>[],
        };

        // Sequence 5 while the store is only caught up to 0: a gap.
        liveController.add(
          EventBatchModel(
            protocolVersion: 1,
            sessionId: 's1',
            firstSequenceNumber: 5,
            lastSequenceNumber: 5,
            events: [
              ProtocolEventModel.fromJson(
                _nodeCreatedEventJson(
                  sessionId: 's1',
                  sequenceNumber: 5,
                  objectId: 7,
                ),
              ),
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(fake.getSnapshotCallCount, 2);
        expect(controller.state, DevToolsConnectionState.connected);
        expect(controller.store.lastAppliedSequence, 10);
        expect(controller.store.needsResync, isFalse);
      },
    );

    test('multiple rapid gap batches share one active snapshot', () async {
      final liveController = StreamController<EventBatchModel>.broadcast();
      addTearDown(liveController.close);
      final resyncSnapshot = Completer<Map<String, Object?>>();
      var snapshotCalls = 0;
      var streaming = false;

      Future<Map<String, Object?>> call(
        String method,
        Map<String, String> args,
      ) async {
        switch (method) {
          case 'ext.all_observer.getProtocolInfo':
            return _ok(_protocolInfoJson());
          case 'ext.all_observer.setStreaming':
            streaming = args['enabled'] == 'true';
            return _ok(<String, Object?>{'streamingEnabled': streaming});
          case 'ext.all_observer.getSnapshot':
            snapshotCalls++;
            if (snapshotCalls == 1) {
              return _ok(_snapshotJson(sessionId: 's1', lastSequenceNumber: 0));
            }
            return resyncSnapshot.future;
          case 'ext.all_observer.getEvents':
            return _ok(<String, Object?>{
              'protocolVersion': 1,
              'sessionId': 's1',
              'firstSequenceNumber': null,
              'lastSequenceNumber': snapshotCalls > 1 ? 7 : 0,
              'events': <Object?>[],
            });
          default:
            throw StateError(method);
        }
      }

      final controller = ConnectionController(
        client: ProtocolClient(callExtension: call),
        liveEvents: liveController.stream,
      );
      addTearDown(controller.dispose);
      await controller.connect();

      EventBatchModel gap(int sequence) => EventBatchModel(
        protocolVersion: 1,
        sessionId: 's1',
        firstSequenceNumber: sequence,
        lastSequenceNumber: sequence,
        events: <ProtocolEventModel>[
          ProtocolEventModel.fromJson(
            _nodeCreatedEventJson(
              sessionId: 's1',
              sequenceNumber: sequence,
              objectId: sequence,
            ),
          ),
        ],
      );

      liveController
        ..add(gap(5))
        ..add(gap(6))
        ..add(gap(7));
      await Future<void>.delayed(Duration.zero);
      expect(snapshotCalls, 2);

      resyncSnapshot.complete(
        _ok(_snapshotJson(sessionId: 's1', lastSequenceNumber: 7)),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(snapshotCalls, 2);
      expect(controller.store.lastAppliedSequence, 7);
      expect(controller.state, DevToolsConnectionState.connected);
    });

    test(
      'snapshot failure releases buffering and permits a bounded retry',
      () async {
        final liveController = StreamController<EventBatchModel>.broadcast();
        addTearDown(liveController.close);
        var snapshotCalls = 0;
        Future<Map<String, Object?>> call(
          String method,
          Map<String, String> args,
        ) async {
          switch (method) {
            case 'ext.all_observer.getProtocolInfo':
              return _ok(_protocolInfoJson());
            case 'ext.all_observer.setStreaming':
              return _ok(<String, Object?>{'streamingEnabled': true});
            case 'ext.all_observer.getSnapshot':
              snapshotCalls++;
              if (snapshotCalls == 1) throw StateError('snapshot failed');
              return _ok(_snapshotJson(sessionId: 's1', lastSequenceNumber: 0));
            case 'ext.all_observer.getEvents':
              return _ok(<String, Object?>{
                'protocolVersion': 1,
                'sessionId': 's1',
                'firstSequenceNumber': null,
                'lastSequenceNumber': 0,
                'events': <Object?>[],
              });
            default:
              throw StateError(method);
          }
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: call),
          liveEvents: liveController.stream,
        );
        addTearDown(controller.dispose);

        await controller.connect();
        expect(controller.state, DevToolsConnectionState.error);
        await controller.connect();
        expect(controller.state, DevToolsConnectionState.connected);
        expect(snapshotCalls, 2);
      },
    );

    test(
      'a gap-triggered snapshot failure is handled and can recover',
      () async {
        final liveController = StreamController<EventBatchModel>.broadcast();
        addTearDown(liveController.close);
        var snapshotCalls = 0;
        Future<Map<String, Object?>> call(
          String method,
          Map<String, String> args,
        ) async {
          switch (method) {
            case 'ext.all_observer.getProtocolInfo':
              return _ok(_protocolInfoJson());
            case 'ext.all_observer.setStreaming':
              return _ok(<String, Object?>{'streamingEnabled': true});
            case 'ext.all_observer.getSnapshot':
              snapshotCalls++;
              if (snapshotCalls == 2) {
                throw StateError('sensitive snapshot detail');
              }
              return _ok(
                _snapshotJson(
                  sessionId: 's1',
                  lastSequenceNumber: snapshotCalls == 1 ? 0 : 10,
                ),
              );
            case 'ext.all_observer.getEvents':
              return _ok(<String, Object?>{
                'protocolVersion': 1,
                'sessionId': 's1',
                'firstSequenceNumber': null,
                'lastSequenceNumber': snapshotCalls > 1 ? 10 : 0,
                'events': <Object?>[],
              });
            default:
              throw StateError(method);
          }
        }

        final controller = ConnectionController(
          client: ProtocolClient(callExtension: call),
          liveEvents: liveController.stream,
        );
        addTearDown(controller.dispose);
        await controller.connect();

        EventBatchModel gap(int sequence) => EventBatchModel(
          protocolVersion: 1,
          sessionId: 's1',
          firstSequenceNumber: sequence,
          lastSequenceNumber: sequence,
          events: <ProtocolEventModel>[
            ProtocolEventModel.fromJson(
              _nodeCreatedEventJson(
                sessionId: 's1',
                sequenceNumber: sequence,
                objectId: sequence,
              ),
            ),
          ],
        );

        liveController.add(gap(5));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, DevToolsConnectionState.error);
        expect(
          controller.errorMessage,
          isNot(contains('sensitive snapshot detail')),
        );

        liveController.add(gap(6));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(controller.state, DevToolsConnectionState.connected);
        expect(controller.store.lastAppliedSequence, 10);
        expect(snapshotCalls, 3);
      },
    );
  });

  test(
    'dispose ignores a transport callback that was already queued',
    () async {
      ObserverConfig.strictMode = true;
      addTearDown(ObserverConfig.reset);
      final stream = _LateDeliveryStream();
      final fake = _FakeExtensionCaller(
        protocolInfoJson: _protocolInfoJson(),
        snapshotJsonQueue: [
          _snapshotJson(sessionId: 's1', lastSequenceNumber: 0),
        ],
      );
      final controller = ConnectionController(
        client: ProtocolClient(callExtension: fake.call),
        liveEvents: stream,
      );
      await controller.connect();
      controller.dispose();

      final event = ProtocolEventModel.fromJson(
        _nodeCreatedEventJson(sessionId: 's1', sequenceNumber: 1, objectId: 1),
      );
      final batch = EventBatchModel(
        protocolVersion: 1,
        sessionId: 's1',
        firstSequenceNumber: 1,
        lastSequenceNumber: 1,
        events: <ProtocolEventModel>[event],
      );

      expect(() => stream.emit(batch), returnsNormally);
    },
  );
}
