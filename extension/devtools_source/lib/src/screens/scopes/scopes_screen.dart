import 'package:all_observer/all_observer.dart';
import 'package:flutter/material.dart';

import '../../models/scope_model.dart';
import '../../store/devtools_store.dart';

/// Section 20.5: active scopes and their registered resources. Disposed
/// scopes are not kept as "active" anywhere in this store (matching the
/// core's own registry) — their disposal, including
/// `failedDisposeCount`, is visible in the Timeline/diagnostics instead of
/// here. This screen never labels an active resource a leak — only
/// "possible lifecycle inconsistency" diagnostics (from
/// [DevToolsStore.diagnostics]) use that language, and only when the
/// protocol itself reported something objectively inconsistent.
class ScopesScreen extends StatelessWidget {
  const ScopesScreen({required this.store, super.key});

  final DevToolsStore store;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
      final List<ScopeModel> scopes = store.scopes
        ..sort((a, b) => a.scopeId.compareTo(b.scopeId));

      if (scopes.isEmpty && store.diagnostics.isEmpty) {
        return const Center(child: Text('No active scopes.'));
      }

      return ListView(
        padding: const EdgeInsets.all(8),
        children: [
          for (final scope in scopes)
            Card(
              child: ExpansionTile(
                title: Text('${scope.debugLabel} (#${scope.scopeId})'),
                subtitle: Text(
                  '${scope.resources.length} resource(s) registered',
                ),
                children: [
                  for (final resource in scope.resources)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.link, size: 16),
                      title: Text(
                        '#${resource.resourceId} — ${resource.resourceKind}',
                      ),
                    ),
                  if (scope.resources.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No resources registered yet.'),
                    ),
                ],
              ),
            ),
          if (store.diagnostics.any(
            (d) => d.code == 'scope_dispose_failures',
          )) ...[
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Disposal diagnostics:'),
            ),
            for (final diag in store.diagnostics.where(
              (d) => d.code == 'scope_dispose_failures',
            ))
              ListTile(
                dense: true,
                leading: const Icon(Icons.info_outline, size: 16),
                title: Text(diag.message),
                subtitle: diag.atSequenceNumber == null
                    ? null
                    : Text('at sequence #${diag.atSequenceNumber}'),
              ),
          ],
        ],
      );
    });
  }
}
