import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../models/model_configuration.dart';
import '../services/api_service.dart';
import '../services/backend_manager.dart';
import '../services/model_config_notifier.dart';
import '../theme/app_theme.dart';
import 'configuration_screen.dart';

/// Lets the user pick a `.pkcls` Orange model file (or reopen a recently
/// used one), loads it on the backend, and – on success – navigates to
/// [ConfigurationScreen] with the resulting domain.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _modelPath;
  bool _loading = false;
  String? _error;

  Future<void> _pickModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pkcls'],
      dialogTitle: 'Select an Orange model file',
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    await _loadModel(path);
  }

  Future<void> _loadModel(String path) async {
    setState(() {
      _loading = true;
      _error = null;
      _modelPath = path;
    });

    try {
      final domain = await context.read<ApiService>().loadModel(path);
      if (!mounted) return;
      await context.read<ModelConfigNotifier>().recordOpened(path);
      if (!mounted) return;
      setState(() => _loading = false);
      context.push(
        '/configuration',
        extra: ConfigurationScreenArgs(domain: domain, modelPath: path),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfigNotifier>().config;
    final notifier = context.watch<BackendNotifier>();
    final recentModels =
        context.watch<ModelConfigNotifier>().recentModels.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.monitor_heart_outlined,
                size: 22, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text(config.appTitle),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Scrollbar(
        child: SingleChildScrollView(
          padding: AppSpacing.page,
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSpacing.contentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  _Hero(
                    loading: _loading,
                    onPickModel: _pickModel,
                    baseUrl: notifier.baseUrl,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _ErrorBanner(message: _error!),
                  ] else if (_modelPath != null && !_loading) ...[
                    const SizedBox(height: 12),
                    Text(
                      _modelPath!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 36),
                  if (recentModels.isNotEmpty) ...[
                    const SectionHeader(
                      title: 'Recent models',
                      subtitle: 'Reopen a model and its saved configuration.',
                    ),
                    Card(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < recentModels.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 60),
                            _RecentModelTile(
                              entry: recentModels[i],
                              enabled: !_loading,
                              onTap: () => _loadModel(recentModels[i].path),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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

/// The welcome panel: what the app does, the primary action, and a quiet
/// confirmation that the diagnostic engine is up.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.loading,
    required this.onPickModel,
    required this.baseUrl,
  });

  final bool loading;
  final VoidCallback onPickModel;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius + 6),
        border: Border.all(color: scheme.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.10),
            scheme.primary.withValues(alpha: 0.02),
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(Icons.medical_services_outlined,
                size: 30, color: scheme.onPrimary),
          ),
          const SizedBox(height: 24),
          Text(
            'Ready when you are',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              'Open an Orange model to build a data-entry form for it, then '
              'run predictions and record your own evaluation for each case.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: loading ? null : onPickModel,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open_outlined, size: 20),
            label: Text(loading ? 'Loading model…' : 'Open model (.pkcls)'),
          ),
          const SizedBox(height: 24),
          _StatusPill(baseUrl: baseUrl),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.baseUrl});

  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const green = Color(0xFF16A34A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: green.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 8,
            width: 8,
            decoration: const BoxDecoration(
              color: green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Engine running · $baseUrl',
            style: theme.textTheme.labelMedium?.copyWith(color: green),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not load that model',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentModelTile extends StatelessWidget {
  const _RecentModelTile({
    required this.entry,
    required this.enabled,
    required this.onTap,
  });

  final ModelConfigEntry entry;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = entry.configuration != null;
    return ListTile(
      enabled: enabled,
      leading: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.insert_drive_file_outlined,
            size: 18, color: theme.colorScheme.primary),
      ),
      title: Text(p.basename(entry.path), style: theme.textTheme.titleSmall),
      subtitle: Text(
        configured
            ? '${entry.configuration!.groups.length} groups configured'
            : 'Not configured yet',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(Icons.chevron_right,
          color: theme.colorScheme.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
