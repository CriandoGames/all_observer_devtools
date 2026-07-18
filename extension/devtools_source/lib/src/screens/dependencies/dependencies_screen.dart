import 'package:all_observer/all_observer.dart';
import 'package:flutter/material.dart';

import '../../models/dependency_model.dart';
import '../../store/devtools_store.dart';

/// Section 20.4: tabular edge list plus a focused deps/dependents view for
/// one selected node. No graph rendering in this MVP — the spec explicitly
/// allows (and for a first pass, prefers) a tabular fallback.
class DependenciesScreen extends StatefulWidget {
  const DependenciesScreen({required this.store, super.key});

  final DevToolsStore store;

  @override
  State<DependenciesScreen> createState() => _DependenciesScreenState();
}

class _DependenciesScreenState extends State<DependenciesScreen> {
  int? _focusedNodeId;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
    final List<DependencyModel> edges = widget.store.dependencies
      ..sort((a, b) => a.trackerId.compareTo(b.trackerId));

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: ListView.builder(
            itemCount: edges.length,
            itemBuilder: (context, index) {
              final DependencyModel edge = edges[index];
              final tracker = widget.store.nodeById(edge.trackerId);
              return ExpansionTile(
                title: Text(
                  '${tracker?.debugLabel ?? 'tracker'} (#${edge.trackerId}) '
                  'depends on ${edge.dependencyIds.length} node(s)',
                ),
                children: [
                  for (final int depId in edge.dependencyIds)
                    ListTile(
                      dense: true,
                      title: Text(
                        '#$depId — ${widget.store.nodeById(depId)?.debugLabel ?? 'unknown node'}',
                      ),
                      trailing: TextButton(
                        child: const Text('Focus'),
                        onPressed: () => setState(() => _focusedNodeId = depId),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: _focusedNodeId == null
              ? const Center(child: Text('Focus a node to see its edges'))
              : _FocusedNodeEdges(nodeId: _focusedNodeId!, store: widget.store),
        ),
      ],
    );
    });
  }
}

class _FocusedNodeEdges extends StatelessWidget {
  const _FocusedNodeEdges({required this.nodeId, required this.store});

  final int nodeId;
  final DevToolsStore store;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
      final node = store.nodeById(nodeId);
      final deps = store.dependenciesOf(nodeId);
      final dependents = store.dependentsOf(nodeId);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${node?.debugLabel ?? 'node'} (#$nodeId)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(),
          Text('Depends on (${deps.length})', style: Theme.of(context).textTheme.titleSmall),
          if (deps.isEmpty)
            const Text('—')
          else
            for (final id in deps)
              Text('#$id — ${store.nodeById(id)?.debugLabel ?? 'unknown node'}'),
          const SizedBox(height: 12),
          Text(
            'Depended on by (${dependents.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (dependents.isEmpty)
            const Text('—')
          else
            for (final id in dependents)
              Text('#$id — ${store.nodeById(id)?.debugLabel ?? 'unknown tracker'}'),
        ],
      );
    });
  }
}
