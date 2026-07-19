import 'package:all_observer/all_observer.dart';
import 'package:flutter/material.dart';

import '../../models/protocol_event_model.dart';
import '../../store/devtools_store.dart';

/// Section 20.3: events ordered by `sequenceNumber`. "Pause" only freezes
/// this screen's own rendering — it never touches `setStreaming` on the
/// bridge, per the spec's "pausar não deve necessariamente parar o
/// protocolo na aplicação" rule.
class TimelineScreen extends StatefulWidget {
  const TimelineScreen({required this.store, super.key});

  final DevToolsStore store;

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  bool _paused = false;
  List<ProtocolEventModel>? _pausedSnapshot;
  String _search = '';
  ProtocolEventModel? _selected;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
      final List<ProtocolEventModel> source = _paused
          ? (_pausedSnapshot ??= widget.store.timeline)
          : widget.store.timeline;

      final List<ProtocolEventModel> filtered = _search.isEmpty
          ? source
          : source.where((e) {
              final needle = _search.toLowerCase();
              return _eventTypeName(e).toLowerCase().contains(needle) ||
                  '${e.primarySubjectId ?? ''}'.contains(needle);
            }).toList();

      final List<ProtocolEventModel> ordered = filtered.reversed.toList();

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
                            hintText: 'Filter by event type or subject id',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) => setState(() => _search = value),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: _paused ? 'Resume' : 'Pause (view only)',
                        icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                        onPressed: () => setState(() {
                          _paused = !_paused;
                          if (!_paused) {
                            _pausedSnapshot = null;
                          }
                        }),
                      ),
                      IconButton(
                        tooltip: 'Clear local view',
                        icon: const Icon(Icons.clear_all),
                        onPressed: () => setState(() {
                          _pausedSnapshot = <ProtocolEventModel>[];
                          _paused = true;
                        }),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: ordered.length,
                    itemBuilder: (context, index) {
                      final ProtocolEventModel event = ordered[index];
                      return ListTile(
                        dense: true,
                        selected: identical(event, _selected),
                        leading: SizedBox(
                          width: 56,
                          child: Text('#${event.sequenceNumber}'),
                        ),
                        title: Text(_eventTypeName(event)),
                        subtitle: event.primarySubjectId == null
                            ? null
                            : Text('subject #${event.primarySubjectId}'),
                        onTap: () => setState(() => _selected = event),
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
            child: _selected == null
                ? const Center(child: Text('Select an event'))
                : _EventDetail(event: _selected!),
          ),
        ],
      );
    });
  }
}

String _eventTypeName(ProtocolEventModel event) => switch (event) {
  NodeCreatedEventModel() => 'Node created',
  NodeUpdatedEventModel() => 'Node updated',
  NodeDisposedEventModel() => 'Node disposed',
  TrackerRunStartedEventModel() => 'Tracker run started',
  TrackerRunFinishedEventModel() => 'Tracker run finished',
  DependenciesChangedEventModel() => 'Dependencies changed',
  ScopeCreatedEventModel() => 'Scope created',
  ScopeResourceRegisteredEventModel() => 'Scope resource registered',
  ScopeDisposedEventModel() => 'Scope disposed',
  WarningRaisedEventModel() => 'Warning raised',
};

class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.event});

  final ProtocolEventModel event;

  @override
  Widget build(BuildContext context) {
    final rows = <String>[
      'sequenceNumber: ${event.sequenceNumber}',
      'eventId: ${event.eventId}',
      'sessionId: ${event.sessionId}',
      'timestampMicros: ${event.timestampMicros}',
      ..._extraFields(event),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          _eventTypeName(event),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final row in rows) Text(row),
        if (event.stackTrace != null) ...[
          const Divider(),
          const Text('Stack trace:'),
          SelectableText(
            event.stackTrace!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  List<String> _extraFields(ProtocolEventModel event) => switch (event) {
    NodeCreatedEventModel e => [
      'objectId: ${e.objectId}',
      'kind: ${e.kind}',
      'debugLabel: ${e.debugLabel}',
      'debugType: ${e.debugType}',
      'initialValueSummary: ${e.initialValueSummary?.shortDisplay ?? '—'}',
    ],
    NodeUpdatedEventModel e => [
      'objectId: ${e.objectId}',
      'kind: ${e.kind}',
      'oldValueSummary: ${e.oldValueSummary?.shortDisplay ?? '—'}',
      'newValueSummary: ${e.newValueSummary?.shortDisplay ?? '—'}',
    ],
    NodeDisposedEventModel e => [
      'objectId: ${e.objectId}',
      'kind: ${e.kind}',
      'listenerCount: ${e.listenerCount}',
      'disposeReason: ${e.disposeReason ?? '—'}',
    ],
    TrackerRunStartedEventModel e => [
      'trackerId: ${e.trackerId}',
      'runId: ${e.runId}',
      'kind: ${e.kind}',
    ],
    TrackerRunFinishedEventModel e => [
      'trackerId: ${e.trackerId}',
      'runId: ${e.runId}',
      'kind: ${e.kind}',
      'durationMicros: ${e.durationMicros}',
      'dependencyIds: ${e.dependencyIds}',
      'completedWithError: ${e.completedWithError}',
    ],
    DependenciesChangedEventModel e => [
      'trackerId: ${e.trackerId}',
      'runId: ${e.runId}',
      'currentDependencyIds: ${e.currentDependencyIds}',
      'addedDependencyIds: ${e.addedDependencyIds}',
      'removedDependencyIds: ${e.removedDependencyIds}',
    ],
    ScopeCreatedEventModel e => [
      'scopeId: ${e.scopeId}',
      'debugLabel: ${e.debugLabel}',
    ],
    ScopeResourceRegisteredEventModel e => [
      'scopeId: ${e.scopeId}',
      'resourceId: ${e.resourceId}',
      'resourceKind: ${e.resourceKind}',
    ],
    ScopeDisposedEventModel e => [
      'scopeId: ${e.scopeId}',
      'registeredResourceCount: ${e.registeredResourceCount}',
      'disposedResourceCount: ${e.disposedResourceCount}',
      'failedDisposeCount: ${e.failedDisposeCount}',
    ],
    WarningRaisedEventModel e => [
      'warningCode: ${e.warningCode}',
      'severity: ${e.severity}',
      'message: ${e.message}',
      if (e.suggestion != null) 'suggestion: ${e.suggestion}',
      if (e.objectId != null) 'objectId: ${e.objectId}',
    ],
  };
}
