import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/config/app_config_notifier.dart';
import 'package:diagnostic_app/models/model_domain.dart';
import 'package:diagnostic_app/models/orange_variable.dart';
import 'package:diagnostic_app/models/prediction_result.dart';
import 'package:diagnostic_app/screens/result_screen.dart';
import 'package:diagnostic_app/services/model_config_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The result screen's other exits (the back arrow, both "New patient"
/// buttons) pop to the input screen and keep the current model loaded. The
/// Home button is the only way back to pick a different model, so what is
/// worth pinning down is that it reaches /home and does not simply uncover
/// the input screen underneath.
void main() {
  late Directory tempDir;

  setUp(() {
    // The screen logs a session to CSV on its first frame; point that at a
    // throwaway directory rather than the real documents folder.
    tempDir = Directory.systemTemp.createTempSync('result_home_button');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  final domain = const ModelDomain(
    features: [
      OrangeVariable(
        name: 'temperature',
        type: VariableType.continuous,
        role: VariableRole.feature,
      ),
    ],
    classVar: OrangeVariable(
      name: 'diagnosis',
      type: VariableType.discrete,
      role: VariableRole.classVar,
      values: ['Negative', 'Positive'],
    ),
  );

  final args = ResultScreenArgs(
    domain: domain,
    result: PredictionResult(
      predictedClass: 'Positive',
      probabilities: const {'Negative': 0.1, 'Positive': 0.9},
      timestamp: DateTime(2026, 9, 14, 12, 30),
    ),
    inputs: const {'temperature': 39.2},
    modelPath: 'model.pkcls',
  );

  /// Routes shaped like the real ones. Tests start at /input and push
  /// /result on top, so the stack matches what the user actually has when
  /// they reach this screen.
  GoRouter buildTestRouter() => GoRouter(
        initialLocation: '/input',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const Scaffold(body: Text('HOME SCREEN')),
          ),
          GoRoute(
            path: '/input',
            builder: (_, __) => const Scaffold(body: Text('INPUT SCREEN')),
          ),
          GoRoute(
            path: '/result',
            builder: (_, __) => ResultScreen(args: args),
          ),
        ],
      );

  /// Pumps the app at /input, then pushes /result — leaving the input screen
  /// underneath, which is what makes "did Home clear the stack?" meaningful.
  Future<void> pumpResultScreen(WidgetTester tester, GoRouter router) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            // Evaluation dialog off: it opens on the first frame and would
            // sit in front of the AppBar this test is driving. CSV logging
            // off so the run touches no files at all.
            create: (_) => AppConfigNotifier(
              const AppConfig(
                evaluationDialogEnabled: false,
                csvLoggingEnabled: false,
              ),
            ),
          ),
          ChangeNotifierProvider(create: (_) => ModelConfigNotifier({})),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/result');
    await tester.pumpAndSettle();
  }

  // Found by icon rather than by label: TextButton.icon does not put a
  // TextButton ancestor above its label in this Flutter version.
  final homeButton = find.byIcon(Icons.home_outlined);
  final newPatientInAppBar = find.byIcon(Icons.person_add_alt);

  testWidgets('the Home button navigates to the home screen', (tester) async {
    final router = buildTestRouter();
    await pumpResultScreen(tester, router);

    expect(find.text('Prediction result'), findsOneWidget);
    expect(homeButton, findsOneWidget);
    expect(find.text('Home'), findsOneWidget);

    await tester.tap(homeButton);
    await tester.pumpAndSettle();

    expect(find.text('HOME SCREEN'), findsOneWidget);
    expect(find.text('Prediction result'), findsNothing);
  });

  testWidgets('Home replaces the stack rather than uncovering input',
      (tester) async {
    final router = buildTestRouter();
    await pumpResultScreen(tester, router);

    await tester.tap(homeButton);
    await tester.pumpAndSettle();

    // Nothing left to pop back to: had this been a pop, the input screen
    // would still be underneath — exactly what this button exists to avoid.
    expect(router.canPop(), isFalse);
    expect(find.text('INPUT SCREEN'), findsNothing);
  });

  testWidgets('New patient still pops to the input screen', (tester) async {
    final router = buildTestRouter();
    await pumpResultScreen(tester, router);

    await tester.tap(newPatientInAppBar);
    await tester.pumpAndSettle();

    expect(find.text('INPUT SCREEN'), findsOneWidget);
    expect(find.text('HOME SCREEN'), findsNothing);
  });
}
