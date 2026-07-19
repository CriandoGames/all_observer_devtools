import 'package:all_observer/all_observer.dart';
import 'package:flutter/material.dart';

import '../../connection/connection_controller.dart';
import '../../models/node_model.dart';
import '../../store/devtools_store.dart';

/// Section 20.1: connection/session identity, per-kind counts, buffer and
/// dropped-event visibility. Every field here comes straight from
/// `DevToolsStore`/`ConnectionController` — nothing is inferred.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({required this.controller, super.key});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
      final DevToolsStore store = controller.store;
      final Map<String, int> countsByKind = <String, int>{};
      int activeCount = 0;
      for (final NodeModel node in store.nodes) {
        if (node.isDisposed) {
          continue;
        }
        activeCount++;
        countsByKind[node.kind] = (countsByKind[node.kind] ?? 0) + 1;
      }

      final rows = <(String, String)>[
        ('Package version', controller.protocolInfo?.packageVersion ?? '—'),
        (
          'Protocol version',
          '${controller.protocolInfo?.protocolVersion ?? '—'}',
        ),
        ('Session', store.sessionId ?? '—'),
        ('Last sequence number', '${store.lastAppliedSequence}'),
        ('Streaming', controller.state.name),
        ('Active nodes', '$activeCount'),
        for (final entry in countsByKind.entries)
          ('  · ${entry.key}', '${entry.value}'),
        ('Active dependency edges', '${store.dependencies.length}'),
        ('Active scopes', '${store.scopes.length}'),
        ('Warnings received', '${store.warnings.length}'),
        ('Timeline events retained', '${store.timeline.length}'),
        ('Core ring-buffer dropped events', '${store.coreDroppedEventCount}'),
        (
          'Snapshot applied at',
          store.snapshotAppliedAt?.toIso8601String() ?? '—',
        ),
        ('Needs resync', store.needsResync ? 'yes' : 'no'),
        ('Reconciliation diagnostics', '${store.diagnostics.length}'),
      ];

      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final (label, value) = rows[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 260,
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    });
  }
}
