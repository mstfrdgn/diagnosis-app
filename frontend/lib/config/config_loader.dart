import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

import 'app_config.dart';

abstract final class ConfigLoader {
  static const _fileName = 'app_config.yaml';
  static const _assetPath = 'assets/config/$_fileName';

  /// Load config using this resolution order:
  ///   1. {appDocumentsDir}/app_config.yaml  – user-edited copy
  ///   2. Bundled assets/config/app_config.yaml – shipped default
  /// On first launch the bundled file is copied to the documents dir so the
  /// user can edit it without recompiling.
  /// Any parse error falls back to [AppConfig.defaults] silently.
  static Future<AppConfig> load() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final userFile = File(p.join(appDir.path, _fileName));

      if (!userFile.existsSync()) {
        final bundled = await rootBundle.loadString(_assetPath);
        await userFile.writeAsString(bundled);
      }

      final content = await userFile.readAsString();
      final yaml = loadYaml(content);
      if (yaml is Map) return AppConfig.fromYaml(yaml);
    } catch (e) {
      debugPrint('ConfigLoader: failed to load config ($e), using defaults.');
    }
    return AppConfig.defaults;
  }
}
