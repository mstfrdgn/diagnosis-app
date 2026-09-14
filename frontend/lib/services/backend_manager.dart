import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../config/app_config.dart';

// ── status ───────────────────────────────────────────────────────────────────

enum BackendStatus { starting, ready, error }

// ── exceptions ────────────────────────────────────────────────────────────────

class BackendStartupException implements Exception {
  const BackendStartupException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ── manager ───────────────────────────────────────────────────────────────────

/// Launches, health-polls, and eventually terminates the FastAPI subprocess.
class BackendManager {
  Process? _process;
  String _host = '127.0.0.1';
  int _port = 8765;

  String get host => _host;
  int get port => _port;
  String get baseUrl => 'http://$_host:$_port';

  /// Start the backend, trying [port] then up to 4 fallback ports if busy.
  Future<void> start({
    required String host,
    required int port,
    required int startupTimeoutSeconds,
  }) async {
    _host = host;
    for (var attempt = 0; attempt < 5; attempt++) {
      final tryPort = port + attempt;
      try {
        await _launch(tryPort, startupTimeoutSeconds);
        _port = tryPort;
        return;
      } on BackendStartupException {
        _process?.kill();
        _process = null;
        if (attempt == 4) rethrow;
        // port may be occupied – let the loop try the next one
      }
    }
  }

  /// Kill the backend subprocess (entire process tree on Windows).
  Future<void> stop() async {
    if (_process == null) return;
    if (Platform.isWindows) {
      await Process.run(
        'taskkill',
        ['/F', '/T', '/PID', '${_process!.pid}'],
        runInShell: true,
      );
    } else {
      _process!.kill(ProcessSignal.sigterm);
    }
    _process = null;
  }

  // ── private ────────────────────────────────────────────────────────────────

  Future<void> _launch(int port, int timeoutSeconds) async {
    final workDir = kDebugMode ? _findBackendDir() : null;

    if (kDebugMode && workDir == null) {
      throw const BackendStartupException(
        'Cannot locate backend/main.py.\n'
        'Run "flutter run" from the diagnostic_app project root, or supply\n'
        '--dart-define=DIAGNOSTIC_BACKEND_DIR=/absolute/path/to/backend.',
      );
    }

    // A backend left over from an earlier run answers /health exactly like one
    // we started, and the readiness probe below cannot tell them apart: ours
    // dies on the bind conflict while the squatter keeps replying 200, so the
    // app would adopt whatever code that process loaded — silently, since
    // nothing about it looks unhealthy. Claim the port only if it is free.
    if (!await _isPortFree(port)) {
      throw BackendStartupException(
        'Port $port already serves a backend this app did not start.',
      );
    }

    final exe = kDebugMode ? _debugExecutable(workDir!) : _executable();
    final args = _buildArgs(port, _host);

    try {
      _process = await Process.start(
        exe,
        args,
        workingDirectory: workDir,
        // runInShell lets Windows resolve 'python' through %PATH%
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (e) {
      throw BackendStartupException('Failed to start backend process: $e');
    }

    if (kDebugMode) {
      _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((l) => debugPrint('[backend] $l'));
      _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((l) => debugPrint('[backend:err] $l'));
    }

    // Latched rather than awaited: the readiness loop has to keep polling and
    // check the exit as it goes, so it can give up the moment the process is
    // gone instead of waiting out the full timeout.
    int? exitCode;
    unawaited(_process!.exitCode.then((code) => exitCode = code));

    await _waitUntilReady(port, timeoutSeconds, () => exitCode);
  }

  /// Whether [port] can still be claimed, decided by asking the OS to bind it.
  ///
  /// An HTTP probe cannot answer this reliably: the first request out of a
  /// freshly started process routinely takes longer than any timeout short
  /// enough to keep startup snappy, and a timeout is indistinguishable from
  /// an empty port — which is precisely the reading that lets a stale backend
  /// be adopted. Binding is immediate and unambiguous.
  ///
  /// Something else can still take the port between this check and the child
  /// actually binding; that race is covered by the exit check in
  /// [_waitUntilReady], which fails the attempt over to the next port.
  Future<bool> _isPortFree(int port) async {
    try {
      final socket = await ServerSocket.bind(_host, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<void> _waitUntilReady(
    int port,
    int timeoutSeconds,
    int? Function() exitCode,
  ) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    final client = http.Client();
    try {
      while (DateTime.now().isBefore(deadline)) {
        final code = exitCode();
        if (code != null) {
          throw BackendStartupException(
            'Backend process exited with code $code before it was ready. '
            'Its output is in the debug console.',
          );
        }
        try {
          final res = await client
              .get(Uri.parse('http://$_host:$port/health'))
              .timeout(const Duration(milliseconds: 500));
          if (res.statusCode == 200) return;
        } catch (_) {
          // not ready yet – keep polling
        }
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    } finally {
      client.close();
    }
    throw BackendStartupException(
      'Backend on port $port did not respond within $timeoutSeconds s.',
    );
  }

  // ── path resolution ────────────────────────────────────────────────────────

  static String _executable() {
    // Phase 7: return path to bundled binary extracted from assets
    throw UnimplementedError(
      'Release binary not yet bundled. Use debug mode (flutter run).',
    );
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

  static List<String> _buildArgs(int port, String host) {
    if (kDebugMode) {
      // In debug mode we launch `python main.py` from the backend directory
      return ['main.py', '--host', host, '--port', '$port'];
    }
    return ['--host', host, '--port', '$port'];
  }

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
    _start();
  }

  final BackendManager _manager;
  final AppConfig _config;

  BackendStatus _status = BackendStatus.starting;
  String? _errorMessage;

  BackendStatus get status => _status;
  String? get errorMessage => _errorMessage;

  /// Proxied so widgets can build API URLs without holding a BackendManager ref.
  String get baseUrl => _manager.baseUrl;

  Future<void> retry() async {
    _status = BackendStatus.starting;
    _errorMessage = null;
    notifyListeners();
    await _start();
  }

  Future<void> _start() async {
    try {
      await _manager.start(
        host: _config.backendHost,
        port: _config.backendPort,
        startupTimeoutSeconds: _config.backendStartupTimeoutSeconds,
      );
      _status = BackendStatus.ready;
    } catch (e) {
      _status = BackendStatus.error;
      _errorMessage = e.toString();
    }
    notifyListeners();
  }
}
