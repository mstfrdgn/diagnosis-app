import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/config/app_config_notifier.dart';
import 'package:diagnostic_app/screens/sessions_screen.dart';
import 'package:diagnostic_app/services/api_service.dart';
import 'package:diagnostic_app/services/batch_run_log.dart';
import 'package:diagnostic_app/services/model_config_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// A batch run is one entry on the Sessions screen, held to the same date
/// filters as the sessions around it, and its predictions are one tap away.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('sessions_screen_batch');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  String stamp(DateTime at) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  /// One session and one batch run today, and one of each long ago.
  Future<void> writeLogs() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 0, 0, 1);
    final longAgo = today.subtract(const Duration(days: 40));

    File(p.join(tempDir.path, 'iris_sessions.csv')).writeAsStringSync(
      'timestamp,age,predicted_class,prob_0,prob_1\r\n'
      '${stamp(today)},41,1,0.20,0.80\r\n'
      '${stamp(longAgo)},30,0,0.70,0.30\r\n',
    );

    const result = 'age,predicted_class,prob_neg,prob_pos\r\n'
        '41,pos,0.18,0.82\r\n'
        '7,neg,0.91,0.09\r\n'
        '55,pos,0.30,0.70\r\n';
    final todayRun = BatchRunLog.resultFileNameFor('iris', today);
    File(p.join(tempDir.path, todayRun)).writeAsStringSync(result);
    File(p.join(tempDir.path, BatchRunLog.resultFileNameFor('iris', longAgo)))
        .writeAsStringSync(result);
    await const BatchRunLog().append(
      Directory(tempDir.path),
      'iris',
      BatchRunRecord(
        timestamp: today,
        inputFileName: 'ward_cases.xlsx',
        rowCount: 3,
        failureCount: 0,
        resultFileName: todayRun,
      ),
    );
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AppConfigNotifier(const AppConfig()),
          ),
          ChangeNotifierProvider(create: (_) => ModelConfigNotifier(const {})),
          Provider(create: (_) => ApiService(baseUrl: 'http://localhost:1')),
        ],
        child: const MaterialApp(
          home: SessionsScreen(
            initialArgs: SessionsScreenArgs(modelPath: 'iris.pkcls'),
          ),
        ),
      ),
    );
    await settleIo(tester);
  }

  testWidgets('filters treat batch runs like sessions', (tester) async {
    await tester.runAsync(writeLogs);
    await pumpScreen(tester);

    expect(find.text('1 session · 1 batch run (of 4 entries)'), findsOneWidget);
    expect(find.text('Batch'), findsOneWidget);
    expect(find.textContaining('ward_cases.xlsx · 3 rows'), findsOneWidget);

    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    expect(find.text('Batch'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('2 sessions · 2 batch runs'), findsOneWidget);
    expect(find.text('Batch'), findsNWidgets(2));
    expect(find.textContaining('Input file unknown · 3 rows'), findsOneWidget);
  });

  testWidgets('expanding a batch run shows its predictions', (tester) async {
    await tester.runAsync(writeLogs);
    await pumpScreen(tester);

    await tester.tap(find.textContaining('ward_cases.xlsx'));
    await settleIo(tester);

    expect(find.text('Batch result file'), findsOneWidget);
    expect(find.text('pos: 2 · neg: 1'), findsOneWidget);
    expect(find.text('Predicted class'), findsNWidgets(2));
    expect(find.text('neg'), findsOneWidget);
  });

  testWidgets('batch rows line up under the list header', (tester) async {
    await tester.runAsync(writeLogs);
    await pumpScreen(tester);
    await tester.tap(find.textContaining('ward_cases.xlsx'));
    await settleIo(tester);

    double left(Finder finder) => tester.getTopLeft(finder).dx;

    // Header first, table second in tree order.
    final predicted = find.text('Predicted class');
    final confidence = find.text('Confidence');
    expect(left(predicted.at(1)), left(predicted.at(0)));
    expect(left(confidence.at(1)), left(confidence.at(0)));
    expect(left(find.text('neg')), left(predicted.at(0)));
    // The session above predicted class "1" too; the row number comes last.
    expect(left(find.text('1').last), left(find.text('Timestamp')));
  });
}

/// Lets real file I/O finish, pumping frames in between, until no progress
/// indicator is left. pumpAndSettle cannot do this on its own: the spinner
/// never stops animating while the read is pending, and the read itself
/// only completes outside the fake clock.
Future<void> settleIo(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Timed out waiting for the log to load.');
}
