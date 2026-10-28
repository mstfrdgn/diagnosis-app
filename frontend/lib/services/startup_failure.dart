import 'dart:convert';

/// Why the backend did not start, worked out from what the startup could
/// observe, with an explanation for people who will never read a log.
enum StartupCause {
  /// Files of the unpacked backend are gone, typically quarantined.
  filesMissing,

  /// Windows refused to run or write a file because it looked infected.
  antivirusBlocked,

  /// The process was refused or killed before Python even ran.
  securityPolicy,

  /// The backend ran and crashed during startup.
  crashed,

  /// Alive, but never got as far as listening.
  notResponding,

  /// Listening, by its own log, yet the app's requests do not get through.
  connectionBlocked,

  /// Every port tried was taken.
  portUnavailable,

  diskFull,
  noWriteAccess,
  unpackFailed,

  /// The bundled archive does not match its checksum.
  installDamaged,

  /// Debug builds only: no backend source tree to run.
  devSetup,
  unknown,
}

class StartupFailure implements Exception {
  const StartupFailure(this.cause, this.detail, {this.folder, this.output});

  final StartupCause cause;

  /// The technical account: what failed, with paths, codes and timings.
  final String detail;

  /// The folder the backend lives in, where the advice names one.
  final String? folder;

  /// The backend output quoted in [detail], if any.
  final String? output;

  /// Whether the process is still running when this is reported, so that it
  /// may yet come up on its own.
  bool get mayStillStart =>
      cause == StartupCause.notResponding ||
      cause == StartupCause.connectionBlocked;

  String get title => switch (cause) {
        StartupCause.filesMissing => 'Some program files are missing',
        StartupCause.antivirusBlocked => 'Blocked by antivirus software',
        StartupCause.securityPolicy => 'Blocked by a security setting',
        StartupCause.crashed => 'The diagnostic engine stopped unexpectedly',
        StartupCause.notResponding => 'The diagnostic engine is not responding',
        StartupCause.connectionBlocked =>
          'The app cannot connect to its diagnostic engine',
        StartupCause.portUnavailable => 'No free connection port',
        StartupCause.diskFull => 'Not enough disk space',
        StartupCause.noWriteAccess => 'The app cannot save its files',
        StartupCause.unpackFailed => 'The app could not prepare its files',
        StartupCause.installDamaged => 'The installation is damaged',
        StartupCause.devSetup => 'Backend source not found',
        StartupCause.unknown => 'The diagnostic engine could not start',
      };

  String get explanation => switch (cause) {
        StartupCause.filesMissing =>
          'Part of the diagnostic engine was removed after it was set up. '
              'Antivirus software usually does this when it does not '
              'recognise a file.',
        StartupCause.antivirusBlocked =>
          'Your antivirus software stopped the diagnostic engine because it '
              'did not recognise it.',
        StartupCause.securityPolicy =>
          'Windows did not allow the diagnostic engine to run. On work or '
              'university computers this is often caused by a security '
              'policy.',
        StartupCause.crashed =>
          'The diagnostic engine closed while it was starting.',
        StartupCause.notResponding =>
          'The diagnostic engine is running but has not finished starting. '
              'Antivirus software checking its files can slow this down a '
              'lot. The app keeps waiting and continues on its own if the '
              'engine starts.',
        StartupCause.connectionBlocked =>
          'The diagnostic engine started, but the app cannot reach it. '
              'Antivirus or firewall software that checks network traffic '
              'can block this, even though both run on this computer.',
        StartupCause.portUnavailable =>
          'The app could not find a free local connection port for its '
              'diagnostic engine.',
        StartupCause.diskFull =>
          'The app needs a few hundred MB of free space to set up its '
              'diagnostic engine.',
        StartupCause.noWriteAccess =>
          'The app was not allowed to save the files of its diagnostic '
              'engine.',
        StartupCause.unpackFailed =>
          'Setting up the diagnostic engine failed while copying its files.',
        StartupCause.installDamaged =>
          'The app\'s own files do not match what was installed.',
        StartupCause.devSetup => detail,
        StartupCause.unknown =>
          'Something unexpected went wrong while starting the diagnostic '
              'engine.',
      };

  String get suggestion {
    final where = folder == null ? '' : ' (folder: $folder)';
    return switch (cause) {
      StartupCause.filesMissing =>
        'Click Repair to restore the files. If this happens again, ask your '
            'IT support to add an antivirus exception for this app$where, '
            'or reinstall the app.',
      StartupCause.antivirusBlocked =>
        'Ask your IT support to add an antivirus exception for this '
            'app$where, then click Repair.',
      StartupCause.securityPolicy =>
        'Contact your IT support and tell them this app\'s engine is being '
            'blocked. Use "Copy diagnostic report" and send them the result.',
      StartupCause.crashed =>
        'Click Repair. If that does not help, reinstall the app and send the '
            'diagnostic report to whoever gave you the app.',
      StartupCause.notResponding =>
        'Wait a few more minutes. If nothing changes, click Repair. If it '
            'still does not start, ask your IT support whether antivirus '
            'software is checking this app.',
      StartupCause.connectionBlocked =>
        'Ask your IT support to allow this app to connect to 127.0.0.1 '
            '(this computer) in the antivirus or firewall settings.',
      StartupCause.portUnavailable =>
        'Restart the computer and open the app again.',
      StartupCause.diskFull => 'Free up some disk space, then click Retry.',
      StartupCause.noWriteAccess =>
        'Ask your IT support for write access$where. Security software may '
            'also be blocking it.',
      StartupCause.unpackFailed => 'Click Repair. If that does not help, '
          'reinstall the app.',
      StartupCause.installDamaged => 'Please reinstall the app.',
      StartupCause.devSetup => 'See the technical details below.',
      StartupCause.unknown => 'Click Retry or Repair. If that does not help, '
          'send the diagnostic report to whoever gave you the app.',
    };
  }

