import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../services/csv_service.dart';
import '../services/session_log_service.dart';
import '../theme/app_theme.dart';

/// Shows the location of `app_config.yaml`, lets the user open it in their
/// system default editor, and reload it into [AppConfigNotifier] without
/// restarting the app. Also shows where session CSV logs are written, what
/// they add up to, and which version of the app is running.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _configPath;
  String? _csvDirPath;
  SessionLogSummary? _logSummary;
  String? _appVersion;
  bool _reloading = false;
  String? _statusMessage;
  bool _statusIsError = false;

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
    final path = await notifier.configFilePath();
    final csvDir = await const CsvService().logDirectory(notifier.config);
    // Reads every log in the folder, so it is kept out of the path lookup's
    // setState: the folder shows up straight away and the totals follow.
    final summary =
        await const SessionLogService().summarize(config: notifier.config);
    if (!mounted) return;
    setState(() {
      _configPath = path;
      _csvDirPath = csvDir.path;
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
      if (Platform.isWindows) {
        // 'start' is a cmd.exe builtin; the empty title arg avoids it being
        // misread as the window title when the path contains spaces/quotes.
        await Process.run('cmd', ['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
      _setStatus('Opened $path in the default editor.');
    } catch (e) {
      _setStatus('Could not open editor: $e', isError: true);
    }
  }

  /// Opens the session-log directory in the platform file manager, creating
  /// it first — it does not exist until the first prediction is logged.
  Future<void> _openCsvFolder() async {
    final path = _csvDirPath;
    if (path == null) return;

    try {
      await Directory(path).create(recursive: true);
      if (Platform.isWindows) {
        // explorer.exe exits non-zero even when it opened the window, so its
        // exit code says nothing about success.
        await Process.run('explorer', [path]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else {
        await Process.run('xdg-open', [path]);
      }
      _setStatus('Opened $path.');
    } catch (e) {
      _setStatus('Could not open folder: $e', isError: true);
    }
  }

  Future<void> _reloadConfig() async {
    setState(() {
      _reloading = true;
      _statusMessage = null;
    });
    try {
      await context.read<AppConfigNotifier>().reload();
      // output_path may have moved the logs elsewhere.
      await _loadPaths();
      _setStatus('Config reloaded.');
    } catch (e) {
      _setStatus('Failed to reload config: $e', isError: true);
    } finally {
      if (mounted) setState(() => _reloading = false);
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfigNotifier>().config;
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
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 16),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _statusIsError
                                      ? Icons.error_outline
                                      : Icons.check_circle_outline,
                                  size: 16,
                                  color: _statusIsError
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _statusMessage!,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: _statusIsError
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                          '${config.backendHost}:${config.backendPort}',
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
