import 'package:all_observer/all_observer.dart';
import 'package:flutter/material.dart';

import '../connection/connection_controller.dart';
import '../connection/connection_state.dart';

/// Explains the current [DevToolsConnectionState] with an icon *and* text —
/// never color alone (implementation spec section 29: accessibility must
/// not depend only on color). Hidden entirely once [DevToolsConnectionState
/// .connected] and no reconciliation problem is outstanding, so it never
/// competes with the data screens for attention when everything is fine.
///
/// The whole banner is one `Observer`: every field it reads
/// (`controller.state`, `controller.store.needsResync`,
/// `controller.store.coreDroppedEventCount`, `controller.errorMessage`,
/// `controller.protocolInfo`) is `all_observer`-reactive, so this widget
/// needs no manual listener wiring.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({required this.controller, super.key});

  final ConnectionController controller;

  @override
  Widget build(BuildContext context) {
    return Observer(() {
      final state = controller.state;
      final needsResync = controller.store.needsResync;
      final droppedCore = controller.store.coreDroppedEventCount;

      if (state == DevToolsConnectionState.connected && !needsResync && droppedCore == 0) {
        return const SizedBox.shrink();
      }

      final (IconData icon, String text, Color color) = switch (state) {
      DevToolsConnectionState.disconnected => (
        Icons.link_off,
        'Not connected to a running app.',
        Theme.of(context).colorScheme.outline,
      ),
      DevToolsConnectionState.connecting => (
        Icons.sync,
        'Connecting…',
        Theme.of(context).colorScheme.primary,
      ),
      DevToolsConnectionState.loadingProtocolInfo => (
        Icons.sync,
        'Checking Observer Protocol compatibility…',
        Theme.of(context).colorScheme.primary,
      ),
      DevToolsConnectionState.loadingSnapshot => (
        Icons.sync,
        'Loading snapshot…',
        Theme.of(context).colorScheme.primary,
      ),
      DevToolsConnectionState.synchronizing => (
        Icons.sync,
        'Synchronizing…',
        Theme.of(context).colorScheme.primary,
      ),
      DevToolsConnectionState.reconnecting => (
        Icons.sync_problem,
        'Sequence gap detected — reloading a fresh snapshot…',
        Theme.of(context).colorScheme.tertiary,
      ),
      DevToolsConnectionState.incompatible => (
        Icons.block,
        'Incompatible Observer Protocol version '
            '(bridge: ${controller.protocolInfo?.protocolVersion}, '
            'extension supports: 1). Update one side to match.',
        Theme.of(context).colorScheme.error,
      ),
      DevToolsConnectionState.unavailable => (
        Icons.help_outline,
        'No all_observer_devtools bridge detected on this isolate. '
            'Call AllObserverDevTools.initialize() in main().',
        Theme.of(context).colorScheme.outline,
      ),
      DevToolsConnectionState.error => (
        Icons.error_outline,
        controller.errorMessage ?? 'Unknown error.',
        Theme.of(context).colorScheme.error,
      ),
      DevToolsConnectionState.connected => (
        Icons.warning_amber,
        droppedCore > 0
            ? '$droppedCore event(s) evicted from the core ring buffer — '
                  'increase eventBufferSize if this matters to you.'
            : 'Resynchronizing after a detected inconsistency…',
        Theme.of(context).colorScheme.tertiary,
      ),
    };

    final bool canRetry =
        state == DevToolsConnectionState.error ||
        state == DevToolsConnectionState.incompatible ||
        state == DevToolsConnectionState.unavailable;

    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
            if (canRetry)
              TextButton(
                onPressed: controller.connect,
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
    });
  }
}
