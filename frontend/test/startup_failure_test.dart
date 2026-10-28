import 'package:diagnostic_app/services/startup_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('causeOfLaunchError', () {
    test('a missing executable means files were removed', () {
      expect(causeOfLaunchError(2), StartupCause.filesMissing);
      expect(causeOfLaunchError(3), StartupCause.filesMissing);
    });

    test('access denied and policy blocks point to a security policy', () {
      expect(causeOfLaunchError(5), StartupCause.securityPolicy);
      expect(causeOfLaunchError(1260), StartupCause.securityPolicy);
      expect(causeOfLaunchError(4551), StartupCause.securityPolicy);
    });

    test('virus errors point to antivirus', () {
      expect(causeOfLaunchError(225), StartupCause.antivirusBlocked);
    });

    test('anything else is unknown', () {
      expect(causeOfLaunchError(87), StartupCause.unknown);
    });
  });

  group('causeOfUnpackError', () {
    test('disk full', () {
      expect(causeOfUnpackError(112), StartupCause.diskFull);
      expect(causeOfUnpackError(28), StartupCause.diskFull);
    });

    test('no permission', () {
      expect(causeOfUnpackError(5), StartupCause.noWriteAccess);
      expect(causeOfUnpackError(13), StartupCause.noWriteAccess);
    });

    test('antivirus refusing the write', () {
      expect(causeOfUnpackError(225), StartupCause.antivirusBlocked);
    });

    test('no OS error at all', () {
      expect(causeOfUnpackError(null), StartupCause.unpackFailed);
    });
  });

  group('isBindError', () {
    test('recognises uvicorn bind failures on Windows and Unix', () {
      expect(
        isBindError('ERROR:    [Errno 10048] error while attempting to bind '
            'on address (\'127.0.0.1\', 8765): only one usage of each socket '
            'address is normally permitted'),
        isTrue,
      );
      expect(isBindError('[Errno 98] Address already in use'), isTrue);
    });

    test('ignores other errors', () {
      expect(isBindError('ImportError: DLL load failed'), isFalse);
    });
  });

  group('causeOfExit', () {
    test('missing files win over everything else', () {
      expect(
        causeOfExit(exitCode: 70, output: 'Traceback', filesIntact: false),
        StartupCause.filesMissing,
      );
    });

    test('Windows access-denied status is a security policy', () {
      expect(
        causeOfExit(exitCode: -1073741790, output: '', filesIntact: true),
        StartupCause.securityPolicy,
      );
      expect(
        causeOfExit(exitCode: 0xC0000022, output: '', filesIntact: true),
        StartupCause.securityPolicy,
      );
    });

    test('a missing DLL status means files are missing', () {
      expect(
        causeOfExit(exitCode: 0xC0000135, output: '', filesIntact: true),
        StartupCause.filesMissing,
      );
    });

    test('dying without a word means it was stopped before it ran', () {
      expect(
        causeOfExit(exitCode: 1, output: '  \n', filesIntact: true),
        StartupCause.securityPolicy,
      );
    });

    test('a traceback is a crash', () {
      expect(
        causeOfExit(
          exitCode: 70,
          output: 'backend: crashed during startup:\nTraceback ...',
          filesIntact: true,
        ),
        StartupCause.crashed,
      );
    });
  });

  group('causeOfTimeout', () {
    test('listening by its own log means the connection is blocked', () {
      expect(
        causeOfTimeout(
          output: 'INFO:     Uvicorn running on http://127.0.0.1:50123',
          filesIntact: true,
        ),
        StartupCause.connectionBlocked,
      );
    });

    test('otherwise it is still starting', () {
      expect(
        causeOfTimeout(output: 'backend: starting', filesIntact: true),
        StartupCause.notResponding,
      );
    });

    test('missing files win', () {
      expect(
        causeOfTimeout(output: '', filesIntact: false),
        StartupCause.filesMissing,
      );
    });
  });

  test('every cause has plain-language text', () {
    for (final cause in StartupCause.values) {
      final failure = StartupFailure(cause, 'detail', folder: r'C:\x');
      expect(failure.title, isNotEmpty, reason: cause.name);
      expect(failure.explanation, isNotEmpty, reason: cause.name);
      expect(failure.suggestion, isNotEmpty, reason: cause.name);
    }
  });

  test('only a backend that may still answer is waited for', () {
    expect(
      const StartupFailure(StartupCause.notResponding, '').mayStillStart,
      isTrue,
    );
    expect(
      const StartupFailure(StartupCause.crashed, '').mayStillStart,
      isFalse,
    );
  });

  test('the diagnostic report carries cause, versions and both logs', () {
    final report = buildDiagnosticReport(
      failure: const StartupFailure(
        StartupCause.notResponding,
        'did not respond within 180 s',
      ),
      appVersion: '1.0.0+1 (release)',
      osVersion: 'windows "Windows 11 Pro" 10.0 (Build 26200)',
      appLog: 'Launching x',
      backendLog: '',
      now: DateTime(2026, 10, 21, 9, 30),
    );
    expect(report, contains('App version: 1.0.0+1 (release)'));
    expect(report, contains('Windows 11 Pro'));
    expect(report, contains('notResponding'));
    expect(report, contains('did not respond within 180 s'));
    expect(report, contains('--- app log (end) ---\nLaunching x'));
    expect(report, contains('--- backend log (end) ---\n(empty)'));
  });

  test('the report does not repeat backend output quoted in the details', () {
    const traceback = 'Traceback (most recent call last):\n'
        '  File "main.py", line 1\n'
        'ImportError: DLL load failed';
    final report = buildDiagnosticReport(
      failure: const StartupFailure(
        StartupCause.crashed,
        'exited with code 70\nIts last output:\n$traceback',
        output: traceback,
      ),
      appVersion: '1.1.0+1 (release)',
      osVersion: 'windows',
      appLog: 'Launching x',
      // As the backend writes it on Windows: CRLF, after an earlier run.
      backendLog: 'earlier run\r\n${traceback.replaceAll('\n', '\r\n')}\r\n',
      now: DateTime(2026, 10, 28),
    );
    expect('ImportError: DLL load failed'.allMatches(report), hasLength(1));
    expect(
      report,
      contains('--- backend log (end) ---\nearlier run\n'
          '(last 3 lines omitted: shown in the details above)'),
    );
  });
}
