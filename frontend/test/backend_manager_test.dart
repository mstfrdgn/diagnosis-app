import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diagnostic_app/config/app_config.dart';
import 'package:diagnostic_app/services/backend_manager.dart';
import 'package:diagnostic_app/services/startup_log.dart';
import 'package:flutter_test/flutter_test.dart';

// Plain `test`s, not `testWidgets`: the widget binding fakes every HTTP
// request, and these need the health probe to reach real sockets.

void main() {
  late Directory tmp;
  late _TestManager manager;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('backend_manager_test');
  });

  tearDown(() async {
    await manager.stop();
    await tmp.delete(recursive: true);
  });

  _TestManager managerWith(List<_Behaviour> behaviours) =>
      manager = _TestManager(tmp, behaviours);

  test('lets the OS pick a port and passes it to the backend', () async {
    managerWith([_healthy]);
    await manager.start(host: '127.0.0.1', startupTimeoutSeconds: 5);
    expect(manager.ports, hasLength(1));
    expect(manager.ports.single, isNot(8765));
    expect(manager.port, manager.ports.single);
    expect(manager.isRunning, isTrue);
  });

  test('moves to another port only when the backend could not bind', () async {
    managerWith([_bindError, _healthy]);
    await manager.start(host: '127.0.0.1', startupTimeoutSeconds: 5);
    expect(manager.ports, hasLength(2));
    expect(manager.port, manager.ports.last);
  });

  test('a backend that does not answer in time is kept, not replaced',
      () async {
    managerWith([_silent]);
    await expectLater(
      manager.start(host: '127.0.0.1', startupTimeoutSeconds: 1),
      throwsA(isA<StartupFailure>()
          .having((e) => e.cause, 'cause', StartupCause.notResponding)),
    );
    expect(manager.ports, hasLength(1));
    expect(manager.killed, isEmpty);
    expect(manager.isRunning, isTrue);

    // Retry waits for the same process instead of launching another.
    final retry = manager.start(host: '127.0.0.1', startupTimeoutSeconds: 5);
    await manager.processes.single.serveHealth();
    await retry;
    expect(manager.ports, hasLength(1));
  });

  test('keepWaiting picks up a slow backend once it answers', () async {
    managerWith([_silent]);
    await expectLater(
      manager.start(host: '127.0.0.1', startupTimeoutSeconds: 1),
      throwsA(isA<StartupFailure>()),
    );
    final waiting = manager.keepWaiting();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await manager.processes.single.serveHealth();
    await waiting;
  });

  test('stop ends a background wait without reporting a failure', () async {
    managerWith([_silent]);
    await expectLater(
      manager.start(host: '127.0.0.1', startupTimeoutSeconds: 1),
      throwsA(isA<StartupFailure>()),
    );
    final waiting = manager.keepWaiting();
    await manager.stop();
    await expectLater(waiting, throwsA(isA<BackendSuperseded>()));
  });

  test(
      'a backend listening by its own log but unreachable is reported as '
      'a blocked connection', () async {
    managerWith([_listeningButUnreachable]);
    await expectLater(
      manager.start(host: '127.0.0.1', startupTimeoutSeconds: 1),
      throwsA(isA<StartupFailure>()
          .having((e) => e.cause, 'cause', StartupCause.connectionBlocked)),
    );
  });

  test('a crash is reported as such and not retried on another port', () async {
    managerWith([_crash, _healthy]);
    await expectLater(
      manager.start(host: '127.0.0.1', startupTimeoutSeconds: 5),
      throwsA(isA<StartupFailure>()
          .having((e) => e.cause, 'cause', StartupCause.crashed)
          .having((e) => e.detail, 'detail', contains('DLL load failed'))),
    );
    expect(manager.ports, hasLength(1));
    expect(manager.isRunning, isFalse);
  });

  test('dying without output is reported as blocked', () async {
    managerWith([_mute]);
    await expectLater(
      manager.start(host: '127.0.0.1', startupTimeoutSeconds: 5),
      throwsA(isA<StartupFailure>()
          .having((e) => e.cause, 'cause', StartupCause.securityPolicy)),
    );
  });

  test('a fixed port that is taken falls back to the next one', () async {
    final squatter = await ServerSocket.bind('127.0.0.1', 0);
    try {
      managerWith([_healthy]);
      await manager.start(
        host: '127.0.0.1',
        port: squatter.port,
        startupTimeoutSeconds: 5,
      );
      expect(manager.ports, [squatter.port + 1]);
    } finally {
      await squatter.close();
    }
  });

  test('startup steps end up in app.log', () async {
    managerWith([_healthy]);
    await manager.start(host: '127.0.0.1', startupTimeoutSeconds: 5);
    final log = await manager.log.tail(StartupLog.appLogName);
    expect(log, contains('Launching fake-backend'));
    expect(log, contains('Backend ready on port ${manager.port}'));
  });

  test(
      'the notifier shows the failure but switches to ready when a slow '
      'backend comes up after all', () async {
    managerWith([_silent]);
    final notifier = BackendNotifier(
      manager,
      const AppConfig(backendStartupTimeoutSeconds: 1),
    );
    await _until(() => notifier.status == BackendStatus.error);
    expect(notifier.failure!.cause, StartupCause.notResponding);
    await _until(() => notifier.waitingInBackground);

    await manager.processes.single.serveHealth();
    await _until(() => notifier.status == BackendStatus.ready);
    expect(notifier.failure, isNull);
    expect(notifier.waitingInBackground, isFalse);
  });
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never became true');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

