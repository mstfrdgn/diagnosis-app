import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../services/csv_service.dart';
import '../theme/app_theme.dart';

/// Shows the location of `app_config.yaml`, lets the user open it in their
/// system default editor, and reload it into [AppConfigNotifier] without
/// restarting the app. Also shows where session CSV logs are written.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _configPath;
  String? _csvDirPath;
  bool _reloading = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadPaths();
  }

  Future<void> _loadPaths() async {
    final notifier = context.read<AppConfigNotifier>();
    final path = await notifier.configFilePath();
    final csvDir = await const CsvService().logDirectory(notifier.config);
    if (!mounted) return;
    setState(() {
      _configPath = path;
      _csvDirPath = csvDir.path;
    });
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
        child: SingleChildScrollView(
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
