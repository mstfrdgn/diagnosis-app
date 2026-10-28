import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import 'startup_failure.dart';
import 'startup_log.dart';

export 'startup_failure.dart';

// ── status ───────────────────────────────────────────────────────────────────

enum BackendStatus { starting, ready, error }

/// What a start is busy with, for the splash screen.
enum BackendPhase { unpacking, launching, repairing }

// ── exceptions ────────────────────────────────────────────────────────────────

/// Thrown out of a wait that a newer [BackendManager.start],
/// [BackendManager.stop] or [BackendManager.repair] took over. Not a failure:
/// whoever took over reports the outcome.
class BackendSuperseded implements Exception {
  const BackendSuperseded();
}

/// The backend exited because its port was taken after all; worth another
/// port, unlike every other exit.
class _PortTaken extends StartupFailure {
  const _PortTaken(String detail) : super(StartupCause.portUnavailable, detail);
}

// ── manager ───────────────────────────────────────────────────────────────────

/// How the backend gets started: `python main.py` from the source tree in
/// debug builds, the unpacked PyInstaller bundle otherwise.
typedef BackendLaunch = ({String exe, String? workDir});

/// Launches, health-polls, and eventually terminates the FastAPI subprocess.
class BackendManager {
  BackendManager({StartupLog? log}) : log = log ?? StartupLog();

  /// Where every startup step is recorded; see [StartupLog].
  final StartupLog log;

  /// Told what a start is doing, for display only.
  void Function(BackendPhase phase)? onPhase;

  Process? _process;

  /// Exit code of [_process], latched once it has exited.
  int? _exitCode;
  DateTime _launchedAt = DateTime.now();

  /// When [_process] exited, latched with [_exitCode]: classifying the exit
  /// takes a while, and the lifetime reported must not include it.
  DateTime? _exitedAt;
  String _host = '127.0.0.1';
  int _port = 0;

  /// Bumped by every start, stop and repair. A wait that sees it change has
  /// been taken over and gives up quietly.
  int _generation = 0;

  /// Path of the unpacked bundle's executable, shared by every port attempt
  /// so the bundle is checked and unpacked at most once per run.
  Future<String>? _bundledExe;

  /// Folder of the unpacked bundle, once known.
  String? _installDir;

  /// The most recent lines the backend wrote to its pipes.
  final _pipeOutput = <String>[];

  /// Size of `backend.log` when the current process was launched: what it
  /// wrote is everything after that.
  int _backendLogOffset = 0;

  /// Completes once the current process's pipes are closed and read out.
  Future<void> _pipesDone = Future.value();

  /// Why the last health probe failed, for the report.
  String _lastProbeError = 'none sent';

  /// Floor for the startup timeout when running the bundle. The first launch
  /// after an install or update runs files the antivirus has never seen, and
  /// on a busy or managed machine scanning them can take minutes.
  static const bundledStartupTimeoutSeconds = 180;

  static const _maxPortAttempts = 5;
  static const _assetDir = 'assets/backend';
  static const _bundleName = 'diagnostic_backend';
  static const _manifestName = '.manifest';

  String get host => _host;
  int get port => _port;
  String get baseUrl => 'http://$_host:$_port';

  /// Whether a backend process from an earlier attempt is still alive.
  bool get isRunning => _process != null && _exitCode == null;

