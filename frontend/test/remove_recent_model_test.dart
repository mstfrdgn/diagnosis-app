import 'dart:convert';
import 'dart:io';

import 'package:diagnostic_app/models/model_configuration.dart';
import 'package:diagnostic_app/services/model_config_notifier.dart';
import 'package:diagnostic_app/services/model_config_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Removing a recent model has to reach `model_configs.json`, not just the
/// in-memory list — otherwise the entry comes back on the next launch.
void main() {
  // These are plain `test`s rather than `testWidgets`, so the binding that
  // backs the path_provider mock has to be brought up by hand.
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('remove_recent_model');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  ModelConfigEntry entryFor(String path, {ModelConfiguration? configuration}) {
    final now = DateTime(2026, 9, 14, 12);
    return ModelConfigEntry(
      path: path,
      createdAt: now,
      lastOpened: now,
      configuration: configuration,
    );
  }

  Map<String, dynamic> readStoreFile() {
    final file = File(p.join(tempDir.path, ModelConfigStore.fileName));
    if (!file.existsSync()) return {};
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  test('remove drops the entry, persists, and notifies', () async {
    final notifier = ModelConfigNotifier({
      'a.pkcls': entryFor('a.pkcls'),
      'b.pkcls': entryFor('b.pkcls'),
    });
    var notified = 0;
    notifier.addListener(() => notified++);

    await notifier.remove('a.pkcls');

    expect(notifier.recentModels.map((e) => e.path), ['b.pkcls']);
    expect(notifier.entryFor('a.pkcls'), isNull);
    expect(notified, 1);
    expect(readStoreFile().keys, ['b.pkcls']);
  });

  test('removing the last entry leaves an empty store, not a stale one',
      () async {
    final notifier = ModelConfigNotifier({'only.pkcls': entryFor('only.pkcls')});

    await notifier.remove('only.pkcls');

    expect(notifier.recentModels, isEmpty);
    expect(readStoreFile(), isEmpty);
  });

  test('a removed model takes its saved configuration with it', () async {
    const config = ModelConfiguration(
      groups: ['Vitals'],
      variableGroups: {'temperature': 'Vitals'},
      variableRanges: {},
    );
    final notifier = ModelConfigNotifier({
      'a.pkcls': entryFor('a.pkcls', configuration: config),
    });

    await notifier.remove('a.pkcls');

    expect(notifier.configurationFor('a.pkcls'), isNull);
    // Reloading from disk is the check that matters: an entry that survives
    // here is one that reappears on the next launch.
    expect(await ModelConfigStore.load(), isEmpty);
  });

  test('removing an unknown path changes nothing and does not notify',
      () async {
    final notifier = ModelConfigNotifier({'a.pkcls': entryFor('a.pkcls')});
    var notified = 0;
    notifier.addListener(() => notified++);

    await notifier.remove('never-added.pkcls');

    expect(notifier.recentModels.map((e) => e.path), ['a.pkcls']);
    expect(notified, 0);
  });
}
