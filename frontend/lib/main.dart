import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'config/app_config_notifier.dart';
import 'config/config_loader.dart';
import 'services/api_service.dart';
import 'services/backend_manager.dart';
import 'services/model_config_notifier.dart';
import 'services/model_config_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = await ConfigLoader.load();
  final modelConfigEntries = await ModelConfigStore.load();

  final backendManager = BackendManager();
  final backendNotifier = BackendNotifier(backendManager, config);

  // Kill the Python subprocess cleanly when the window is closed.
  WidgetsBinding.instance.addObserver(
    _LifecycleWatcher(backendManager),
  );

  final router = buildRouter(backendNotifier);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppConfigNotifier>.value(
          value: AppConfigNotifier(config),
        ),
        ChangeNotifierProvider<ModelConfigNotifier>.value(
          value: ModelConfigNotifier(modelConfigEntries),
        ),
        ChangeNotifierProvider<BackendNotifier>.value(value: backendNotifier),
        // Rebuilt whenever BackendNotifier changes (e.g. after a retry picks
        // a different port), so it always targets the live backend.
        ProxyProvider<BackendNotifier, ApiService>(
          update: (_, notifier, previous) =>
              ApiService(baseUrl: notifier.baseUrl),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: DiagnosticApp(router: router),
    ),
  );
}

// ── lifecycle observer ────────────────────────────────────────────────────────

class _LifecycleWatcher extends WidgetsBindingObserver {
  _LifecycleWatcher(this._manager);
  final BackendManager _manager;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _manager.stop();
    }
  }
}
