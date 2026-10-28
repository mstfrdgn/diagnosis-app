import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/config/app_config_notifier.dart';
import 'package:diagnostic_app/models/model_configuration.dart';
import 'package:diagnostic_app/models/model_domain.dart';
import 'package:diagnostic_app/models/orange_variable.dart';
import 'package:diagnostic_app/screens/home_screen.dart';
import 'package:diagnostic_app/screens/sessions_screen.dart';
import 'package:diagnostic_app/services/api_service.dart';
import 'package:diagnostic_app/services/backend_manager.dart';
import 'package:diagnostic_app/services/model_config_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// "View Sessions" is the one exit from the configured-model dialog that is
/// not a way into the prediction flow: it reads the log off disk from the
/// model's path alone. What is worth pinning down is that it reaches
/// /sessions with that path and leaves the backend entirely alone — loading a
/// model there is the slow part, and this route has no need of it.
void main() {
  /// Stands in for the real manager so [BackendNotifier] can reach `ready`
  /// without launching a Python subprocess.
  final backend = BackendNotifier(_FakeBackendManager(), const AppConfig());

  final configuration = const ModelConfiguration(
    groups: ['Vitals'],
    variableGroups: {'temperature': 'Vitals'},
    variableRanges: {},
  );

  ModelConfigNotifier notifierWith({ModelConfiguration? configuration}) {
    final now = DateTime(2026, 9, 14, 12);
    return ModelConfigNotifier({
      'model.pkcls': ModelConfigEntry(
        path: 'model.pkcls',
        createdAt: now,
        lastOpened: now,
        configuration: configuration,
      ),
    });
  }

  /// Records what the /sessions route was handed, so the test can assert on
  /// the path without rendering the real log screen.
  SessionsScreenArgs? pushedArgs;

  setUp(() => pushedArgs = null);

  late Directory tempDir;

  setUp(() {
    // Loading a model records it in model_configs.json; point that at a
    // throwaway directory rather than the real documents folder.
    tempDir = Directory.systemTemp.createTempSync('view_sessions_action');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  GoRouter buildTestRouter() => GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/sessions',
            builder: (_, state) {
              pushedArgs = state.extra as SessionsScreenArgs?;
              return const Scaffold(body: Text('SESSIONS SCREEN'));
            },
          ),
          GoRoute(
            path: '/configuration',
            builder: (_, __) => const Scaffold(body: Text('WIZARD')),
          ),
          GoRoute(
            path: '/input',
            builder: (_, __) => const Scaffold(body: Text('INPUT SCREEN')),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const Scaffold(body: Text('SETTINGS')),
          ),
        ],
      );

  Future<_RecordingApiService> pumpHome(
    WidgetTester tester,
    GoRouter router, {
    ModelConfiguration? configuration,
  }) async {
    // The hero panel fills the default 800x600 viewport on its own, which
    // would leave the recent-model tile off screen and unhittable.
    await tester.binding.setSurfaceSize(const Size(1200, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _RecordingApiService();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppConfigNotifier(const AppConfig())),
          ChangeNotifierProvider.value(value: backend),
          ChangeNotifierProvider(
            create: (_) => notifierWith(configuration: configuration),
          ),
          Provider<ApiService>.value(value: api),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  // Found by icon: TextButton.icon does not put a TextButton ancestor above
  // its label in this Flutter version.
  final viewSessions = find.byIcon(Icons.history_outlined);
  final recentTile = find.byType(ListTile);

  testWidgets('the dialog offers View Sessions alongside the other two',
      (tester) async {
    await pumpHome(tester, buildTestRouter(), configuration: configuration);

    await tester.tap(recentTile);
    await tester.pumpAndSettle();

    expect(find.text('View Sessions'), findsOneWidget);
    expect(find.text('Reconfigure'), findsOneWidget);
    expect(find.text('Start Diagnosis'), findsOneWidget);
  });

  testWidgets('View Sessions goes to /sessions with the model path',
      (tester) async {
    await pumpHome(tester, buildTestRouter(), configuration: configuration);

    await tester.tap(recentTile);
    await tester.pumpAndSettle();
    await tester.tap(viewSessions);
    await tester.pumpAndSettle();

    expect(find.text('SESSIONS SCREEN'), findsOneWidget);
    expect(pushedArgs?.modelPath, 'model.pkcls');
  });

  testWidgets('View Sessions never loads the model on the backend',
      (tester) async {
    final api = await pumpHome(
      tester,
      buildTestRouter(),
      configuration: configuration,
    );

    await tester.tap(recentTile);
    await tester.pumpAndSettle();
    await tester.tap(viewSessions);
    await tester.pumpAndSettle();

    expect(api.loadedPaths, isEmpty);
    // A failed load would have put the error banner up instead.
    expect(find.text('Could not load that model'), findsNothing);
  });

  testWidgets('it pushes, so the home screen is still underneath',
      (tester) async {
    final router = buildTestRouter();
    await pumpHome(tester, router, configuration: configuration);

    await tester.tap(recentTile);
    await tester.pumpAndSettle();
    await tester.tap(viewSessions);
    await tester.pumpAndSettle();

    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('Recent models'), findsOneWidget);
  });

  testWidgets('an unconfigured model still skips the dialog entirely',
      (tester) async {
    final api = await pumpHome(tester, buildTestRouter());

    await tester.tap(recentTile);
    // A single frame, not pumpAndSettle: the load is already under way and
    // its "Loading model…" spinner never settles.
    await tester.pump();

    // No dialog to choose from: the only thing to do with an unconfigured
    // model is configure it, and that does need the model loaded.
    expect(find.text('View Sessions'), findsNothing);
    expect(api.loadedPaths, ['model.pkcls']);
  });
}

/// [BackendNotifier] starts its manager in its constructor; this one reports
/// a base URL and does nothing else, so no subprocess is launched.
class _FakeBackendManager extends BackendManager {
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

/// Records every [loadModel] call so a test can assert the backend was left
/// alone. The domain it returns is the smallest one the home screen accepts.
class _RecordingApiService extends ApiService {
  _RecordingApiService() : super(baseUrl: 'http://127.0.0.1:8765');

  final loadedPaths = <String>[];

  @override
  Future<ModelDomain> loadModel(String path) async {
    loadedPaths.add(path);
    return const ModelDomain(features: [], classVar: _classVar);
  }

  static const _classVar = OrangeVariable(
    name: 'diagnosis',
    type: VariableType.discrete,
    role: VariableRole.classVar,
    values: ['Negative', 'Positive'],
  );
}
