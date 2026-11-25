import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/models/model_domain.dart';
import 'package:diagnostic_app/models/orange_variable.dart';
import 'package:diagnostic_app/models/session_record.dart';
import 'package:diagnostic_app/services/csv_service.dart';
import 'package:diagnostic_app/services/session_log_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CsvService.logFileNameFor', () {
    test('derives a per-model name from the configured output path', () {
      expect(
        CsvService.logFileNameFor(r'C:\models\dengue_model.pkcls',
            'sessions.csv'),
        'dengue_model_sessions.csv',
      );
    });

    test('slugifies spaces and punctuation in the model file name', () {
      expect(
        CsvService.logFileNameFor(r'C:\Users\me\Desktop\Dengue orange.pkcls',
            'sessions.csv'),
        'dengue_orange_sessions.csv',
      );
    });

    test('gives different models different files', () {
      final a = CsvService.logFileNameFor('heart_risk_model.pkcls',
          'sessions.csv');
      final b = CsvService.logFileNameFor('Dengue orange.pkcls',
          'sessions.csv');
      expect(a, isNot(b));
    });

    test('preserves a directory part of the configured path', () {
      expect(
        CsvService.logFileNameFor('dengue_model.pkcls', r'logs/sessions.csv'),
        p.join('logs', 'dengue_model_sessions.csv'),
      );
    });

    test('falls back to the configured path when no model is loaded', () {
      expect(CsvService.logFileNameFor('', 'sessions.csv'), 'sessions.csv');
    });

    test('uses the display name once the model has been renamed', () {
      expect(
        CsvService.logFileNameFor(
          r'C:\models\dengue_model.pkcls',
          'sessions.csv',
          displayName: 'Dengue Pediatric',
        ),
        'dengue_pediatric_sessions.csv',
      );
    });

    test('ignores a blank display name', () {
      expect(
        CsvService.logFileNameFor(
          r'C:\models\dengue_model.pkcls',
          'sessions.csv',
          displayName: '   ',
        ),
        'dengue_model_sessions.csv',
      );
    });
  });

  group('CsvService.appendRecord', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    late Directory tempDir;
    late File log;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('csv_service');
      log = File(p.join(tempDir.path, 'zoo_sessions.csv'));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    const domain = ModelDomain(
      features: [
        OrangeVariable(
          name: 'legs',
          type: VariableType.continuous,
          role: VariableRole.feature,
        ),
      ],
      classVar: OrangeVariable(
        name: 'type',
        type: VariableType.discrete,
        role: VariableRole.classVar,
        values: ['bird', 'fish'],
      ),
    );

    Future<void> append({String? diagnosis, String? notes}) async {
      final result = await const CsvService().appendRecord(
        SessionRecord(
          timestamp: DateTime(2026, 11, 25, 10),
          inputs: const {'legs': 2.0},
          predictedClass: 'bird',
          probabilities: const {'bird': 0.9, 'fish': 0.1},
          doctorDiagnosis: diagnosis,
          notes: notes,
        ),
        domain: domain,
        modelPath: 'zoo.pkcls',
        config: AppConfig.defaults,
      );
      expect(result.error, isNull);
    }

    SessionLog read() => const SessionLogService().parse(
          log.readAsStringSync(),
          path: log.path,
          config: AppConfig.defaults,
        );

    test('always writes every column, leaving cells without a value empty',
        () async {
      await append();
      await append(diagnosis: 'Uncertain', notes: 'ok');
      expect(
        log.readAsStringSync(),
        'timestamp,legs,predicted_class,prob_bird,prob_fish,'
        'doctor_diagnosis,notes\r\n'
        '2026-11-25 10:00:00,2.0,bird,0.90,0.10,,\r\n'
        '2026-11-25 10:00:00,2.0,bird,0.90,0.10,Uncertain,ok\r\n',
      );
    });

    test('appends to a log from 1.1.0 without touching it', () async {
      const old = 'timestamp,legs,predicted_class,prob_bird,prob_fish,'
          'doctor_diagnosis,notes\r\n'
          '2026-09-17 09:30:00,4.0,fish,0.20,0.80,Positive,old\r\n';
      log.writeAsStringSync(old);
      await append(diagnosis: 'bird');

      expect(log.readAsStringSync(), startsWith(old));
      // A diagnosis from the former fixed list still reads as it was entered.
      expect(
        read().sessions.map((s) => s.doctorDiagnosis),
        ['bird', 'Positive'],
      );
    });

    test('adds the columns an older log was configured to leave out', () async {
      const oldRow = '2026-09-17 09:30:00,4.0,fish,"two\r\nlines"\r\n';
      log.writeAsStringSync('timestamp,legs,predicted_class,notes\r\n$oldRow');
      await append(diagnosis: 'bird', notes: 'first');
      await append(diagnosis: 'fish', notes: 'second');

      final contents = log.readAsStringSync();
      expect(
        contents,
        startsWith('timestamp,legs,predicted_class,notes,'
            'prob_bird,prob_fish,doctor_diagnosis\r\n$oldRow'),
      );
      expect(contents, contains('bird,first,0.90,0.10,bird\r\n'));
      expect(contents, contains('bird,second,0.90,0.10,fish\r\n'));

      final sessions = read().sessions;
      expect(
        {for (final s in sessions) s.notes: s.doctorDiagnosis},
        {'first': 'bird', 'second': 'fish', 'two\nlines': ''},
      );
      expect(sessions.last.probabilities, isEmpty);
      expect(tempDir.listSync(), hasLength(1));
    });
  });
}
