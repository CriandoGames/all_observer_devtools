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
  late final VmServiceAdapter _adapter;
  late final ConnectionController _controller;

  @override
  void initState() {
    super.initState();
    _adapter = VmServiceAdapter();
    _controller = ConnectionController(
      client: _adapter.buildProtocolClient(),
      liveEvents: _adapter.liveEvents,
    );
    _controller.connect();
  }

  @override
  void dispose() {
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
