import 'dart:convert';
import 'dart:io';

import 'package:all_observer/all_observer.dart';
import 'package:all_observer_devtools/src/serialization/snapshot_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodeSnapshot matches the protocol v1 golden fixture', () {
    final ObserverProtocolSnapshot snapshot = ObserverProtocolSnapshot(
      protocolVersion: observerProtocolVersion,
      sessionId: 'session-fixture',
      generatedAtMicros: 2000,
      lastSequenceNumber: 5,
      droppedEventCount: 0,
      firstAvailableSequence: 1,
      lastAvailableSequence: 5,
      nodes: <ObserverNodeSnapshot>[
        const ObserverNodeSnapshot(
          objectId: ObserverNodeId(1),
          kind: ObserverNodeKind.observable,
          debugLabel: 'counter',
          debugType: 'int',
          createdAtMicros: 1000,
          valueSummary: ObserverValueSummary(type: 'int', display: '0'),
        ),
        const ObserverNodeSnapshot(
          objectId: ObserverNodeId(2),
          kind: ObserverNodeKind.computed,
          debugLabel: 'doubled',
          debugType: 'int',
          createdAtMicros: 1100,
        ),
      ],
      dependencies: <ObserverDependencySnapshot>[
        ObserverDependencySnapshot(
          trackerId: const ObserverNodeId(2),
          dependencyIds: <ObserverNodeId>{const ObserverNodeId(1)},
        ),
      ],
      scopes: <ObserverScopeSnapshot>[
        ObserverScopeSnapshot(
          scopeId: const ObserverNodeId(3),
          debugLabel: 'homeScope',
          resources: const <ObserverScopeResourceSnapshot>[
            ObserverScopeResourceSnapshot(
              resourceId: ObserverNodeId(4),
              resourceKind: ObserverNodeKind.subscription,
            ),
          ],
        ),
      ],
    );

    final Map<String, Object?> actual = encodeSnapshot(snapshot);
    final Map<String, Object?> expected =
        jsonDecode(File('test/fixtures/protocol_v1/snapshot.json').readAsStringSync())
            as Map<String, Object?>;

    expect(jsonDecode(jsonEncode(actual)), expected);
  });

  test('empty snapshot encodes to empty lists, not nulls', () {
    final ObserverProtocolSnapshot snapshot = ObserverProtocolSnapshot(
      protocolVersion: observerProtocolVersion,
      sessionId: 's1',
      generatedAtMicros: 0,
      lastSequenceNumber: 0,
      droppedEventCount: 0,
      firstAvailableSequence: null,
      lastAvailableSequence: null,
      nodes: const <ObserverNodeSnapshot>[],
      dependencies: const <ObserverDependencySnapshot>[],
      scopes: const <ObserverScopeSnapshot>[],
    );

    final Map<String, Object?> encoded = encodeSnapshot(snapshot);

    expect(encoded['nodes'], isEmpty);
    expect(encoded['dependencies'], isEmpty);
    expect(encoded['scopes'], isEmpty);
    expect(encoded['firstAvailableSequence'], isNull);
    expect(encoded['lastAvailableSequence'], isNull);
  });
}
