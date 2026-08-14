import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/config/app_config_notifier.dart';
import 'package:diagnostic_app/screens/settings_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// A Scrollbar with no controller falls back to the PrimaryScrollController,
/// which desktop platforms do not attach — so it finds no scroll position and
/// asserts the moment the user drags. The assertion only fires on a real
/// scroll, which is why this drives one.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('scrollbar_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  testWidgets('scrolling the settings screen does not assert', (tester) async {
    // On mobile the PrimaryScrollController is inherited automatically and
    // both widgets happen to agree, so the bug is invisible under
    // flutter_test's default (Android) platform. This app ships on desktop,
    // where it is not inherited. The override has to be undone inside the
    // test body — the framework checks for leaked debug vars before tearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      // Small enough that the content is guaranteed to overflow and scroll.
      tester.view.physicalSize = const Size(700, 500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => AppConfigNotifier(AppConfig.defaults),
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -250),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
