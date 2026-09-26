import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../models/model_configuration.dart';
import '../models/model_description.dart';
import '../services/api_service.dart';
import '../services/backend_manager.dart';
import '../services/model_config_notifier.dart';
import '../theme/app_theme.dart';
import 'configuration_screen.dart';
import 'input_screen.dart';
import 'sessions_screen.dart';

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

  /// Shared by the [Scrollbar] and the body it wraps. Without an explicit
  /// controller the Scrollbar falls back to the PrimaryScrollController,
  /// which desktop platforms do not attach, so it never finds a scroll
  /// position and asserts as soon as the user scrolls.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

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

  /// Tapping a recent model that already has a saved configuration is
  /// ambiguous — the user may want to run a case, to change the setup, or just
  /// to read back its past sessions — so ask. An unconfigured model can only
  /// go one way: into the wizard.
  Future<void> _openRecent(ModelConfigEntry entry) async {
    final configuration = entry.configuration;
    if (configuration == null) {
      await _loadModel(entry.path);
      return;
    }
    final action = await _RecentModelActionDialog.show(context, entry: entry);
    if (action == null || !mounted) return;
    // Past sessions are read straight off disk from the model's path, so this
    // one skips loading the model on the backend entirely.
    if (action == _RecentModelAction.viewSessions) {
      context.push(
        '/sessions',
        extra: SessionsScreenArgs(modelPath: entry.path),
      );
      return;
    }
    await _loadModel(
      entry.path,
      startWithConfiguration:
          action == _RecentModelAction.startDiagnosis ? configuration : null,
    );
  }

  /// Renames a recent model. The new name also decides the file its future
  /// sessions are logged to; logs written under the old name stay where they
  /// are, which is why the dialog says so.
  Future<void> _renameModel(ModelConfigEntry entry) async {
    final name = await _RenameModelDialog.show(context, entry: entry);
    if (name == null || !mounted) return;
    await context.read<ModelConfigNotifier>().setDisplayName(entry.path, name);
  }

  /// Drops [entry] from the recent list. Confirmed first because the saved
  /// configuration goes with it, and rebuilding one by hand is the real cost —
  /// the model file itself is never touched.
  Future<void> _removeModel(ModelConfigEntry entry) async {
    final confirmed = await _RemoveModelDialog.show(context, entry: entry);
    if (confirmed != true || !mounted) return;
    final name = entry.effectiveName;
    await context.read<ModelConfigNotifier>().remove(entry.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $name from recent models.')),
    );
  }

  /// Loads [path] on the backend, then goes to the input screen when
  /// [startWithConfiguration] is supplied, or to the configuration wizard.
  Future<void> _loadModel(
    String path, {
    ModelConfiguration? startWithConfiguration,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _modelPath = path;
    });

    try {
      final domain = await context.read<ApiService>().loadModel(path);
      if (!mounted) return;
      // The generated summary is only kept for models that do not have one
      // yet; recordOpened never overwrites a description the user edited.
      await context
          .read<ModelConfigNotifier>()
          .recordOpened(path, autoDescription: describeModel(domain));
      if (!mounted) return;
      setState(() => _loading = false);
      if (startWithConfiguration != null) {
        context.push(
          '/input',
          extra: InputScreenArgs(
            domain: domain,
            modelPath: path,
            modelConfig: startWithConfiguration,
          ),
        );
        return;
      }
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
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
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
                              onTap: () => _openRecent(recentModels[i]),
                              onRename: () => _renameModel(recentModels[i]),
                              onRemove: () => _removeModel(recentModels[i]),
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

/// The opening panel: where the user is in the flow, what the app does with a
/// model, the primary action, and a quiet confirmation that the engine is up.
///
/// Laid out left-aligned rather than centred. A centred stack of icon,
/// headline and button reads as a product splash; this is the first step of a
/// clinical workflow, so it reads as a working header instead — the eyebrow
/// says which step it is, and the engine status sits opposite it where a
/// status belongs rather than as a footnote under the button.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.loading,
    required this.onPickModel,
    required this.baseUrl,
  });

  final bool loading;
  final VoidCallback onPickModel;
  final String baseUrl;

  /// Comfortable measure for the supporting paragraph. Left to fill the panel
  /// it would run to ~95 characters, past the point where the eye reliably
  /// finds the start of the next line.
  static const _proseWidth = 520.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(AppSpacing.radius + 6);

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          // The same surface and border a Card gets, so the panel sits on the
          // page at the same height as the list below it.
          color: theme.cardTheme.color ?? scheme.surface,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.8),
          ),
          borderRadius: radius,
        ),
        child: Stack(
          children: [
            // A soft wash of the accent colour bleeding in from the corner:
            // cheaper than a shadow, and unlike a full-panel gradient it
            // leaves the text sitting on a flat, legible surface.
            Positioned(
              top: -110,
              right: -70,
              child: IgnorePointer(
                child: Container(
                  height: 280,
                  width: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.16),
                        scheme.primary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(36, 32, 36, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // spaceBetween pushes these to opposite edges while they
                  // both fit, and drops the status onto its own line once the
                  // window is too narrow for the pair. The full-width box is
                  // what makes that work: left to shrink-wrap its children,
                  // the Wrap has no free space to distribute and the two end
                  // up side by side on the left.
                  SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 14,
                      children: [
                        const _Eyebrow(label: 'Select a model'),
                        _StatusPill(baseUrl: baseUrl),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'Start a diagnostic session',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _proseWidth),
                    child: Text(
                      'Open a trained Orange classifier and the app builds a '
                      'data-entry form from its variables — then run '
                      'predictions and record your own evaluation for each '
                      'case.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 18,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: loading ? null : onPickModel,
                        icon: loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.folder_open_outlined, size: 20),
                        label: Text(
                          loading ? 'Loading model…' : 'Open model (.pkcls)',
                        ),
                      ),
                      Text(
                        'Works with any Orange 3 classifier.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small tracked label behind an accent rule, naming the step this screen is.
class _Eyebrow extends StatelessWidget {
  const _Eyebrow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 13,
          width: 3,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        // Flexible so a very narrow window truncates the label instead of
        // overflowing the row it shares with the status pill.
        Flexible(
          child: Text(
            label.toUpperCase(),
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// "The engine answered": a live dot, the state, and the address it is on.
///
/// The address is the part a user reads out when something is wrong, so it
/// keeps its own monospaced slot behind a divider instead of running on from
/// the label.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.baseUrl});

  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The seeded scheme has no "healthy" colour, and its primary is already
    // spoken for by actions. Dark mode takes the lighter green to clear the
    // contrast floor against a dark panel.
    final green = theme.brightness == Brightness.light
        ? const Color(0xFF16A34A)
        : const Color(0xFF4ADE80);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: green.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 7,
            width: 7,
            decoration: BoxDecoration(
              color: green,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: green.withValues(alpha: 0.55),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          Text(
            'Engine running',
            style: theme.textTheme.labelMedium?.copyWith(
              color: green,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 9),
          Container(height: 11, width: 1, color: green.withValues(alpha: 0.3)),
          const SizedBox(width: 9),
          // Flexible, so a window too narrow for the whole pill ellipsises
          // the address rather than overflowing: "Engine running" is the part
          // that has to stay readable.
          Flexible(
            child: Text(
              baseUrl,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: green.withValues(alpha: 0.9),
                fontFamily: 'monospace',
              ),
            ),
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

/// What the user chose to do with an already-configured recent model.
enum _RecentModelAction { startDiagnosis, reconfigure, viewSessions }

/// Asked when a recent model already has a saved configuration.
class _RecentModelActionDialog extends StatelessWidget {
  const _RecentModelActionDialog({required this.entry});

  final ModelConfigEntry entry;

  static Future<_RecentModelAction?> show(
    BuildContext context, {
    required ModelConfigEntry entry,
  }) {
    return showDialog<_RecentModelAction>(
      context: context,
      builder: (_) => _RecentModelActionDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = entry.configuration?.groups.length ?? 0;
    return AlertDialog(
      icon: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.insert_drive_file_outlined,
            size: 22, color: theme.colorScheme.primary),
      ),
      title: Text(entry.effectiveName),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      content: SizedBox(
        width: 420,
        child: Text(
          'This model is already configured '
          '($groups ${groups == 1 ? 'group' : 'groups'}). Start entering '
          'patient data, change the setup first, or look over the sessions '
          'already recorded for it?',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(_RecentModelAction.viewSessions),
          icon: const Icon(Icons.history_outlined, size: 20),
          label: const Text('View Sessions'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(_RecentModelAction.reconfigure),
          icon: const Icon(Icons.tune, size: 20),
          label: const Text('Reconfigure'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(_RecentModelAction.startDiagnosis),
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text('Start Diagnosis'),
        ),
      ],
    );
  }
}

/// Renames a recent model. Clearing the field is allowed and puts the model
/// back under its file name, so a rename is never a one-way door.
class _RenameModelDialog extends StatefulWidget {
  const _RenameModelDialog({required this.entry});

  final ModelConfigEntry entry;

  static Future<String?> show(
    BuildContext context, {
    required ModelConfigEntry entry,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _RenameModelDialog(entry: entry),
    );
  }

  @override
  State<_RenameModelDialog> createState() => _RenameModelDialogState();
}

class _RenameModelDialogState extends State<_RenameModelDialog> {
  late final _controller =
      TextEditingController(text: widget.entry.displayName ?? '');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Rename model'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Display name',
                hintText: p.basename(widget.entry.path),
                prefixIcon: const Icon(Icons.label_outline, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Shown on this screen, and used to name the session log new '
              'predictions are written to. Logs already saved under the old '
              'name are left as they are. Leave it empty to go back to the '
              'file name.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Confirms dropping a recent model. Unlike a rename, this one is a one-way
/// door for the saved configuration, so it says plainly what is lost and what
/// is not — the file on disk being the part users worry about.
class _RemoveModelDialog extends StatelessWidget {
  const _RemoveModelDialog({required this.entry});

  final ModelConfigEntry entry;

  static Future<bool?> show(
    BuildContext context, {
    required ModelConfigEntry entry,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => _RemoveModelDialog(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final groups = entry.configuration?.groups.length ?? 0;
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return AlertDialog(
      icon: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, size: 22, color: scheme.error),
      ),
      title: Text('Remove ${entry.effectiveName}?'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              groups > 0
                  ? 'Takes it off this list and discards its saved setup '
                      '($groups ${groups == 1 ? 'group' : 'groups'}), which '
                      'would have to be rebuilt by hand.'
                  : 'Takes it off this list. It has no saved setup to lose.',
              style: bodyStyle,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                entry.path,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The model file is not deleted — open it again from '
              '"Select model" to start over. Session logs are left alone.',
              style: bodyStyle,
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          icon: const Icon(Icons.delete_outline, size: 20),
          label: const Text('Remove'),
        ),
      ],
    );
  }
}

class _RecentModelTile extends StatelessWidget {
  const _RecentModelTile({
    required this.entry,
    required this.enabled,
    required this.onTap,
    required this.onRename,
    required this.onRemove,
  });

  final ModelConfigEntry entry;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final configured = entry.configuration != null;
    final description = entry.description;
    final subtitleStyle =
        theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant);

    return ListTile(
      enabled: enabled,
      isThreeLine: true,
      leading: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.insert_drive_file_outlined,
            size: 18, color: scheme.primary),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.effectiveName,
              style: theme.textTheme.titleSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: enabled ? onRename : null,
            icon: const Icon(Icons.edit_outlined, size: 16),
            tooltip: 'Rename model',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (description != null && description.isNotEmpty)
            Text(description, style: subtitleStyle, maxLines: 2,
                overflow: TextOverflow.ellipsis),
          Text(
            configured
                ? '${entry.configuration!.groups.length} groups configured'
                : 'Not configured yet',
            style: subtitleStyle,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            'Created ${_formatDateTime(entry.createdAt)} · '
            'Last opened ${_formatDateTime(entry.lastOpened)}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      // Kept out of the title row, where the rename pencil sits: that one
      // edits the name next to it, while this discards the whole entry.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.delete_outline, size: 20),
            tooltip: 'Remove from recent models',
            color: scheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// `14 Aug 2026, 15:04` — short enough for a list row and unambiguous about
/// the month, which a numeric date would not be across locales.
String _formatDateTime(DateTime time) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.day} ${months[time.month - 1]} ${time.year}, '
      '${two(time.hour)}:${two(time.minute)}';
}
