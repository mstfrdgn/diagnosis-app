import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_config.dart';
import 'config_loader.dart';

/// Wraps the current [AppConfig] in a [ChangeNotifier] so widgets can
/// `watch` it and rebuild when the settings screen reloads the YAML file.
class AppConfigNotifier extends ChangeNotifier {
  AppConfigNotifier(this._config);

  AppConfig _config;
  AppConfig get config => _config;

  /// Absolute path to the user-editable `app_config.yaml`.
  Future<String> configFilePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return p.join(appDir.path, ConfigLoader.fileName);
  }

  /// Re-reads `app_config.yaml` from disk and notifies listeners.
  Future<void> reload() async {
    _config = await ConfigLoader.load();
    notifyListeners();
  }
}
