import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';

/// Shows the location of `app_config.yaml`, lets the user open it in their
/// system default editor, and reload it into [AppConfigNotifier] without
/// restarting the app.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _configPath;
  bool _reloading = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    final path = await context.read<AppConfigNotifier>().configFilePath();
    if (!mounted) return;
    setState(() => _configPath = path);
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

  Future<void> _reloadConfig() async {
    setState(() {
      _reloading = true;
      _statusMessage = null;
    });
    try {
      await context.read<AppConfigNotifier>().reload();
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
    final config = context.watch<AppConfigNotifier>().config;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Config file',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _configPath ?? 'Locating app_config.yaml…',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _configPath == null ? null : _openInEditor,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Open in editor'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _reloading ? null : _reloadConfig,
                      icon: _reloading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_reloading ? 'Reloading…' : 'Reload config'),
                    ),
                  ],
                ),
                if (_statusMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _statusMessage!,
                    style: TextStyle(
                      color: _statusIsError
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                Text(
                  'Current values',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        _ConfigRow('Title', config.appTitle),
                        _ConfigRow('Theme', config.appTheme),
                        _ConfigRow(
                          'Backend',
                          '${config.backendHost}:${config.backendPort}',
                        ),
                        _ConfigRow(
                          'Result display style',
                          config.resultDisplayStyle,
                        ),
                        _ConfigRow(
                          'CSV logging',
                          config.csvLoggingEnabled ? 'enabled' : 'disabled',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
