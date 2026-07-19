import 'dart:async';

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import '../connection/connection_controller.dart';
import '../connection/vm_service_adapter.dart';
import '../screens/dependencies/dependencies_screen.dart';
import '../screens/nodes/nodes_screen.dart';
import '../screens/overview/overview_screen.dart';
import '../screens/scopes/scopes_screen.dart';
import '../screens/timeline/timeline_screen.dart';
import '../screens/warnings/warnings_screen.dart';
import 'connection_banner.dart';

/// Root content widget, mounted as the `child` of `DevToolsExtension` in
/// `main.dart`. Owns the [VmServiceAdapter]/[ConnectionController] for the
/// whole extension lifetime. Reactivity is per-screen: [ConnectionBanner]
/// and every screen below wrap their own `build()` in an `all_observer`
/// `Observer`, so this widget's own `build()` is plain, non-reactive
/// scaffolding — no top-level listener wiring needed here.
class AllObserverDevToolsApp extends StatefulWidget {
  const AllObserverDevToolsApp({super.key});

  @override
  State<AllObserverDevToolsApp> createState() => _AllObserverDevToolsAppState();
}

class _AllObserverDevToolsAppState extends State<AllObserverDevToolsApp> {
  late VmServiceAdapter _adapter;
  late ConnectionController _controller;
  Object? _serviceIdentity;
  String? _selectedIsolateId;
  bool _serviceConnected = false;

  @override
  void initState() {
    super.initState();
    _serviceIdentity = serviceManager.service;
    _selectedIsolateId =
        serviceManager.isolateManager.selectedIsolate.value?.id;
    _serviceConnected = serviceManager.connectedState.value.connected;
    _adapter = VmServiceAdapter();
    _controller = ConnectionController(
      client: _adapter.buildProtocolClient(),
      liveEvents: _adapter.liveEvents,
    );
    serviceManager.connectedState.addListener(_handleDevToolsTargetChanged);
    serviceManager.isolateManager.selectedIsolate.addListener(
      _handleDevToolsTargetChanged,
    );
    _connectIfReady();
  }

  void _connectIfReady() {
    if (_serviceConnected && _selectedIsolateId != null) {
      unawaited(_controller.connect());
    }
  }

  /// A controller/client/stream binding is immutable for one selected
  /// isolate. Replace the whole binding on disconnect, reconnect, isolate
  /// selection, or hot restart so an in-flight handshake cannot cross those
  /// boundaries.
  void _handleDevToolsTargetChanged() {
    if (!mounted) return;
    final Object? nextService = serviceManager.service;
    final String? nextIsolateId =
        serviceManager.isolateManager.selectedIsolate.value?.id;
    final bool nextConnected = serviceManager.connectedState.value.connected;
    if (identical(nextService, _serviceIdentity) &&
        nextIsolateId == _selectedIsolateId &&
        nextConnected == _serviceConnected) {
      return;
    }

    final VmServiceAdapter oldAdapter = _adapter;
    final ConnectionController oldController = _controller;
    final VmServiceAdapter nextAdapter = VmServiceAdapter();
    final ConnectionController nextController = ConnectionController(
      client: nextAdapter.buildProtocolClient(),
      liveEvents: nextAdapter.liveEvents,
    );

    setState(() {
      _serviceIdentity = nextService;
      _selectedIsolateId = nextIsolateId;
      _serviceConnected = nextConnected;
      _adapter = nextAdapter;
      _controller = nextController;
    });
    oldController.dispose();
    oldAdapter.dispose();
    _connectIfReady();
  }

  @override
  void dispose() {
    serviceManager.connectedState.removeListener(_handleDevToolsTargetChanged);
    serviceManager.isolateManager.selectedIsolate.removeListener(
      _handleDevToolsTargetChanged,
    );
    _controller.dispose();
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('all_observer'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Nodes'),
              Tab(text: 'Timeline'),
              Tab(text: 'Dependencies'),
              Tab(text: 'Scopes'),
              Tab(text: 'Warnings'),
            ],
          ),
        ),
        body: Column(
          children: [
            ConnectionBanner(controller: _controller),
            Expanded(
              child: TabBarView(
                children: [
                  OverviewScreen(controller: _controller),
                  NodesScreen(store: _controller.store),
                  TimelineScreen(store: _controller.store),
                  DependenciesScreen(store: _controller.store),
                  ScopesScreen(store: _controller.store),
                  WarningsScreen(store: _controller.store),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