  /// Start the backend and wait for it to answer.
  ///
  /// Without [port] the OS picks a free one. With [port] (the `fixed_port`
  /// override) that port is tried first, then up to 4 above it.
  ///
  /// If an earlier start left a process that is still running but has not
  /// answered yet, this waits for that one again rather than killing it and
  /// starting over: whatever slows it down (an antivirus scan, typically)
  /// would only start over too.
  ///
  /// Throws [StartupFailure] when the backend does not come up, leaving it
  /// running if it is merely slow (see [StartupFailure.mayStillStart]).
  Future<void> start({
    required String host,
    int? port,
    required int startupTimeoutSeconds,
  }) async {
    _host = host;
    final generation = ++_generation;
    final timeout = Duration(
      seconds: kDebugMode
          ? startupTimeoutSeconds
          : max(startupTimeoutSeconds, bundledStartupTimeoutSeconds),
    );
    await log.directory;

    if (isRunning) {
      log.write('Waiting again for backend pid ${_process!.pid} '
          'on port $_port');
      onPhase?.call(BackendPhase.launching);
      await _waitUntilReady(generation, timeout);
      return;
    }

    final launch = await resolveLaunch();
    onPhase?.call(BackendPhase.launching);
    for (var attempt = 1;; attempt++) {
      final last = attempt == _maxPortAttempts;
      final tryPort = port == null ? await _freePort() : port + attempt - 1;
      if (port != null && !await _isPortFree(tryPort)) {
        log.write('Port $tryPort is in use');
        if (last) {
          throw StartupFailure(
            StartupCause.portUnavailable,
            'Ports $port to $tryPort are all in use.',
          );
        }
        continue;
      }
      try {
        await _launch(launch, tryPort, timeout, generation);
        return;
      } on _PortTaken catch (e) {
        log.write('Port $tryPort was taken before the backend bound it');
        if (last) throw StartupFailure(e.cause, e.detail);
      }
    }
  }

  /// Wait, without a deadline, for the backend left running by a [start]
  /// that timed out. Throws [StartupFailure] if it exits instead, and
  /// [BackendSuperseded] if anything else starts or stops it meanwhile.
  Future<void> keepWaiting() => _waitUntilReady(_generation, null);

  /// Kill the backend subprocess (entire process tree on Windows).
  Future<void> stop() async {
    _generation++;
    final process = _process;
    _process = null;
    if (process == null) return;
    log.write('Stopping backend pid ${process.pid}');
    await killProcess(process);
  }

