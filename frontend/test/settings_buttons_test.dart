import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/config/app_config_notifier.dart';
import 'package:diagnostic_app/screens/settings_screen.dart';
import 'package:diagnostic_app/services/backend_manager.dart';
import 'package:diagnostic_app/services/startup_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// The Settings buttons that hand a path to the OS. On macOS app.log and
/// backend.log sit under ~/Library/Application Support, which Finder hides,
/// so the "Open log folder" button is how users reach them; it has to open
/// the folder the backend manager writes to, not the CSV folder next to it.
/// Each button reports back in its own card, not in whichever card happens
/// to come first.
void main() {
  late Directory tempDir;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'diagnostic_app',
      packageName: 'com.diagnostic.diagnosticApp',
      version: '1.1.0',
      buildNumber: '',
      buildSignature: '',
    );
    tempDir = Directory.systemTemp.createTempSync('settings_buttons');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Every path handed to the OS, in order, by either seam.
  late List<String> opened;

  Future<void> pumpSettings(WidgetTester tester) async {
    opened = [];
    final backend = BackendNotifier(
      _FakeBackendManager(StartupLog(baseDirectory: () async => tempDir)),
      const AppConfig(),
    );
    addTearDown(backend.dispose);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(
                create: (_) => AppConfigNotifier(AppConfig.defaults)),
            ChangeNotifierProvider<BackendNotifier?>.value(value: backend),
          ],
          child: MaterialApp(
            home: SettingsScreen(
              openFolder: (path) async => opened.add(path),
              openInEditor: (path) async => opened.add(path),
            ),
          ),
        ),
      );
      // The paths are looked up on real disk, outside the fake clock.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  /// Taps [label] for real: the CSV button creates its folder on disk first.
  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.ancestor(
      of: find.text(label),
      matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
    );
    await tester.ensureVisible(button);
    await tester.runAsync(() async {
      await tester.tap(button);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
  }

  /// The card whose heading is [title].
  Finder card(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(Card));

  testWidgets('Open log folder opens the folder holding app.log',
      (tester) async {
    await pumpSettings(tester);
    final logDir = p.join(tempDir.path, 'logs');
    expect(find.text(logDir), findsOneWidget);

    await tapButton(tester, 'Open log folder');

    expect(opened, [logDir]);
  });

  testWidgets('each button reports back in its own card only', (tester) async {
    await pumpSettings(tester);

    const cards = ['app_config.yaml', 'CSV folder', 'Log folder'];
    const buttons = {
      'app_config.yaml': 'Open in editor',
      'CSV folder': 'Open folder',
      'Log folder': 'Open log folder',
    };

    for (final title in cards) {
      await tapButton(tester, buttons[title]!);
      final message = title == 'app_config.yaml'
          ? 'Opened ${opened.last} in the default editor.'
          : 'Opened ${opened.last}.';

      for (final other in cards) {
        expect(
          find.descendant(of: card(other), matching: find.text(message)),
          other == title ? findsOneWidget : findsNothing,
          reason: '"${buttons[title]}" message in the $other card',
        );
      }
    }
  });
}

/// [BackendNotifier] starts its manager in its constructor; this one does
/// nothing, so no subprocess is launched, but keeps the real [StartupLog].
class _FakeBackendManager extends BackendManager {
  _FakeBackendManager(StartupLog log) : super(log: log);

  @override
  String get baseUrl => 'http://127.0.0.1:8765';

  @override
  Future<void> start({
    required String host,
    int? port,
    required int startupTimeoutSeconds,
  }) async {}

  @override
  Future<void> stop() async {}
}