  @override
  String toString() => detail;
}

// ── classification ───────────────────────────────────────────────────────────

/// Win32 error codes that come back from starting or writing a file.
abstract final class _Win32 {
  static const fileNotFound = 2;
  static const pathNotFound = 3;
  static const accessDenied = 5;
  static const handleDiskFull = 39;
  static const diskFull = 112;
  static const virusInfected = 225;
  static const virusDeleted = 226;
  static const accessDisabledByPolicy = 1260;
  static const appControlPolicy = 4551;
}

/// errno values with the same meaning on Linux and macOS.
abstract final class _Errno {
  static const eperm = 1;
  static const eacces = 13;
  static const enospc = 28;
}

/// Cause of an OS error from `Process.start`.
StartupCause causeOfLaunchError(int errorCode) => switch (errorCode) {
      _Win32.fileNotFound || _Win32.pathNotFound => StartupCause.filesMissing,
      _Win32.virusInfected ||
      _Win32.virusDeleted =>
        StartupCause.antivirusBlocked,
      _Win32.accessDenied ||
      _Win32.accessDisabledByPolicy ||
      _Win32.appControlPolicy ||
      _Errno.eacces ||
      _Errno.eperm =>
        StartupCause.securityPolicy,
      _ => StartupCause.unknown,
    };

/// Cause of an OS error while unpacking the bundle.
StartupCause causeOfUnpackError(int? errorCode) => switch (errorCode) {
      _Win32.diskFull ||
      _Win32.handleDiskFull ||
      _Errno.enospc =>
        StartupCause.diskFull,
      _Win32.virusInfected ||
      _Win32.virusDeleted =>
        StartupCause.antivirusBlocked,
      _Win32.accessDenied ||
      _Errno.eacces ||
      _Errno.eperm =>
        StartupCause.noWriteAccess,
      _ => StartupCause.unpackFailed,
    };

/// NTSTATUS codes a process can exit with when Windows stops it.
const _statusAccessDenied = 0xC0000022;
const _statusDllNotFound = 0xC0000135;

/// Whether the backend's [output] says it failed to bind its port, which is
/// the one exit that makes trying another port worthwhile.
bool isBindError(String output) {
  final lower = output.toLowerCase();
  return lower.contains('error while attempting to bind') ||
      lower.contains('address already in use') ||
      lower.contains('errno 10048') ||
      lower.contains('errno 98');
}

/// Cause of the backend exiting with [exitCode] before it was ready, given
/// what it wrote meanwhile and whether all its files are still there.
StartupCause causeOfExit({
  required int exitCode,
  required String output,
  required bool filesIntact,
}) {
  if (!filesIntact) return StartupCause.filesMissing;
  final status = exitCode & 0xFFFFFFFF;
  if (status == _statusAccessDenied) return StartupCause.securityPolicy;
  if (status == _statusDllNotFound) return StartupCause.filesMissing;
  // The backend logs a line as the very first thing it does; a process that
  // died without one never got to run its own code.
  if (output.trim().isEmpty) return StartupCause.securityPolicy;
  return StartupCause.crashed;
}

/// Cause of the backend still running but not answering in time.
StartupCause causeOfTimeout({
  required String output,
  required bool filesIntact,
}) {
  if (!filesIntact) return StartupCause.filesMissing;
  // uvicorn logs this once its socket is listening.
  if (output.contains('Uvicorn running on')) {
    return StartupCause.connectionBlocked;
  }
  return StartupCause.notResponding;
}

// ── report ───────────────────────────────────────────────────────────────────

/// Plain-text report for the clipboard: enough for someone else to tell what
/// happened without access to the machine.
String buildDiagnosticReport({
  required StartupFailure failure,
  required String appVersion,
  required String osVersion,
  required String appLog,
  required String backendLog,
  required DateTime now,
}) {
  String section(String name, String body) =>
      '--- $name ---\n${body.trim().isEmpty ? '(empty)' : body.trim()}\n';
  return [
    'Diagnostic report',
    'Generated:   ${now.toIso8601String()}',
    'App version: $appVersion',
    'OS:          $osVersion',
    'Cause:       ${failure.cause.name} - ${failure.title}',
    '',
    section('details', failure.detail),
    section('app log (end)', appLog),
    section('backend log (end)', _withoutQuoted(backendLog, failure.output)),
  ].join('\n');
}

/// [log] without the lines at its end that [quoted] ends with too, i.e. what
/// the details already show.
String _withoutQuoted(String log, String? quoted) {
  if (quoted == null || quoted.trim().isEmpty) return log;
  final logLines = const LineSplitter().convert(log.trimRight());
  final quotedLines = const LineSplitter().convert(quoted.trimRight());
  var same = 0;
  while (same < logLines.length &&
      same < quotedLines.length &&
      logLines[logLines.length - 1 - same].trimRight() ==
          quotedLines[quotedLines.length - 1 - same].trimRight()) {
    same++;
  }
  if (same == 0) return log;
  return [
    ...logLines.take(logLines.length - same),
    '(last $same lines omitted: shown in the details above)',
  ].join('\n');
}
