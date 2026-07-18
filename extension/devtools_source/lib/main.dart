import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';

import 'src/app/all_observer_devtools_app.dart';

void main() {
  runApp(const AllObserverDevToolsExtensionRoot());
}

/// Root widget required by the `devtools_extensions` framework. Everything
/// below [DevToolsExtension] can access the `serviceManager`,
/// `extensionManager`, and `dtdManager` globals it initializes.
class AllObserverDevToolsExtensionRoot extends StatelessWidget {
  const AllObserverDevToolsExtensionRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(child: AllObserverDevToolsApp());
  }
}
