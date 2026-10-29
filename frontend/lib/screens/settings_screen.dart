import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../services/backend_manager.dart';
import '../services/csv_service.dart';
import '../services/folder_opener.dart' as folder_opener;
import '../services/session_log_service.dart';
import '../theme/app_theme.dart';

/// Shows the location of `app_config.yaml`, lets the user open it in their
/// system default editor, and reload it into [AppConfigNotifier] without
/// restarting the app. Also shows where session CSV logs are written, what
/// they add up to, where the app and backend logs are, and which version of
/// the app is running.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.openFolder = folder_opener.openFolder,
    this.openInEditor = _openInDefaultEditor,
  });

  /// Opens a folder in the platform file manager; replaced in tests.
  final Future<void> Function(String path) openFolder;

  /// Opens a file in the system default editor; replaced in tests.
  final Future<void> Function(String path) openInEditor;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

Future<void> _openInDefaultEditor(String path) async {
  if (Platform.isWindows) {
    // 'start' is a cmd.exe builtin; the empty title arg avoids it being
    // misread as the window title when the path contains spaces/quotes.
    await Process.run('cmd', ['/c', 'start', '', path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    await Process.run('xdg-open', [path]);
  }
}

/// The cards on the screen whose buttons report back.
enum _SettingsCard { config, sessionLogs, appLogs }

class _SettingsScreenState extends State<SettingsScreen> {
  String? _configPath;
  String? _csvDirPath;
  String? _appLogDirPath;
  SessionLogSummary? _logSummary;
  String? _appVersion;
  bool _reloading = false;
  /// The outcome of the last button pressed, shown in that button's card.
  ({_SettingsCard card, String message, bool isError})? _status;

  /// Shared by the [Scrollbar] and the body it wraps; see the note in
  /// `home_screen.dart` for why the fallback controller will not do.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadPaths();
    _loadVersion();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPaths() async {
    final notifier = context.read<AppConfigNotifier>();
    final backend = context.read<BackendNotifier?>();
    final path = await notifier.configFilePath();
    final csvDir = await const CsvService().logDirectory(notifier.config);
    final appLogDir = await backend?.logDirectory;
    // Reads every log in the folder, so it is kept out of the path lookup's
    // setState: the folder shows up straight away and the totals follow.
    final summary =
        await const SessionLogService().summarize(config: notifier.config);
    if (!mounted) return;
    setState(() {
      _configPath = path;
      _csvDirPath = csvDir.path;
      _appLogDirPath = appLogDir?.path;
      _logSummary = summary;
    });
  }

  /// The running build's version. Comes from the platform's own package
  /// metadata, which the Windows/macOS runners stamp from `pubspec.yaml`.
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final build = info.buildNumber;
      setState(() => _appVersion =
          build.isEmpty ? info.version : '${info.version}+$build');
    } catch (e) {
      if (!mounted) return;
      setState(() => _appVersion = 'Unavailable ($e)');
    }
  }

  Future<void> _openInEditor() async {
    final path = _configPath;
    if (path == null) return;

    try {
      await widget.openInEditor(path);
      _setStatus(_SettingsCard.config, 'Opened $path in the default editor.');
    } catch (e) {
      _setStatus(_SettingsCard.config, 'Could not open editor: $e',
          isError: true);
    }
  }

  /// Opens the session-log directory in the platform file manager, creating
  /// it first — it does not exist until the first prediction is logged.
  Future<void> _openCsvFolder() async {
    final path = _csvDirPath;
    if (path == null) return;

    try {
      await Directory(path).create(recursive: true);
      await widget.openFolder(path);
      _setStatus(_SettingsCard.sessionLogs, 'Opened $path.');
    } catch (e) {
      _setStatus(_SettingsCard.sessionLogs, 'Could not open folder: $e',
          isError: true);
    }
  }

  /// Opens the folder holding `app.log` and `backend.log`. On macOS it sits
  /// under ~/Library, which Finder hides, so this is the way users find it.
  Future<void> _openAppLogFolder() async {
    final path = _appLogDirPath;
    if (path == null) return;

    try {
      await widget.openFolder(path);
      _setStatus(_SettingsCard.appLogs, 'Opened $path.');
    } catch (e) {
      _setStatus(_SettingsCard.appLogs, 'Could not open folder: $e',
          isError: true);
    }
  }

  Future<void> _reloadConfig() async {
    setState(() {
      _reloading = true;
      _status = null;
    });
    try {
      await context.read<AppConfigNotifier>().reload();
      // output_path may have moved the logs elsewhere.
      await _loadPaths();
      _setStatus(_SettingsCard.config, 'Config reloaded.');
    } catch (e) {
      _setStatus(_SettingsCard.config, 'Failed to reload config: $e',
          isError: true);
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  void _setStatus(_SettingsCard card, String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() => _status = (card: card, message: message, isError: isError));
  }

  /// The status line for [card], spaced to sit under its buttons, if the
  /// last message belongs to it.
  List<Widget> _statusIn(_SettingsCard card) {
    final status = _status;
    if (status == null || status.card != card) return const [];
    return [
      const SizedBox(height: 16),
      _StatusLine(message: status.message, isError: status.isError),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfigNotifier>().config;
    // Nullable so the screen also renders where no backend is provided.
    final backend = context.watch<BackendNotifier?>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: AppSpacing.page,
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(
                    title: 'Configuration file',
                    subtitle:
                        'Edit this YAML to change app-wide behaviour, then '
                        'reload it without restarting.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text('app_config.yaml',
                                  style: theme.textTheme.titleSmall),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            _configPath ?? 'Locating app_config.yaml…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed:
                                    _configPath == null ? null : _openInEditor,
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                label: const Text('Open in editor'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _reloading ? null : _reloadConfig,
                                icon: _reloading
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh, size: 20),
                                label: Text(
                                    _reloading ? 'Reloading…' : 'Reload'),
                              ),
                            ],
                          ),
                          ..._statusIn(_SettingsCard.config),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SectionHeader(
                    title: 'Session logs',
                    subtitle: config.csvLoggingEnabled
                        ? 'Every prediction is appended to a CSV in this '
                            'folder — one file per model.'
                        : 'CSV logging is disabled in app_config.yaml; '
                            'nothing is being written.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_outlined,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text('CSV folder',
                                  style: theme.textTheme.titleSmall),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            _csvDirPath ?? 'Locating the log folder…',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 16),
                          _LogSummary(summary: _logSummary),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed:
                                _csvDirPath == null ? null : _openCsvFolder,
                            icon: const Icon(Icons.folder_open_outlined,
                                size: 20),
                            label: const Text('Open folder'),
                          ),
                          ..._statusIn(_SettingsCard.sessionLogs),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SectionHeader(
                    title: 'App logs',
                    subtitle: 'What the app and its backend did at startup. '
                        'Send these files along when reporting a problem.',
                  ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.folder_outlined,
                                  size: 18,
                                  color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 8),
                              Text('Log folder',
                                  style: theme.textTheme.titleSmall),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            _appLogDirPath ??
                                (backend == null
                                    ? 'Not available without a backend.'
                                    : 'Locating the log folder…'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                            onPressed: _appLogDirPath == null
                                ? null
                                : _openAppLogFolder,
                            icon: const Icon(Icons.folder_open_outlined,
                                size: 20),
                            label: const Text('Open log folder'),
                          ),
                          ..._statusIn(_SettingsCard.appLogs),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SectionHeader(title: 'Current values'),
                  Card(
                    child: Column(
                      children: [
                        _ConfigRow('Title', config.appTitle),
                        const Divider(height: 1, indent: 20, endIndent: 20),
                        _ConfigRow('Theme', config.appTheme),
                        const Divider(height: 1, indent: 20, endIndent: 20),
                        _ConfigRow(
                          'Backend',
                          // The port is picked at startup unless fixed in
                          // the config, so only the running one is accurate.
                          backend?.baseUrl ?? config.backendHost,
                        ),
                        const Divider(height: 1, indent: 20, endIndent: 20),
                        _ConfigRow(
                          'Probabilities',
                          config.resultDisplayShowProbability
                              ? 'shown'
                              : 'hidden',
                        ),
                        const Divider(height: 1, indent: 20, endIndent: 20),
                        _ConfigRow(
                          'CSV logging',
                          config.csvLoggingEnabled ? 'enabled' : 'disabled',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  const SectionHeader(
                    title: 'App version',
                    subtitle: 'The build of the app you are running. Quote it '
                        'when reporting a problem.',
                  ),
                  Card(
                    child: Column(
                      children: [
                        _ConfigRow(
                          'Version',
                          _appVersion ?? 'Reading version…',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the log folder holds, as one line under its path: how many per-model
/// logs are in it, how many sessions they add up to, and how many batch runs
/// sit beside them.
class _LogSummary extends StatelessWidget {
  const _LogSummary({required this.summary});

  /// Null while the folder is still being read.
  final SessionLogSummary? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final summary = this.summary;

    final (IconData icon, Color color, String text) = switch (summary) {
      null => (
          Icons.hourglass_empty,
          scheme.onSurfaceVariant,
          'Counting recorded sessions…',
        ),
      SessionLogSummary(error: final error?) => (
          Icons.error_outline,
          scheme.error,
          'Could not read the log folder: $error',
        ),
      SessionLogSummary(fileCount: 0, batchRunCount: 0) => (
          Icons.inbox_outlined,
          scheme.onSurfaceVariant,
          'No log files yet.',
        ),
      final s => (
          Icons.summarize_outlined,
          scheme.onSurfaceVariant,
          '${_count(s.fileCount, 'log file')} · '
              '${_count(s.sessionCount, 'recorded session')} · '
              '${_count(s.batchRunCount, 'batch run')}'
              '${s.unreadableFileCount == 0 ? '' : ' · '
                  '${_count(s.unreadableFileCount, 'file')} could not be '
                  'read, so its rows are not counted'}',
        ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  static String _count(int value, String noun) =>
      '$value $noun${value == 1 ? '' : 's'}';
}

/// A button's outcome: a tick and the message, or an error icon and the
/// error, both in the matching colour.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isError ? theme.colorScheme.error : theme.colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

class _ConfigRow extends StatelessWidget {
  const _ConfigRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
