import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/services/session_log_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _service = SessionLogService();
const _config = AppConfig();

SessionLog parse(String contents, {AppConfig config = _config}) =>
    _service.parse(contents, path: 'sessions.csv', config: config);

void main() {
  group('SessionLogService.parse', () {
    const log = 'timestamp,age,fever,predicted_class,prob_0,prob_1,'
        'doctor_diagnosis,notes\r\n'
        '2026-09-17 09:30:00,41,yes,1,0.18,0.82,Positive,Admitted\r\n'
        '2026-09-16 14:05:11,7,no,0,0.91,0.09,Negative,\r\n';

    test('reads the columns the header describes', () {
      final result = parse(log);
      expect(result.succeeded, isTrue);
      expect(result.featureNames, ['age', 'fever']);
      expect(result.sessions, hasLength(2));

      final newest = result.sessions.first;
      expect(newest.timestamp, DateTime(2026, 9, 17, 9, 30));
      expect(newest.predictedClass, '1');
      expect(newest.inputs, {'age': '41', 'fever': 'yes'});
      expect(newest.probabilities, {'0': 0.18, '1': 0.82});
      expect(newest.doctorDiagnosis, 'Positive');
      expect(newest.notes, 'Admitted');
    });

    test('confidence is the highest probability in the row', () {
      expect(parse(log).sessions.first.confidence, 0.82);
      expect(parse(log).sessions.last.confidence, 0.91);
    });

    test('sorts newest first regardless of file order', () {
      final result = parse(log);
      expect(
        result.sessions.map((s) => s.rawTimestamp),
        ['2026-09-17 09:30:00', '2026-09-16 14:05:11'],
      );
    });

    test('keeps the columns straight when probabilities were not logged', () {
      final result = parse(
        'timestamp,age,predicted_class,doctor_diagnosis,notes\r\n'
        '2026-09-17 09:30:00,41,1,Positive,ok\r\n',
      );
      final session = result.sessions.single;
      expect(session.probabilities, isEmpty);
      expect(session.confidence, isNull);
      expect(session.predictedClass, '1');
      expect(session.doctorDiagnosis, 'Positive');
    });

    test('follows the configured timestamp format', () {
      final result = parse(
        'timestamp,age,predicted_class\r\n17.09.2026 09:30:00,41,1\r\n',
        config: const AppConfig(csvTimestampFormat: '%d.%m.%Y %H:%M:%S'),
      );
      expect(result.sessions.single.timestamp, DateTime(2026, 9, 17, 9, 30));
    });

    test('reads rows written before the timestamp format was changed', () {
      final result = parse(
        'timestamp,age,predicted_class\r\n'
        '17.09.2026 09:30:00,41,1\r\n'
        '2026-09-18 10:00:00,42,1\r\n'
        '2026-09-19T11:15:30,43,1\r\n'
        '2026-09-20 12:00,44,1\r\n'
        '21.09.2026 13:45,45,1\r\n',
        config: const AppConfig(csvTimestampFormat: '%d/%m/%Y %H:%M'),
      );
      expect(result.sessions.map((s) => s.timestamp), [
        DateTime(2026, 9, 21, 13, 45),
        DateTime(2026, 9, 20, 12),
        DateTime(2026, 9, 19, 11, 15, 30),
        DateTime(2026, 9, 18, 10),
        DateTime(2026, 9, 17, 9, 30),
      ]);
    });

    test('tries the configured format before the others', () {
      final result = parse(
        'timestamp,age,predicted_class\r\n03.04.2026 09:30,41,1\r\n',
        config: const AppConfig(csvTimestampFormat: '%m.%d.%Y %H:%M'),
      );
      expect(result.sessions.single.timestamp, DateTime(2026, 3, 4, 9, 30));
    });

    test('does not guess at a date with slashes', () {
      final result = parse(
        'timestamp,age,predicted_class\r\n03/04/2026 09:30:00,41,1\r\n',
      );
      expect(result.sessions.single.timestamp, isNull);
    });

    test('keeps a row whose timestamp does not match the format', () {
      final result = parse(
        'timestamp,age,predicted_class\r\nsometime yesterday,41,1\r\n',
      );
      final session = result.sessions.single;
      expect(session.timestamp, isNull);
      expect(session.rawTimestamp, 'sometime yesterday');
      expect(session.predictedClass, '1');
    });

    test('pads a truncated row instead of dropping the rows after it', () {
      final result = parse(
        'timestamp,age,predicted_class,doctor_diagnosis,notes\r\n'
        '2026-09-17 09:30:00,41,1\r\n'
        '2026-09-17 10:00:00,52,0,Negative,fine\r\n',
      );
      expect(result.sessions, hasLength(2));
      expect(result.sessions.last.doctorDiagnosis, isEmpty);
      expect(result.sessions.last.notes, isEmpty);
    });

    test('sinks unparseable timestamps below the dated rows', () {
      final result = parse(
        'timestamp,age,predicted_class\r\n'
        'sometime yesterday,41,1\r\n'
        '2026-09-16 14:05:11,7,0\r\n'
        '2026-09-17 09:30:00,52,1\r\n',
      );
      expect(
        result.sessions.map((s) => s.rawTimestamp),
        ['2026-09-17 09:30:00', '2026-09-16 14:05:11', 'sometime yesterday'],
      );
    });

    test('a header-only file is an empty log, not an error', () {
      final result = parse('timestamp,age,predicted_class\r\n');
      expect(result.succeeded, isTrue);
      expect(result.sessions, isEmpty);
    });

    test('rejects a file that is not one of our logs', () {
      final result = parse('name,value\r\nfoo,1\r\n');
      expect(result.succeeded, isFalse);
      expect(result.error, contains('Unrecognised log format'));
    });
  });
}
