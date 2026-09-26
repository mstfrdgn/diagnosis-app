import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/services/csv_service.dart';
import 'package:diagnostic_app/services/session_log_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The Settings screen reports the log folder as a whole, so what matters is
/// that the count covers every per-model log and nothing else that happens to
/// sit in the same folder.
void main() {
  // Plain `test`s, so the binding backing the path_provider mock has to be
  // brought up by hand.
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = SessionLogService();
  const config = AppConfig();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('session_log_summary');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Writes a log with [rows] data rows under a valid header.
  void writeLog(String name, int rows) {
    final buffer = StringBuffer('timestamp,age,predicted_class\r\n');
    for (var i = 0; i < rows; i++) {
      buffer.write('2026-09-1${i % 9} 09:30:00,${20 + i},1\r\n');
    }
    File(p.join(tempDir.path, name)).writeAsStringSync(buffer.toString());
  }

  group('SessionLogService.summarize', () {
    test('a folder that does not exist yet counts as nothing', () async {
      final summary = await service.summarize(
        config: const AppConfig(csvOutputPath: 'logs/sessions.csv'),
      );

      expect(summary.succeeded, isTrue);
      expect(summary.fileCount, 0);
      expect(summary.sessionCount, 0);
    });

    test('an empty folder counts as nothing', () async {
      final summary = await service.summarize(config: config);

      expect(summary.succeeded, isTrue);
      expect(summary.fileCount, 0);
      expect(summary.sessionCount, 0);
    });

    test('adds the rows up across every per-model log', () async {
      writeLog('iris_sessions.csv', 3);
      writeLog('heart_risk_sessions.csv', 5);

      final summary = await service.summarize(config: config);

      expect(summary.fileCount, 2);
      expect(summary.sessionCount, 8);
      expect(summary.unreadableFileCount, 0);
    });

    test('counts the bare fallback file too', () async {
      writeLog('sessions.csv', 2);

      final summary = await service.summarize(config: config);

      expect(summary.fileCount, 1);
      expect(summary.sessionCount, 2);
    });

    test('a header-only log is a file with no sessions', () async {
      writeLog('iris_sessions.csv', 0);

      final summary = await service.summarize(config: config);

      expect(summary.fileCount, 1);
      expect(summary.sessionCount, 0);
      expect(summary.unreadableFileCount, 0);
    });

    test('ignores files that are not per-model logs', () async {
      writeLog('iris_sessions.csv', 4);
      File(p.join(tempDir.path, 'notes.txt')).writeAsStringSync('hello');
      File(p.join(tempDir.path, 'export.csv')).writeAsStringSync('a,b\r\n1,2\r\n');
      File(p.join(tempDir.path, 'model_configs.json')).writeAsStringSync('{}');

      final summary = await service.summarize(config: config);

      expect(summary.fileCount, 1);
      expect(summary.sessionCount, 4);
    });

    test('one unreadable log does not hide the rest', () async {
      writeLog('iris_sessions.csv', 3);
      File(p.join(tempDir.path, 'broken_sessions.csv'))
          .writeAsStringSync('not,a,session,log\r\n1,2,3,4\r\n');

      final summary = await service.summarize(config: config);

      expect(summary.fileCount, 2);
      expect(summary.sessionCount, 3);
      expect(summary.unreadableFileCount, 1);
    });

    test('follows output_path into a subdirectory', () async {
      const nested = AppConfig(csvOutputPath: 'logs/sessions.csv');
      Directory(p.join(tempDir.path, 'logs')).createSync();
      File(p.join(tempDir.path, 'logs', 'iris_sessions.csv'))
          .writeAsStringSync('timestamp,age,predicted_class\r\n'
              '2026-09-17 09:30:00,41,1\r\n');
      // Same name, wrong folder: it belongs to a different output_path.
      writeLog('iris_sessions.csv', 9);

      final summary = await service.summarize(config: nested);

      expect(summary.fileCount, 1);
      expect(summary.sessionCount, 1);
    });
  });

  group('CsvService.isModelLogFileName', () {
    test('accepts the names logFileNameFor produces', () {
      const configured = 'sessions.csv';
      for (final model in ['iris.pkcls', 'Heart Risk.pkcls', 'a.pkcls']) {
        final name = CsvService.logFileNameFor(model, configured);
        expect(
          CsvService.isModelLogFileName(name, configured),
          isTrue,
          reason: name,
        );
      }
    });

    test('accepts the bare fallback and matches case-insensitively', () {
      expect(CsvService.isModelLogFileName('sessions.csv', 'sessions.csv'),
          isTrue);
      expect(CsvService.isModelLogFileName('IRIS_Sessions.CSV', 'sessions.csv'),
          isTrue);
    });

    test('rejects unrelated files in the same folder', () {
      for (final name in [
        'notes.txt',
        'export.csv',
        'sessions.csv.bak',
        'model_configs.json',
        'iris_sessions.xlsx',
        'iris-sessions.csv',
      ]) {
        expect(
          CsvService.isModelLogFileName(name, 'sessions.csv'),
          isFalse,
          reason: name,
        );
      }
    });

    test('compares against the configured name, not a fixed one', () {
      expect(CsvService.isModelLogFileName('iris_runs.csv', 'logs/runs.csv'),
          isTrue);
      expect(CsvService.isModelLogFileName('iris_sessions.csv', 'logs/runs.csv'),
          isFalse);
    });
  });
}