// ── fakes ────────────────────────────────────────────────────────────────────

typedef _Behaviour = Future<void> Function(_FakeProcess process);

/// Answers /health right away.
Future<void> _healthy(_FakeProcess p) => p.serveHealth();

/// Runs but never answers, like a backend held up by an antivirus scan.
Future<void> _silent(_FakeProcess p) async => p.say('backend: starting');

Future<void> _listeningButUnreachable(_FakeProcess p) async =>
    p.say('INFO:     Uvicorn running on http://127.0.0.1:${p.port}');

Future<void> _bindError(_FakeProcess p) async {
  p.say('ERROR:    [Errno 10048] error while attempting to bind on address');
  p.exit(1);
}

Future<void> _crash(_FakeProcess p) async {
  p.say('backend: crashed during startup:');
  p.say('ImportError: DLL load failed while importing _multiarray_umath');
  p.exit(70);
}

Future<void> _mute(_FakeProcess p) async => p.exit(1);

class _TestManager extends BackendManager {
  _TestManager(Directory logBase, this._behaviours)
      : super(log: StartupLog(baseDirectory: () async => logBase));

  final List<_Behaviour> _behaviours;
  final ports = <int>[];
  final processes = <_FakeProcess>[];
  final killed = <_FakeProcess>[];

  @override
  Future<BackendLaunch> resolveLaunch() async =>
      (exe: 'fake-backend', workDir: null);

  @override
  Future<Process> spawnProcess(BackendLaunch launch, List<String> args) async {
    final port = int.parse(args[args.indexOf('--port') + 1]);
    final process = _FakeProcess(1000 + ports.length, port);
    ports.add(port);
    processes.add(process);
    await _behaviours[processes.length - 1](process);
    return process;
  }

  @override
  Future<void> killProcess(Process process) async {
    final fake = process as _FakeProcess;
    killed.add(fake);
    fake.exit(-1);
  }
}

class _FakeProcess implements Process {
  _FakeProcess(this.pid, this.port);

  @override
  final int pid;
  final int port;

  final _exit = Completer<int>();
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  HttpServer? _server;

  void say(String line) => _stderr.add(utf8.encode('$line\n'));

  Future<void> serveHealth() async {
    final server = await HttpServer.bind('127.0.0.1', port);
    _server = server;
    server.listen((req) {
      req.response
        ..statusCode = 200
        ..write('{"status":"ok"}')
        ..close();
    });
  }

  void exit(int code) {
    if (_exit.isCompleted) return;
    _server?.close(force: true);
    _stdout.close();
    _stderr.close();
    _exit.complete(code);
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  IOSink get stdin => throw UnimplementedError();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    exit(-1);
    return true;
  }
}
