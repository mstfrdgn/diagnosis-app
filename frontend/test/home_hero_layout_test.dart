import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/config/app_config_notifier.dart';
import 'package:diagnostic_app/models/model_domain.dart';
import 'package:diagnostic_app/models/orange_variable.dart';
import 'package:diagnostic_app/screens/home_screen.dart';
import 'package:diagnostic_app/services/api_service.dart';
import 'package:diagnostic_app/services/backend_manager.dart';
import 'package:diagnostic_app/services/model_config_notifier.dart';
import 'package:diagnostic_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The hero puts the eyebrow beside the engine-status pill, and the primary
/// button beside its caption. Both pairs share a line while there is room and
/// wrap when there is not, so the width the window happens to be is what
/// decides the layout — which is exactly the kind of thing that silently
/// starts overflowing after an edit to the copy.
void main() {
  /// Every width the desktop app is plausibly used at. Phone-sized widths are
  /// left out: the app bar title does not fit there, and the app never runs
  /// that narrow.
  const widths = [1440.0, 1200.0, 900.0, 760.0, 620.0];

  Future<void> pumpHome(
    WidgetTester tester, {
    required double width,
    Brightness brightness = Brightness.light,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AppConfigNotifier(const AppConfig()),
          ),
          ChangeNotifierProvider(
            create: (_) => BackendNotifier(_FakeBackendManager(), const AppConfig()),
          ),
          ChangeNotifierProvider(create: (_) => ModelConfigNotifier({})),
          Provider<ApiService>.value(value: _StubApiService()),
        ],
        child: MaterialApp(
          theme: AppTheme.build(brightness),
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in widths) {
    testWidgets('the hero lays out without overflow at ${width.toInt()}px',
        (tester) async {
      await pumpHome(tester, width: width);

      // An overflowing Row, Column or Wrap reports a FlutterError rather than
      // failing a frame, so this is the assertion that catches it.
      expect(tester.takeException(), isNull);

      // The two elements that have to survive any reflow.
      expect(find.text('Open model (.pkcls)'), findsOneWidget);
      expect(find.text('Engine running'), findsOneWidget);
      expect(find.text('http://127.0.0.1:8765'), findsOneWidget);
    });
  }

  testWidgets('it lays out in dark mode too', (tester) async {
    await pumpHome(tester, width: 1200, brightness: Brightness.dark);

    expect(tester.takeException(), isNull);
    expect(find.text('Engine running'), findsOneWidget);
  });

  testWidgets('the eyebrow and status share the top line when wide',
      (tester) async {
    await pumpHome(tester, width: 1200);

    final eyebrow = tester.getRect(find.text('SELECT A MODEL'));
    final status = tester.getRect(find.text('Engine running'));

    expect(status.left, greaterThan(eyebrow.right));
    // Same run of the Wrap, so their centres line up vertically.
    expect((status.center.dy - eyebrow.center.dy).abs(), lessThan(2));
  });

  testWidgets('the status drops below the eyebrow when narrow', (tester) async {
    await pumpHome(tester, width: 620);

    final eyebrow = tester.getRect(find.text('SELECT A MODEL'));
    final status = tester.getRect(find.text('Engine running'));

    expect(status.top, greaterThan(eyebrow.bottom));
  });

  testWidgets('the decorative icon tile is gone', (tester) async {
    await pumpHome(tester, width: 1200);

    // It said nothing the headline did not; what is left in the hero is the
    // folder icon on the button.
    expect(find.byIcon(Icons.medical_services_outlined), findsNothing);
    expect(find.byIcon(Icons.folder_open_outlined), findsOneWidget);
  });
}

/// [BackendNotifier] starts its manager in its constructor; this one reports a
/// base URL and does nothing else, so no subprocess is launched.
class _FakeBackendManager extends BackendManager {
  @override
  String get baseUrl => 'http://127.0.0.1:8765';

  @override
  Future<void> start({
    required String host,
    required int port,
    required int startupTimeoutSeconds,
  }) async {}

  @override
  Future<void> stop() async {}
}

/// Never called: these tests only render the screen's initial state.
class _StubApiService extends ApiService {
  _StubApiService() : super(baseUrl: 'http://127.0.0.1:8765');

  @override
  Future<ModelDomain> loadModel(String path) async =>
      throw UnimplementedError();
}
