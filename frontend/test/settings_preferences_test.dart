import 'dart:io';

import 'package:diagnostic_app/app.dart';
import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/config/app_config_notifier.dart';
import 'package:diagnostic_app/config/config_loader.dart';
import 'package:diagnostic_app/config/preference.dart';
import 'package:diagnostic_app/screens/settings_screen.dart';
import 'package:diagnostic_app/services/backend_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:yaml/yaml.dart';

/// The Preferences section: every control writes its key to the user's
/// app_config.yaml and changes the running config without a restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late File configFile;
  late AppConfigNotifier notifier;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'diagnostic_app',
      packageName: 'com.diagnostic.diagnosticApp',
      version: '1.2.0',
      buildNumber: '',
      buildSignature: '',
    );
    tempDir = Directory.systemTemp.createTempSync('settings_preferences');
    configFile = File(p.join(tempDir.path, 'app_config.yaml'));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<void> pumpSettings(WidgetTester tester, String yaml) async {
    configFile.writeAsStringSync(yaml);
    await tester.runAsync(() async {
      notifier = AppConfigNotifier(await ConfigLoader.load());
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const SettingsScreen()),
        ],
      );
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: notifier),
            ChangeNotifierProvider<BackendNotifier?>.value(value: null),
          ],
          child: DiagnosticApp(router: router),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  /// Taps for real: the file is written before the control moves.
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
  }

  Finder switchFor(String title) => find.ancestor(
        of: find.text(title),
        matching: find.byType(SwitchListTile),
      );

  Object? stored(Preference preference) =>
      (loadYaml(configFile.readAsStringSync()) as Map)[preference.section]
          [preference.key];

  final oldConfig =
      File('test/fixtures/app_config_1.0.0.yaml').readAsStringSync();

  testWidgets('each switch writes its key and takes effect at once',
      (tester) async {
    await pumpSettings(tester, oldConfig);

    final switches = <String, (Preference, bool Function(AppConfig))>{
      'Show probabilities': (
        Preference.showProbability,
        (c) => c.resultDisplayShowProbability,
      ),
      'Evaluation dialog': (
        Preference.evaluationEnabled,
        (c) => c.evaluationDialogEnabled,
      ),
      'Add an “Uncertain” option': (
        Preference.includeUncertainOption,
        (c) => c.evaluationDialogIncludeUncertainOption,
      ),
      'CSV logging': (
        Preference.csvLoggingEnabled,
        (c) => c.csvLoggingEnabled,
      ),
      'Show range hints': (Preference.showRangeHints, (c) => c.showRangeHints),
    };
    for (final MapEntry(key: title, value: (preference, read))
        in switches.entries) {
      for (final expected in [false, true]) {
        await tap(tester, switchFor(title));
        expect(stored(preference), expected, reason: title);
        expect(read(notifier.config), expected, reason: title);
        expect(
          tester.widget<SwitchListTile>(switchFor(title)).value,
          expected,
          reason: title,
        );
      }
    }
    expect(configFile.readAsStringSync(), contains('# Port FastAPI listens on'));
    expect(File('${configFile.path}.tmp').existsSync(), isFalse);
  });

  testWidgets('the theme and format change with the app running',
      (tester) async {
    await pumpSettings(tester, oldConfig);
    Brightness brightness() =>
        Theme.of(tester.element(find.text('Preferences'))).brightness;
    expect(brightness(), Brightness.light);

    await tap(tester, find.text('Dark'));
    expect(brightness(), Brightness.dark);
    expect(stored(Preference.theme), 'dark');

    await tap(tester, find.text('Decimal'));
    expect(stored(Preference.probabilityFormat), 'decimal');
    expect(notifier.config.resultDisplayProbabilityFormat, 'decimal');
    expect(notifier.config.appTheme, 'dark');
  });

  testWidgets('a broken file is reported and left as it is', (tester) async {
    const broken = 'app:\n  theme: [light\n';
    await pumpSettings(tester, broken);

    await tap(tester, switchFor('Show range hints'));

    expect(find.textContaining('Not saved'), findsOneWidget);
    expect(configFile.readAsStringSync(), broken);
    expect(notifier.config.showRangeHints, isTrue);
  });

  testWidgets('says so when auto_open_after_result keeps the dialog away',
      (tester) async {
    await pumpSettings(
        tester, 'evaluation_dialog:\n  auto_open_after_result: false\n');
    expect(
        find.textContaining('auto_open_after_result is off'), findsOneWidget);
  });

  test('saves in quick succession all end up in the file', () async {
    configFile.writeAsStringSync(oldConfig);
    final notifier = AppConfigNotifier(await ConfigLoader.load());
    await Future.wait([
      notifier.setPreference(Preference.theme, 'dark'),
      notifier.setPreference(Preference.showRangeHints, false),
      notifier.setPreference(Preference.csvLoggingEnabled, false),
    ]);
    expect(stored(Preference.theme), 'dark');
    expect(stored(Preference.showRangeHints), false);
    expect(stored(Preference.csvLoggingEnabled), false);
  });

  test('keeps what was edited in the file since it was loaded', () async {
    configFile.writeAsStringSync('app:\n  theme: light\n');
    final notifier = AppConfigNotifier(await ConfigLoader.load());
    configFile.writeAsStringSync('app:\n  theme: light\n  title: Mine\n');
    await notifier.setPreference(Preference.theme, 'dark');
    expect(notifier.config.appTitle, 'Mine');
    expect(configFile.readAsStringSync(), 'app:\n  theme: dark\n  title: Mine\n');
  });
}
