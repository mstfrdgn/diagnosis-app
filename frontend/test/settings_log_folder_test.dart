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

/// On macOS app.log and backend.log sit under ~/Library/Application Support,
/// which Finder hides, so the Settings button is how users reach them. It has
/// to open the same folder the backend manager writes to, not the CSV folder
/// next to it.
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
    tempDir = Directory.systemTemp.createTempSync('settings_log_folder');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  testWidgets('Open log folder opens the folder holding app.log',
      (tester) async {
    final logDir = p.join(tempDir.path, 'logs');
    final opened = <String>[];
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
            ),
          ),
        ),
      );
      // The paths are looked up on real disk, outside the fake clock.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text(logDir), findsOneWidget);

    final button = find.widgetWithText(OutlinedButton, 'Open log folder');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(opened, [logDir]);
    expect(find.text('Opened $logDir.'), findsOneWidget);
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
