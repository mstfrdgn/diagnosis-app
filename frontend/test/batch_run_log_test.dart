import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/models/logged_session.dart';
import 'package:diagnostic_app/services/batch_prediction_service.dart';
import 'package:diagnostic_app/services/batch_run_log.dart';
import 'package:diagnostic_app/services/session_log_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Batch runs reach the Sessions screen through their result files, with the
/// index filling in what a result file cannot say about itself. What matters
/// is that each run is found exactly once, under the right model, whether or
/// not the index knows about it — and that the session log beside it reads
/// exactly as it did before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const log = BatchRunLog();
  const config = AppConfig();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('batch_run_log');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  const resultCsv = 'age,fever,predicted_class,prob_neg,prob_pos,'
      'doctor_diagnosis,notes\r\n'
      '41,yes,pos,0.18,0.82,,\r\n'
      '7,no,neg,0.91,0.09,,\r\n'
      '30,no,,,,,\r\n'
      '55,yes,pos,0.30,0.70,,\r\n';

  void writeFile(String name, String contents) =>
      File(p.join(tempDir.path, name)).writeAsStringSync(contents);

  group('BatchRunLog file names', () {
    test('round-trips the model slug and run time', () {
      final at = DateTime(2026, 8, 14, 9, 5, 3);
      final name = BatchRunLog.resultFileNameFor('dengue_orange', at);
      expect(name, 'dengue_orange_batch_20260814_090503.csv');
      expect(BatchRunLog.parseResultFileName(name), ('dengue_orange', at));
    });

    test('matches what BatchPredictionService has always written', () {
      final name = BatchPredictionService.outputFileNameFor(
        r'C:\models\Dengue orange.pkcls',
        DateTime(2026, 8, 14, 9, 5, 3),
      );
      expect(BatchRunLog.isResultFileName(name), isTrue);
    });

    test('keeps a slug that itself contains _batch_ whole', () {
      expect(
        BatchRunLog.parseResultFileName('a_batch_b_batch_20260101_101010.csv')
            ?.$1,
        'a_batch_b',
      );
    });

    test('rejects names that are not result files', () {
      for (final name in [
        'iris_sessions.csv',
        'iris_batch_runs.csv',
        'iris_batch_2026_101010.csv',
        'iris_batch_20261301_101010.csv',
        'iris_batch_20260101_101010.xlsx',
      ]) {
        expect(BatchRunLog.isResultFileName(name), isFalse, reason: name);
      }
    });
  });

  group('BatchRunLog.parseResult', () {
    final result = log.parseResult(resultCsv, path: 'r.csv');

    test('reads predictions, probabilities and inputs', () {
      expect(result.succeeded, isTrue);
      expect(result.rows, hasLength(4));
      expect(result.rows.first.predictedClass, 'pos');
      expect(result.rows.first.probabilities, {'neg': 0.18, 'pos': 0.82});
      expect(result.rows.first.confidence, 0.82);
      expect(result.rows.first.inputs, {'age': '41', 'fever': 'yes'});
    });

    test('counts failures and classes, most frequent first', () {
      expect(result.failureCount, 1);
      expect(result.rows[2].failed, isTrue);
      expect(
        result.classCounts.map((e) => (e.key, e.value)),
        [('pos', 2), ('neg', 1)],
      );
    });

    test('takes the last predicted_class when a result was re-run', () {
      final rerun = log.parseResult(
        'age,predicted_class,prob_a,predicted_class,prob_a\r\n'
        '41,old,0.10,new,0.90\r\n',
        path: 'r.csv',
      );
      final row = rerun.rows.single;
      expect(row.predictedClass, 'new');
      expect(row.probabilities, {'a': 0.90});
    });

    test('a file without predictions is reported, not guessed at', () {
      expect(
          log.parseResult('a,b\r\n1,2\r\n', path: 'r.csv').succeeded, isFalse);
    });
  });

  group('BatchRunLog.loadRuns', () {
    Directory directory() => Directory(tempDir.path);

    test('fills in the input file from the index', () async {
      final at = DateTime(2026, 9, 14, 10, 30);
      final name = BatchRunLog.resultFileNameFor('iris', at);
      writeFile(name, resultCsv);
      await log.append(
        directory(),
        'iris',
        BatchRunRecord(
          timestamp: at,
          inputFileName: 'ward 3, cases.xlsx',
          rowCount: 4,
          failureCount: 1,
          resultFileName: name,
        ),
      );

      final run =
          (await log.loadRuns(directory(), 'iris', config: config)).single;
      expect(run.timestamp, at);
      expect(run.rawTimestamp, '2026-09-14 10:30:00');
      expect(run.inputFileName, 'ward 3, cases.xlsx');
      expect(run.rowCount, 4);
      expect(run.failureCount, 1);
      expect(run.resultPath, p.join(tempDir.path, name));
    });

    test('a result file the index does not know is counted from disk',
        () async {
      writeFile('iris_batch_20260101_080000.csv', resultCsv);

      final run =
          (await log.loadRuns(directory(), 'iris', config: config)).single;
      expect(run.inputFileName, isNull);
      expect(run.rowCount, 4);
      expect(run.failureCount, 1);
    });

    test('an index entry whose result file is gone is not listed', () async {
      await log.append(
        directory(),
        'iris',
        BatchRunRecord(
          timestamp: DateTime(2026, 9, 14),
          inputFileName: 'gone.csv',
          rowCount: 3,
          failureCount: 0,
          resultFileName: 'iris_batch_20260914_000000.csv',
        ),
      );
      expect(await log.loadRuns(directory(), 'iris', config: config), isEmpty);
    });

    test("lists only this model's runs, newest first", () async {
      writeFile('iris_batch_20260101_080000.csv', resultCsv);
      writeFile('iris_batch_20260301_080000.csv', resultCsv);
      writeFile('iris_extra_batch_20260201_080000.csv', resultCsv);
      writeFile('heart_batch_20260201_080000.csv', resultCsv);

      final runs = await log.loadRuns(directory(), 'iris', config: config);
      expect(
        runs.map((r) => r.timestamp),
        [DateTime(2026, 3, 1, 8), DateTime(2026, 1, 1, 8)],
      );
    });

    test('a missing folder has no runs', () async {
      expect(
        await log.loadRuns(
          Directory(p.join(tempDir.path, 'nope')),
          'iris',
          config: config,
        ),
        isEmpty,
      );
    });
  });

  group('SessionLogService with batch runs', () {
    const service = SessionLogService();
    const sessionLog = 'timestamp,age,predicted_class,prob_0,prob_1\r\n'
        '2026-09-14 09:00:00,41,1,0.20,0.80\r\n'
        '2026-09-14 11:00:00,30,0,0.70,0.30\r\n'
        'not a date,22,0,0.60,0.40\r\n';

    test('load returns the session log untouched plus the batch runs',
        () async {
      writeFile('iris_sessions.csv', sessionLog);
      writeFile('iris_batch_20260914_100000.csv', resultCsv);

      final result =
          await service.load(modelPath: 'iris.pkcls', config: config);
      expect(result.succeeded, isTrue);
      expect(result.sessions, hasLength(3));
      expect(result.featureNames, ['age']);
      expect(result.batchRuns, hasLength(1));
    });

    test('entries interleave by time, unparsed sessions last', () async {
      writeFile('iris_sessions.csv', sessionLog);
      writeFile('iris_batch_20260914_100000.csv', resultCsv);

      final result =
          await service.load(modelPath: 'iris.pkcls', config: config);
      expect(
        result.entries.map(
          (e) => switch (e) {
            LoggedSession(:final rawTimestamp) => rawTimestamp,
            LoggedBatchRun() => 'batch',
          },
        ),
        ['2026-09-14 11:00:00', 'batch', '2026-09-14 09:00:00', 'not a date'],
      );
    });

    test('a model with only batch runs is not empty', () async {
      writeFile('iris_batch_20260914_100000.csv', resultCsv);

      final result =
          await service.load(modelPath: 'iris.pkcls', config: config);
      expect(result.exists, isFalse);
      expect(result.isEmpty, isFalse);
      expect(result.entries.single, isA<LoggedBatchRun>());
    });

    test('summarize counts batch runs apart from sessions', () async {
      writeFile('iris_sessions.csv', sessionLog);
      writeFile('iris_batch_20260914_100000.csv', resultCsv);
      writeFile('heart_batch_20260914_100000.csv', resultCsv);
      writeFile(
        'iris_batch_runs.csv',
        'timestamp,input_file,row_count,failure_count,result_file\r\n',
      );

      final summary = await service.summarize(config: config);
      expect(summary.fileCount, 1);
      expect(summary.sessionCount, 3);
      expect(summary.batchRunCount, 2);
      expect(summary.unreadableFileCount, 0);
    });

    test('the index is not mistaken for a session log', () async {
      // With output_path `runs.csv`, session logs end in `_runs.csv` — and
      // so does the batch index.
      const runs = AppConfig(csvOutputPath: 'runs.csv');
      writeFile(
        'iris_batch_runs.csv',
        'timestamp,input_file,row_count,failure_count,result_file\r\n',
      );

      final summary = await service.summarize(config: runs);
      expect(summary.fileCount, 0);
      expect(summary.unreadableFileCount, 0);
    });
  });
}
