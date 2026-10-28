import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The log files that let someone find out afterwards why the backend did not
/// start, on machines where nobody watches a console.
///
/// Two files, since two processes write them: `app.log` holds this app's
/// startup steps (unpacking, executable, port, timings, exit codes) and
/// anything the backend writes to its pipes; `backend.log` is written by the
/// backend itself (`--log-file`). Each app start moves the previous run's
/// files to `*.prev.log`, so a restart does not wipe the evidence.
class StartupLog {
  StartupLog({Future<Directory> Function()? baseDirectory})
      : _baseDirectory = baseDirectory ?? getApplicationSupportDirectory;

  static const appLogName = 'app.log';
  static const backendLogName = 'backend.log';

  final Future<Directory> Function() _baseDirectory;
  Future<Directory>? _dir;

  /// Lines logged before the folder was ready, written out once it is.
  final _pending = <String>[];
  File? _appLog;

  /// The log folder, created and rotated on first use.
  Future<Directory> get directory => _dir ??= _open();

  Future<File> get backendLogFile async =>
      File(p.join((await directory).path, backendLogName));

  Future<Directory> _open() async {
    final dir = Directory(p.join((await _baseDirectory()).path, 'logs'));
    await dir.create(recursive: true);
    for (final name in [appLogName, backendLogName]) {
      final file = File(p.join(dir.path, name));
      final prev =
          File(p.join(dir.path, name.replaceFirst('.log', '.prev.log')));
      try {
        if (await prev.exists()) await prev.delete();
        if (await file.exists()) await file.rename(prev.path);
      } on FileSystemException {
        // Still held open, e.g. by a backend left over from the last run:
        // keep appending to it rather than fail the start over a log.
      }
    }
    _appLog = File(p.join(dir.path, appLogName));
    final pending = List.of(_pending);
    _pending.clear();
    pending.forEach(_append);
    return dir;
  }

  /// Append a timestamped line to `app.log` (and the debug console).
  void write(String message) {
    final line = '${DateTime.now().toIso8601String()}  $message';
    if (kDebugMode) debugPrint(line);
    if (_appLog == null) {
      _pending.add(line);
    } else {
      _append(line);
    }
  }

  void _append(String line) {
    try {
      // Synchronous and flushed: the app may be killed right after a
      // failure, and these are a handful of short lines per start.
      _appLog!.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } on FileSystemException {
      // nowhere left to report it
    }
  }

  /// The last [lines] lines of [name] in the log folder, or '' if it does not
  /// exist (yet).
  Future<String> tail(String name, {int lines = 80}) async {
    try {
      final file = File(p.join((await directory).path, name));
      if (!await file.exists()) return '';
      return tailOf(await file.readAsString(), lines);
    } on FileSystemException catch (e) {
      return '(could not read $name: ${e.message})';
    }
  }

  /// The last [lines] lines of [text].
  static String tailOf(String text, int lines) {
    final all = const LineSplitter().convert(text);
    return all.skip(max(0, all.length - lines)).join('\n');
  }
}
