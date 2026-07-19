import 'package:all_observer/all_observer.dart';
import 'package:flutter/material.dart';

import '../../models/warning_model.dart';
import '../../store/devtools_store.dart';

/// Section 20.6: warnings the core itself raised (misuse, possible listener
/// leaks it detected via its own `listenerLeakThreshold`, writes during
/// build, etc). This screen displays them; it does not invent new ones —
/// see [DevToolsStore.diagnostics] for the separate, explicitly-labeled
/// "reconciliation diagnostic" list this extension itself produces.
class WarningsScreen extends StatefulWidget {
  const WarningsScreen({required this.store, super.key});

  final DevToolsStore store;

  @override
  State<WarningsScreen> createState() => _WarningsScreenState();
}

class _WarningsScreenState extends State<WarningsScreen> {
  WarningSeverityModel? _severityFilter;
  String _search = '';

  @override
  Widget build(BuildContext context) {
    return Observer(() {
      final List<WarningModel> filtered = widget.store.warnings
          .where((warning) {
            if (_severityFilter != null &&
                warning.severity != _severityFilter) {
              return false;
            }
            if (_search.isNotEmpty &&
                !warning.message.toLowerCase().contains(
                  _search.toLowerCase(),
                ) &&
                !warning.warningCode.toLowerCase().contains(
                  _search.toLowerCase(),
                )) {
              return false;
            }
            return true;
          })
          .toList()
          .reversed
          .toList();

      return Column(
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
                      hintText: 'Search warnings',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _search = value),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<WarningSeverityModel?>(
                  value: _severityFilter,
                  hint: const Text('Severity'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    for (final severity in WarningSeverityModel.values)
                      DropdownMenuItem(
                        value: severity,
                        child: Text(severity.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _severityFilter = value),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No warnings.'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final WarningModel warning = filtered[index];
                      return ListTile(
                        leading: Icon(_severityIcon(warning.severity)),
                        title: Text(warning.message),
                        subtitle: Text(
                          [
                            warning.warningCode,
                            if (warning.objectId != null)
                              'node #${warning.objectId}',
                            if (warning.suggestion != null) warning.suggestion!,
                          ].join(' · '),
                        ),
                        trailing: Text('#${warning.sequenceNumber}'),
                      );
                    },
                  ),
          ),
        ],
      );
    });
  }
}

IconData _severityIcon(WarningSeverityModel severity) => switch (severity) {
  WarningSeverityModel.info => Icons.info_outline,
  WarningSeverityModel.warning => Icons.warning_amber,
  WarningSeverityModel.error => Icons.error_outline,
  WarningSeverityModel.unknown => Icons.help_outline,
};
