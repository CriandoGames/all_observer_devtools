import 'package:all_observer/all_observer.dart';
import 'package:flutter/material.dart';

import '../../models/node_model.dart';
import '../../store/devtools_store.dart';

/// Section 20.2: searchable/filterable node table with a detail panel.
/// Never renders a raw object — only [NodeModel.valueSummary]'s bounded,
/// pre-redacted display text.
class NodesScreen extends StatefulWidget {
  const NodesScreen({required this.store, super.key});

  final DevToolsStore store;

  @override
  State<NodesScreen> createState() => _NodesScreenState();
}

enum _LifecycleFilter { all, active, disposed }

class _NodesScreenState extends State<NodesScreen> {
  String _search = '';
  String? _kindFilter;
  _LifecycleFilter _lifecycleFilter = _LifecycleFilter.active;
  int? _selectedObjectId;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
    final List<NodeModel> allNodes = widget.store.nodes;
    final Set<String> kinds = allNodes.map((n) => n.kind).toSet();

    final List<NodeModel> filtered =
        allNodes.where((node) {
          if (_lifecycleFilter == _LifecycleFilter.active && node.isDisposed) {
            return false;
          }
          if (_lifecycleFilter == _LifecycleFilter.disposed && !node.isDisposed) {
            return false;
          }
          if (_kindFilter != null && node.kind != _kindFilter) {
            return false;
          }
          if (_search.isNotEmpty) {
            final String needle = _search.toLowerCase();
            return node.debugLabel.toLowerCase().contains(needle) ||
                '${node.objectId}'.contains(needle);
          }
          return true;
        }).toList()..sort((a, b) => a.objectId.compareTo(b.objectId));

    final NodeModel? selected = _selectedObjectId == null
        ? null
        : widget.store.nodeById(_selectedObjectId!);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search by label or id',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() => _search = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String?>(
                      value: _kindFilter,
                      hint: const Text('Kind'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('All kinds')),
                        for (final kind in kinds)
                          DropdownMenuItem(value: kind, child: Text(kind)),
                      ],
                      onChanged: (value) => setState(() => _kindFilter = value),
                    ),
                    const SizedBox(width: 8),
                    SegmentedButton<_LifecycleFilter>(
                      segments: const [
                        ButtonSegment(value: _LifecycleFilter.active, label: Text('Active')),
                        ButtonSegment(
                          value: _LifecycleFilter.disposed,
                          label: Text('Disposed'),
                        ),
                        ButtonSegment(value: _LifecycleFilter.all, label: Text('All')),
                      ],
                      selected: {_lifecycleFilter},
                      onSelectionChanged: (selection) =>
                          setState(() => _lifecycleFilter = selection.first),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final NodeModel node = filtered[index];
                    return ListTile(
                      dense: true,
                      selected: node.objectId == _selectedObjectId,
                      leading: Icon(
                        node.isDisposed ? Icons.block : Icons.circle,
                        size: 12,
                        color: node.isDisposed
                            ? Theme.of(context).colorScheme.outline
                            : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(node.debugLabel, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        '#${node.objectId} · ${node.kind} · '
                        '${node.valueSummary?.shortDisplay ?? '—'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => setState(() => _selectedObjectId = node.objectId),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 2,
          child: selected == null
              ? const Center(child: Text('Select a node'))
              : _NodeDetail(node: selected, store: widget.store),
        ),
      ],
    );
    });
  }
}

class _NodeDetail extends StatelessWidget {
  const _NodeDetail({required this.node, required this.store});

  final NodeModel node;
  final DevToolsStore store;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
      final Set<int> deps = store.dependenciesOf(node.objectId);
      final Set<int> dependents = store.dependentsOf(node.objectId);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(node.debugLabel, style: Theme.of(context).textTheme.titleMedium),
          Text('#${node.objectId} · ${node.kind} · ${node.debugType}'),
          const SizedBox(height: 12),
          Text('Value: ${node.valueSummary?.shortDisplay ?? '—'}'),
          if (node.valueSummary?.isRedacted ?? false)
            const Text('(redacted by the core\'s value policy)'),
          const SizedBox(height: 12),
          Text('Created at (µs): ${node.createdAtMicros}'),
          if (node.updatedAtMicros != null) Text('Last updated (µs): ${node.updatedAtMicros}'),
          if (node.isDisposed) ...[
            const Divider(),
            Text('Disposed at (µs): ${node.disposedAtMicros}'),
            Text('Listener count at dispose: ${node.listenerCountAtDispose ?? '—'}'),
            if (node.disposeReason != null) Text('Dispose reason: ${node.disposeReason}'),
          ],
          const Divider(),
          Text('Dependencies (${deps.length})', style: Theme.of(context).textTheme.titleSmall),
          if (deps.isEmpty) const Text('—') else Text(deps.map((id) => '#$id').join(', ')),
          const SizedBox(height: 8),
          Text(
            'Dependents (${dependents.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (dependents.isEmpty)
            const Text('—')
          else
            Text(dependents.map((id) => '#$id').join(', ')),
        ],
      );
    });
  }
}