  /// Throw away the unpacked backend so the next [start] unpacks it afresh.
  ///
  /// Every backend of this user is killed first, including strays from
  /// earlier runs: a running one keeps its files locked.
  Future<void> repair() async {
    onPhase?.call(BackendPhase.repairing);
    log.write('Repair: removing the unpacked backend');
    await stop();
    _bundledExe = null;
    if (kDebugMode) return;
    await _killStrayBackends();

    final root = Directory(await _backendRoot());
    // Killed processes release their files a moment after taskkill returns.
    for (var attempt = 1;; attempt++) {
      try {
        if (await root.exists()) await root.delete(recursive: true);
        log.write('Repair: removed ${root.path}');
        return;
      } on FileSystemException catch (e) {
        if (attempt == 10) {
          log.write('Repair: could not remove ${root.path}: $e');
          throw StartupFailure(
            causeOfUnpackError(e.osError?.errorCode),
            'Could not remove ${root.path} for the repair: $e',
            folder: root.path,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  // ── overridable for tests ──────────────────────────────────────────────────

  @visibleForTesting
  Future<BackendLaunch> resolveLaunch() async {
    if (kDebugMode) {
      final workDir = _findBackendDir();
      if (workDir == null) {
        throw const StartupFailure(
          StartupCause.devSetup,
          'Cannot locate backend/main.py.\n'
          'Run "flutter run" from the diagnostic_app project root, or supply\n'
          '--dart-define=DIAGNOSTIC_BACKEND_DIR=/absolute/path/to/backend.',
        );
      }
      return (exe: _debugExecutable(workDir), workDir: workDir);
    }
    onPhase?.call(BackendPhase.unpacking);
    try {
      return (exe: await (_bundledExe ??= _unpackBundle()), workDir: null);
    } catch (_) {
      _bundledExe = null; // let Retry unpack again
      rethrow;
    }
  }

  @visibleForTesting
  Future<Process> spawnProcess(BackendLaunch launch, List<String> args) =>
      Process.start(
        launch.exe,
        args,
        workingDirectory: launch.workDir,
        // runInShell lets Windows resolve 'python' through %PATH%; the
        // bundle is started by its absolute path and needs no shell.
        runInShell: kDebugMode && Platform.isWindows,
      );

  @visibleForTesting
  Future<void> killProcess(Process process) async {
    if (Platform.isWindows) {
      // With runInShell, a plain kill() only reaches the shell and orphans
      // the Python server behind it.
      await Process.run(
        'taskkill',
        ['/F', '/T', '/PID', '${process.pid}'],
        runInShell: true,
      );
    } else {
      process.kill(ProcessSignal.sigterm);
    }
  }

  // ── private ────────────────────────────────────────────────────────────────

  Future<void> _launch(
    BackendLaunch launch,
    int port,
    Duration timeout,
    int generation,
  ) async {
    final backendLog = kDebugMode ? null : await log.backendLogFile;
    final args = _buildArgs(port, _host, backendLog?.path);
    _backendLogOffset = backendLog != null && await backendLog.exists()
        ? await backendLog.length()
        : 0;

    log.write('Launching ${launch.exe} ${args.join(' ')}');
    final Process process;
    try {
      process = await spawnProcess(launch, args);
    } on ProcessException catch (e) {
      log.write('Launch failed: $e');
      var cause = causeOfLaunchError(e.errorCode);
      if (cause == StartupCause.unknown && (await _missingFiles()).isNotEmpty) {
        cause = StartupCause.filesMissing;
      }
      throw StartupFailure(
        cause,
        'Failed to start backend process ${launch.exe}: $e',
        folder: _installDir,
      );
    }

    _process = process;
    _exitCode = null;
    _exitedAt = null;
    _port = port;
    _launchedAt = DateTime.now();
    _pipeOutput.clear();
    _lastProbeError = 'none sent';
    log.write('Backend pid ${process.pid} started on port $port');

    // Read even when the backend logs to its own file: unread pipes fill up,
    // and the backend then blocks on its next write.
    Future<void> capture(Stream<List<int>> stream, String tag) => stream
            .transform(const SystemEncoding().decoder)
            .transform(const LineSplitter())
            .listen((line) {
          if (identical(_process, process)) {
            _pipeOutput.add(line);
            if (_pipeOutput.length > 200) _pipeOutput.removeAt(0);
          }
          log.write('[$tag] $line');
        }).asFuture<void>();

    _pipesDone = Future.wait([
      capture(process.stdout, 'backend'),
      capture(process.stderr, 'backend:err'),
    ]);

    // Latched rather than awaited: the readiness loop has to keep polling and
    // check the exit as it goes, so it can give up the moment the process is
    // gone instead of waiting out the full timeout.
    unawaited(process.exitCode.then((code) {
      final exitedAt = DateTime.now();
      log.write('Backend pid ${process.pid} exited with code $code '
          '(${_hex(code)}) after ${_elapsed(exitedAt)}');
      if (identical(_process, process)) {
        _exitedAt = exitedAt;
        _exitCode = code;
      }
    }));

    await _waitUntilReady(generation, timeout);
  }

  /// A port nothing listens on, picked by the OS.
  ///
  /// It is free only until the backend binds it, and something else could
  /// take it in between; the backend then exits with a bind error and
  /// [start] tries another.
  Future<int> _freePort() async {
    try {
      final socket = await ServerSocket.bind(_host, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } on SocketException catch (e) {
      throw StartupFailure(
        StartupCause.portUnavailable,
        'Could not open any local port on $_host: $e',
      );
    }
  }

  /// Whether [port] can still be claimed, decided by asking the OS to bind it.
  ///
  /// Only needed for a fixed port: a backend left over from an earlier run
  /// answers /health exactly like one we started, so a busy port must not be
  /// mistaken for ours.
  Future<bool> _isPortFree(int port) async {
    try {
      final socket = await ServerSocket.bind(_host, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<void> _waitUntilReady(int generation, Duration? timeout) async {
    final started = DateTime.now();
    final deadline = timeout == null ? null : started.add(timeout);
    final client = http.Client();
    try {
      while (deadline == null || DateTime.now().isBefore(deadline)) {
        if (generation != _generation || _process == null) {
          throw const BackendSuperseded();
        }
        final code = _exitCode;
        if (code != null) throw await _exitFailure(code);
        try {
          final res = await client
              .get(Uri.parse('http://$_host:$_port/health'))
              .timeout(const Duration(seconds: 2));
          if (res.statusCode == 200) {
            if (generation != _generation) throw const BackendSuperseded();
            log.write('Backend ready on port $_port after ${_elapsed()}');
            return;
          }
          _lastProbeError = 'HTTP ${res.statusCode}';
        } on BackendSuperseded {
          rethrow;
        } catch (e) {
          // not ready yet – keep polling
          _lastProbeError = '$e';
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      client.close();
    }
    throw await _timeoutFailure(timeout!);
  }

  Future<StartupFailure> _exitFailure(int code) async {
    final process = _process;
    _process = null; // nothing left to kill
    // The exit can be seen before the last lines it wrote have been read.
    await _pipesDone.timeout(const Duration(seconds: 2), onTimeout: () => []);
    final output = await _recentOutput();
    if (isBindError(output)) return _PortTaken(output);

    final shown = StartupLog.tailOf(output, 25);
    final missing = await _missingFiles();
    final cause = causeOfExit(
      exitCode: code,
      output: output,
      filesIntact: missing.isEmpty,
    );
    log.write('Classified exit as ${cause.name}');
    return StartupFailure(
      cause,
      [
        'Backend process ${process?.pid} exited with code $code (${_hex(code)}) '
            'after ${_elapsed(_exitedAt)}, before it was ready.',
        if (missing.isNotEmpty) _describeMissing(missing),
        if (output.trim().isEmpty)
          'It wrote no output at all.'
        else
          'Its last output:\n$shown',
      ].join('\n'),
      folder: _installDir,
      output: shown,
    );
  }

  Future<StartupFailure> _timeoutFailure(Duration timeout) async {
    final output = await _recentOutput();
    final shown = StartupLog.tailOf(output, 25);
    final missing = await _missingFiles();
    final cause = causeOfTimeout(output: output, filesIntact: missing.isEmpty);
    log.write('No answer within ${timeout.inSeconds} s; last probe error: '
        '$_lastProbeError; classified as ${cause.name}');
    return StartupFailure(
      cause,
      [
        'Backend pid ${_process?.pid} on port $_port did not respond within '
            '${timeout.inSeconds} s and is still running.',
        'Last health check: $_lastProbeError',
        if (missing.isNotEmpty) _describeMissing(missing),
        if (output.trim().isEmpty)
          'It has written no output yet.'
        else
          'Its last output:\n$shown',
      ].join('\n'),
      folder: _installDir,
      output: shown,
    );
  }

  /// Everything the current process wrote: its pipes, plus what it appended
  /// to `backend.log` since it was launched.
  Future<String> _recentOutput() async {
    final parts = List.of(_pipeOutput);
    if (!kDebugMode) {
      try {
        final file = await log.backendLogFile;
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final from = min(_backendLogOffset, bytes.length);
          final start = max(from, bytes.length - 64 * 1024);
          parts.add(utf8.decode(bytes.sublist(start), allowMalformed: true));
        }
      } on FileSystemException {
        // reported as no output
      }
    }
    return parts.join('\n');
  }

  /// Files of the unpacked bundle that are gone or truncated, checked against
  /// the list written when it was unpacked. Only run after a failure: it
  /// touches every file of the bundle.
  Future<List<String>> _missingFiles() async {
    final dir = _installDir;
    if (kDebugMode || dir == null) return const [];
    try {
      return await Isolate.run(() => _checkManifest(dir));
    } catch (e) {
      log.write('File check failed: $e');
      return const [];
    }
  }

  static List<String> _checkManifest(String dir) {
    final manifest = File(p.join(dir, _manifestName));
    // Unpacked by a version that wrote no list; the executable is all that
    // can be checked, and the start already did.
    if (!manifest.existsSync()) return const [];
    final missing = <String>[];
    for (final line in manifest.readAsLinesSync()) {
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final size = int.parse(line.substring(0, tab));
      final name = line.substring(tab + 1);
      final file = File(p.join(dir, name));
      if (!file.existsSync() || file.lengthSync() != size) missing.add(name);
    }
    return missing;
  }

  String _describeMissing(List<String> missing) =>
      'Missing or damaged files in $_installDir (${missing.length}): '
      '${missing.take(10).join(', ')}'
      '${missing.length > 10 ? ', …' : ''}';

  /// Time from launch to [until], or to now.
  String _elapsed([DateTime? until]) {
    final ms =
        (until ?? DateTime.now()).difference(_launchedAt).inMilliseconds;
    return '${(ms / 1000).toStringAsFixed(1)} s';
  }

  static String _hex(int code) =>
      '0x${(code & 0xFFFFFFFF).toRadixString(16).toUpperCase()}';

  /// Kill backends of this user that this run does not know about, e.g. one
  /// left over from a run that was killed itself.
  Future<void> _killStrayBackends() async {
    try {
      if (Platform.isWindows) {
        final user = Platform.environment['USERNAME'];
        await Process.run('taskkill', [
          '/F',
          '/IM',
          '$_bundleName.exe',
          if (user != null) ...['/FI', 'USERNAME eq $user'],
        ]);
      } else {
        final user = Platform.environment['USER'];
        await Process.run('pkill', [
          '-x',
          if (user != null) ...['-U', user],
          _bundleName,
        ]);
      }
    } on ProcessException catch (e) {
      log.write('Could not look for stray backends: $e');
    }
  }

  // ── path resolution ────────────────────────────────────────────────────────

  static Future<String> _backendRoot() async =>
      p.join((await getApplicationCacheDirectory()).path, 'backend');

  /// Unpack the bundled backend (the zipped PyInstaller --onedir build) into
  /// the app cache, unless this exact build is already there, and return the
  /// path of its executable.
  ///
  /// Each build gets a folder named after its SHA256, so an app update never
  /// runs an older backend, and only the small checksum asset is read on
  /// a normal start. The marker file is written last: a folder without it
  /// is an interrupted extraction and gets redone.
  Future<String> _unpackBundle() async {
    final expected =
        (await rootBundle.loadString('$_assetDir/$_bundleName.sha256'))
            .trim()
            .toLowerCase();
    final root = await _backendRoot();
    final installDir = p.join(root, expected);
    _installDir = installDir;
    final exe = p.join(
      installDir,
      Platform.isWindows ? '$_bundleName.exe' : _bundleName,
    );
    final marker = File(p.join(installDir, '.unpacked'));
    if (await marker.exists()) {
      // The executable is checked too: antivirus software may have
      // quarantined it since it was unpacked.
      if (await File(exe).exists()) {
        log.write('Backend already unpacked: $exe');
        return exe;
      }
      log.write('Backend executable is missing from an unpacked bundle '
          '(probably removed by antivirus); unpacking again');
    }

    log.write('Unpacking backend to $installDir');
    final started = DateTime.now();
    try {
      final dir = Directory(installDir);
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);

      // Copied out of the asset bundle so the isolate below can stream it
      // from disk instead of holding the whole archive in memory twice.
      final zipPath = p.join(root, '$expected.zip');
      final data = await rootBundle.load('$_assetDir/$_bundleName.zip');
      await File(zipPath).writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      try {
        // Hashing and inflating a few hundred MB would freeze the splash
        // screen if done on this isolate.
        await Isolate.run(
            () => _verifyAndExtract(zipPath, expected, installDir));
      } finally {
        await File(zipPath).delete();
      }

      if (!Platform.isWindows) {
        await Process.run('chmod', ['+x', exe]);
      }
      await marker.create();
    } on StartupFailure catch (e) {
      log.write('Unpacking failed: $e');
      rethrow;
    } on FileSystemException catch (e) {
      log.write('Unpacking failed: $e');
      throw StartupFailure(
        causeOfUnpackError(e.osError?.errorCode),
        'Could not unpack the backend to $installDir: $e',
        folder: installDir,
      );
    } catch (e) {
      log.write('Unpacking failed: $e');
      throw StartupFailure(
        StartupCause.unpackFailed,
        'Could not unpack the backend to $installDir: $e',
        folder: installDir,
      );
    }
    log.write('Unpacked in '
        '${DateTime.now().difference(started).inMilliseconds / 1000} s');

    // Antivirus software often removes a file it dislikes right after it has
    // been written, before anything gets to run it.
    if (!await File(exe).exists()) {
      log.write('Backend executable vanished right after unpacking');
      throw StartupFailure(
        StartupCause.filesMissing,
        'The backend executable $exe was removed right after it was unpacked.',
        folder: installDir,
      );
    }

    // Folders of earlier builds. One may still be in use by a stray backend
    // process; it is simply left for the next start to remove.
    await for (final entry in Directory(root).list()) {
      if (p.equals(entry.path, installDir)) continue;
      try {
        await entry.delete(recursive: true);
      } on FileSystemException {
        // still locked
      }
    }
    return exe;
  }

  /// Check the archive, extract it, and write [_manifestName]: one
  /// `size<TAB>path` line per file, for [_missingFiles].
  static Future<void> _verifyAndExtract(
    String zipPath,
    String expectedSha256,
    String outDir,
  ) async {
    final actual =
        (await sha256.bind(File(zipPath).openRead()).first).toString();
    if (actual != expectedSha256) {
      throw StartupFailure(
        StartupCause.installDamaged,
        'The bundled backend is damaged (SHA256 $actual, expected '
        '$expectedSha256).',
      );
    }

    // Not archive's extractFileToDisk: it swallows write errors, and a
    // half-written backend fails later in ways that are hard to trace.
    final manifest = StringBuffer();
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        final name = p.normalize(entry.name);
        final path = p.join(outDir, name);
        if (!p.isWithin(outDir, path)) {
          throw StartupFailure(
            StartupCause.installDamaged,
            'The bundled backend contains an invalid path: ${entry.name}',
          );
        }
        Directory(p.dirname(path)).createSync(recursive: true);
        final output = OutputFileStream(path);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
        manifest.writeln('${entry.size}\t$name');
        entry.clear();
      }
    } finally {
      input.closeSync();
    }
    File(p.join(outDir, _manifestName)).writeAsStringSync(manifest.toString());
  }

  /// Prefer a `backend/.venv` interpreter if one has been set up (the usual
  /// `python -m venv .venv && pip install -r requirements.txt` dev flow);
  /// otherwise fall back to whatever `python`/`python3` resolves to on PATH.
  static String _debugExecutable(String backendDir) {
    final venvPython = Platform.isWindows
        ? p.join(backendDir, '.venv', 'Scripts', 'python.exe')
        : p.join(backendDir, '.venv', 'bin', 'python3');
    if (File(venvPython).existsSync()) return venvPython;
    return Platform.isWindows ? 'python' : 'python3';
  }

  static List<String> _buildArgs(int port, String host, String? logFile) => [
        // In debug mode we launch `python main.py` from the backend directory
        if (kDebugMode) 'main.py',
        '--host',
        host,
        '--port',
        '$port',
        if (logFile != null) ...['--log-file', logFile],
      ];

  /// Walk up from [Directory.current] looking for `backend/main.py`.
  /// Supports a --dart-define override for non-standard layouts.
  static String? _findBackendDir() {
    const override = String.fromEnvironment('DIAGNOSTIC_BACKEND_DIR');
    if (override.isNotEmpty) return override;

    var dir = Directory.current;
    for (var i = 0; i < 6; i++) {
      final candidate = p.join(dir.path, 'backend');
      if (File(p.join(candidate, 'main.py')).existsSync()) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // filesystem root
      dir = parent;
    }
    return null;
  }
}

// ── notifier ──────────────────────────────────────────────────────────────────

/// ChangeNotifier wrapping [BackendManager]; drives the go_router redirect.
class BackendNotifier extends ChangeNotifier {
  BackendNotifier(this._manager, this._config) {
    _manager.onPhase = (phase) {
      _phase = phase;
      notifyListeners();
    };
    _run(_start);
  }

  final BackendManager _manager;
  final AppConfig _config;

  BackendStatus _status = BackendStatus.starting;
  BackendPhase _phase = BackendPhase.launching;
  StartupFailure? _failure;
  bool _waitingInBackground = false;

  BackendStatus get status => _status;
  BackendPhase get phase => _phase;

  /// Why the backend is not running, while [status] is error.
  StartupFailure? get failure => _failure;

  /// Whether a backend that timed out is still being waited for, so the
  /// error screen may yet give way to the app on its own.
  bool get waitingInBackground => _waitingInBackground;

  /// Proxied so widgets can build API URLs without holding a BackendManager ref.
  String get baseUrl => _manager.baseUrl;

  Future<void> retry() => _run(_start);

  /// Kill the backend, unpack it again and start it.
  Future<void> repair() => _run(() async {
        await _manager.repair();
        await _start();
      });

  Future<Directory> get logDirectory => _manager.log.directory;

  /// Plain-text summary of the failure, for the user to send on.
  Future<String> diagnosticReport() async {
    var version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // leave it unknown
    }
    return buildDiagnosticReport(
      failure: _failure ??
          const StartupFailure(StartupCause.unknown, 'No failure recorded.'),
      appVersion: '$version (${kDebugMode ? 'debug' : 'release'})',
      osVersion:
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      appLog: await _manager.log.tail(StartupLog.appLogName),
      backendLog: await _manager.log.tail(StartupLog.backendLogName),
      now: DateTime.now(),
    );
  }

  Future<void> _start() => _manager.start(
        host: _config.backendHost,
        port: _config.backendFixedPort,
        startupTimeoutSeconds: _config.backendStartupTimeoutSeconds,
      );

  Future<void> _run(Future<void> Function() body) async {
    _status = BackendStatus.starting;
    _phase = BackendPhase.launching;
    _failure = null;
    _waitingInBackground = false;
    notifyListeners();
    try {
      await body();
      _status = BackendStatus.ready;
    } on BackendSuperseded {
      return;
    } catch (e) {
      _status = BackendStatus.error;
      _failure = _asFailure(e);
    }
    notifyListeners();
    if (_status == BackendStatus.error && _manager.isRunning) {
      unawaited(_keepWaiting());
    }
  }

  Future<void> _keepWaiting() async {
    _waitingInBackground = true;
    notifyListeners();
    try {
      await _manager.keepWaiting();
      _status = BackendStatus.ready;
      _failure = null;
    } on BackendSuperseded {
      return;
    } catch (e) {
      _failure = _asFailure(e);
    }
    _waitingInBackground = false;
    notifyListeners();
  }

  StartupFailure _asFailure(Object e) {
    if (e is StartupFailure) return e;
    _manager.log.write('Unexpected startup error: $e');
    return StartupFailure(StartupCause.unknown, '$e');
  }
}
