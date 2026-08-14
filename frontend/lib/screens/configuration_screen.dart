import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/model_configuration.dart';
import '../models/model_description.dart';
import '../models/model_domain.dart';
import '../models/orange_variable.dart';
import '../services/model_config_notifier.dart';
import '../theme/app_theme.dart';
import 'input_screen.dart';

/// Data passed via `extra` when navigating to [ConfigurationScreen].
class ConfigurationScreenArgs {
  const ConfigurationScreenArgs({
    required this.domain,
    required this.modelPath,
  });

  final ModelDomain domain;
  final String modelPath;
}

/// A three-step wizard that turns a freshly loaded Orange domain into a
/// [ModelConfiguration]:
///
///   1. **Create groups** – the user names the sections they want.
///   2. **Assign variables** – every feature is dragged (or picked) into a
///      group; the step cannot be left while anything is unassigned.
///   3. **Set ranges** – min/max bounds for continuous variables, pre-filled
///      from the Orange domain hints where the model provides them.
///
/// The result is saved per model path via [ModelConfigNotifier] and carried
/// forward to [InputScreen], which renders one page per group.
class ConfigurationScreen extends StatefulWidget {
  const ConfigurationScreen({super.key, required this.args});

  final ConfigurationScreenArgs args;

  @override
  State<ConfigurationScreen> createState() => _ConfigurationScreenState();
}

/// Sentinel value used by the "assign to group" menu for *removing* a
/// variable from its group; a real group name can never collide with it.
const _unassignSentinel = ' unassign';

/// Renders a bound for display, dropping the `.0` that `toString()` leaves
/// on whole numbers (Orange range hints are usually integral).
String _formatNumber(double? value) {
  if (value == null) return '';
  return value == value.roundToDouble() && value.abs() < 1e15
      ? value.toStringAsFixed(0)
      : value.toString();
}

class _ConfigurationScreenState extends State<ConfigurationScreen> {
  static const _stepLabels = ['Groups', 'Assign', 'Ranges'];

  int _step = 0;

  final _groups = <String>[];

  /// Variable name → group name, or `null` while still unassigned.
  final _groupOf = <String, String?>{};

  final _minControllers = <String, TextEditingController>{};
  final _maxControllers = <String, TextEditingController>{};

  final _newGroupController = TextEditingController();
  final _newGroupFocus = FocusNode();
  String? _newGroupError;

  /// The model's one-line summary. Pre-filled with the description generated
  /// when the model was loaded, then whatever the user makes of it.
  late final TextEditingController _descriptionController;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final notifier = context.read<ModelConfigNotifier>();
    final existing = notifier.configurationFor(widget.args.modelPath);

    _descriptionController = TextEditingController(
      text: notifier.descriptionFor(widget.args.modelPath) ??
          describeModel(widget.args.domain),
    );

    _groups.addAll(existing?.groups ?? const []);
    for (final variable in _assignableVariables) {
      _groupOf[variable.name] = existing?.variableGroups[variable.name];
    }
    // Guard against saved data drifting out of sync (e.g. a hand-edited
    // config file): a variable's saved group must always exist in `_groups`,
    // or it would be assigned to a group the user cannot see.
    for (final group in _groupOf.values) {
      if (group != null && !_groups.contains(group)) _groups.add(group);
    }

    for (final variable in _continuousVariables) {
      final override = existing?.variableRanges[variable.name];
      _minControllers[variable.name] = TextEditingController(
        text: _formatNumber(override?.min ?? variable.min),
      );
      _maxControllers[variable.name] = TextEditingController(
        text: _formatNumber(override?.max ?? variable.max),
      );
    }
  }

  @override
  void dispose() {
    _newGroupController.dispose();
    _newGroupFocus.dispose();
    _descriptionController.dispose();
    for (final controller in _minControllers.values) {
      controller.dispose();
    }
    for (final controller in _maxControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ── domain slices ──────────────────────────────────────────────────────

  /// Features the user actually fills in. String variables are excluded:
  /// Orange treats them as metadata and they are never sent to `/predict`,
  /// so asking the user to file them into a group would be busywork.
  List<OrangeVariable> get _assignableVariables => widget.args.domain.features
      .where((v) => v.type != VariableType.string)
      .toList();

  /// Numeric variables, which are the only ones a min/max range applies to.
  /// Orange's `TimeVariable` is a subclass of `ContinuousVariable`, so it
  /// gets a range too.
  List<OrangeVariable> get _continuousVariables => _assignableVariables
      .where((v) =>
          v.type == VariableType.continuous || v.type == VariableType.time)
      .toList();

  List<OrangeVariable> get _unassignedVariables =>
      _assignableVariables.where((v) => _groupOf[v.name] == null).toList();

  List<OrangeVariable> _variablesIn(String group) =>
      _assignableVariables.where((v) => _groupOf[v.name] == group).toList();

  // ── step 1: groups ─────────────────────────────────────────────────────

  void _addGroup() {
    final name = _newGroupController.text.trim();
    if (name.isEmpty) {
      setState(() => _newGroupError = 'Enter a name for the group.');
      return;
    }
    if (_groups.any((g) => g.toLowerCase() == name.toLowerCase())) {
      setState(() => _newGroupError = 'A group called “$name” already exists.');
      return;
    }
    setState(() {
      _groups.add(name);
      _newGroupError = null;
      _newGroupController.clear();
    });
    _newGroupFocus.requestFocus();
  }

  Future<void> _deleteGroup(String group) async {
    final assigned = _variablesIn(group);
    if (assigned.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Delete “$group”?'),
          content: Text(
            '${assigned.length} variable${assigned.length == 1 ? '' : 's'} '
            'will go back to the unassigned list.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _groups.remove(group);
      for (final name in _groupOf.keys.toList()) {
        if (_groupOf[name] == group) _groupOf[name] = null;
      }
    });
  }

  // ── step 3: ranges ─────────────────────────────────────────────────────

  double? _parsed(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  /// Variable name → why its range is invalid. Empty means step 3 is valid.
  Map<String, String> get _rangeErrors {
    final errors = <String, String>{};
    for (final variable in _continuousVariables) {
      final minText = _minControllers[variable.name]!.text.trim();
      final maxText = _maxControllers[variable.name]!.text.trim();
      final min = _parsed(_minControllers[variable.name]!);
      final max = _parsed(_maxControllers[variable.name]!);
      if (minText.isNotEmpty && min == null) {
        errors[variable.name] = 'Minimum must be a number.';
      } else if (maxText.isNotEmpty && max == null) {
        errors[variable.name] = 'Maximum must be a number.';
      } else if (min != null && max != null && min > max) {
        errors[variable.name] = 'Minimum must not be greater than maximum.';
      }
    }
    return errors;
  }

  // ── navigation ─────────────────────────────────────────────────────────

  bool get _canAdvance => switch (_step) {
        0 => _groups.isNotEmpty,
        1 => _unassignedVariables.isEmpty,
        _ => _rangeErrors.isEmpty,
      };

  /// Explains a disabled Next/Finish button, shown next to it.
  String? get _blockedReason {
    if (_canAdvance) return null;
    switch (_step) {
      case 0:
        return 'Create at least one group to continue.';
      case 1:
        final count = _unassignedVariables.length;
        return '$count variable${count == 1 ? '' : 's'} still unassigned.';
      default:
        return 'Fix the highlighted ranges to continue.';
    }
  }

  void _advance() {
    if (!_canAdvance) return;
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    setState(() => _saving = true);

    final variableGroups = <String, String>{
      for (final entry in _groupOf.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    final variableRanges = <String, VariableRangeOverride>{
      for (final variable in _continuousVariables)
        if (_parsed(_minControllers[variable.name]!) != null ||
            _parsed(_maxControllers[variable.name]!) != null)
          variable.name: VariableRangeOverride(
            min: _parsed(_minControllers[variable.name]!),
            max: _parsed(_maxControllers[variable.name]!),
          ),
    };
    final modelConfig = ModelConfiguration(
      groups: List.of(_groups),
      variableGroups: variableGroups,
      variableRanges: variableRanges,
    );

    final router = GoRouter.of(context);
    await context.read<ModelConfigNotifier>().saveConfiguration(
          widget.args.modelPath,
          modelConfig,
          description: _descriptionController.text,
        );
    if (!mounted) return;
    setState(() => _saving = false);

    router.push(
      '/input',
      extra: InputScreenArgs(
        domain: widget.args.domain,
        modelPath: widget.args.modelPath,
        modelConfig: modelConfig,
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Configure model'),
            const SizedBox(height: 2),
            Text(
              p.basename(widget.args.modelPath),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _WizardProgress(
            current: _step,
            labels: _stepLabels,
            onStepTapped: (index) => setState(() => _step = index),
          ),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: AppSpacing.page,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AppSpacing.contentWidth,
                    ),
                    child: switch (_step) {
                      0 => _buildGroupsStep(),
                      1 => _buildAssignStep(),
                      _ => _buildRangesStep(),
                    },
                  ),
                ),
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── step 1 ─────────────────────────────────────────────────────────────

  Widget _buildGroupsStep() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIntro(
          icon: Icons.folder_copy_outlined,
          title: 'Create groups',
          description:
              'Split the model’s variables into sections. Each group becomes '
              'one page of the data-entry form, in the order you create them.',
        ),
        const SizedBox(height: 24),
        const SectionHeader(
          title: 'Description',
          subtitle: 'Read from the model when it was loaded — rewrite it to '
              'say whatever is useful to you.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Model description',
                hintText: 'What this model is for',
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const SectionHeader(title: 'Add a group'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newGroupController,
                        focusNode: _newGroupFocus,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Group name',
                          hintText: 'e.g. Signs & Symptoms',
                          prefixIcon: Icon(Icons.label_outline, size: 20),
                        ),
                        onChanged: (_) {
                          if (_newGroupError != null) {
                            setState(() => _newGroupError = null);
                          }
                        },
                        onSubmitted: (_) => _addGroup(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _addGroup,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add Group'),
                    ),
                  ],
                ),
                if (_newGroupError != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: 6),
                      Text(
                        _newGroupError!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        SectionHeader(
          title: 'Your groups',
          subtitle: _groups.isEmpty
              ? 'Nothing yet — add your first group above.'
              : 'Shown as form pages in this order.',
          trailing: _CountBadge(count: _groups.length),
        ),
        if (_groups.isEmpty)
          const EmptyStateCard(
            icon: Icons.folder_off_outlined,
            message: 'No groups created yet.',
          )
        else
          for (var i = 0; i < _groups.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _GroupCard(
                index: i,
                name: _groups[i],
                assignedCount: _variablesIn(_groups[i]).length,
                onDelete: () => _deleteGroup(_groups[i]),
              ),
            ),
      ],
    );
  }

  // ── step 2 ─────────────────────────────────────────────────────────────

  Widget _buildAssignStep() {
    final theme = Theme.of(context);
    final unassigned = _unassignedVariables;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIntro(
          icon: Icons.drag_indicator,
          title: 'Assign variables',
          description:
              'Drag each variable onto a group — or click it to pick one from '
              'a menu. Every variable needs a home before you can continue.',
        ),
        const SizedBox(height: 24),
        SectionHeader(
          title: 'Unassigned',
          subtitle: unassigned.isEmpty
              ? 'All variables have been placed.'
              : 'Drag these onto a group below.',
          trailing: _CountBadge(
            count: unassigned.length,
            tone: unassigned.isEmpty
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
        ),
        if (unassigned.isEmpty)
          EmptyStateCard(
            icon: Icons.task_alt,
            message: 'Every variable has been assigned to a group.',
            tone: theme.colorScheme.primary,
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final variable in unassigned)
                    _VariableChip(
                      variable: variable,
                      currentGroup: null,
                      groups: _groups,
                      onAssign: (group) =>
                          setState(() => _groupOf[variable.name] = group),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 28),
        const SectionHeader(
          title: 'Groups',
          subtitle: 'Drop variables here to assign them.',
        ),
        for (final group in _groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _GroupDropTarget(
              name: group,
              variables: _variablesIn(group),
              groups: _groups,
              onAssign: (variableName, target) =>
                  setState(() => _groupOf[variableName] = target),
            ),
          ),
      ],
    );
  }

  // ── step 3 ─────────────────────────────────────────────────────────────

  Widget _buildRangesStep() {
    final variables = _continuousVariables;
    final errors = _rangeErrors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepIntro(
          icon: Icons.straighten,
          title: 'Set ranges',
          description:
              'Bounds for the numeric variables. They are pre-filled from the '
              'model where it provides a hint, and are used to validate what '
              'can be typed into the form. Leave a field empty for no bound.',
        ),
        const SizedBox(height: 24),
        if (variables.isEmpty)
          const EmptyStateCard(
            icon: Icons.info_outline,
            message:
                'This model has no continuous variables, so there is nothing '
                'to set here.',
          )
        else ...[
          SectionHeader(
            title: 'Continuous variables',
            subtitle: 'Detected automatically from the Orange domain.',
            trailing: _CountBadge(count: variables.length),
          ),
          for (final variable in variables)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _RangeCard(
                variable: variable,
                group: _groupOf[variable.name],
                minController: _minControllers[variable.name]!,
                maxController: _maxControllers[variable.name]!,
                error: errors[variable.name],
                onChanged: () => setState(() {}),
              ),
            ),
        ],
      ],
    );
  }

  // ── footer ─────────────────────────────────────────────────────────────

  Widget _buildFooter() {
    final theme = Theme.of(context);
    final isLastStep = _step == 2;
    final reason = _blockedReason;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerTheme.color ?? Colors.black12),
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            if (_step > 0)
              OutlinedButton.icon(
                onPressed: () => setState(() => _step--),
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text('Back'),
              ),
            const Spacer(),
            if (reason != null)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: (_canAdvance && !_saving) ? _advance : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(isLastStep ? Icons.check : Icons.arrow_forward,
                      size: 20),
              label: Text(isLastStep ? 'Finish' : 'Next'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── wizard chrome ────────────────────────────────────────────────────────────

/// The numbered step indicator under the app bar. Completed steps are
/// tappable so the user can jump back and revise an earlier decision.
class _WizardProgress extends StatelessWidget {
  const _WizardProgress({
    required this.current,
    required this.labels,
    required this.onStepTapped,
  });

  final int current;
  final List<String> labels;
  final ValueChanged<int> onStepTapped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerTheme.color ?? Colors.black12),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSpacing.contentWidth),
          child: Row(
            children: [
              for (var i = 0; i < labels.length; i++) ...[
                if (i > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.only(bottom: 22),
                      color: i <= current
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
                _StepDot(
                  number: i + 1,
                  label: labels[i],
                  isCurrent: i == current,
                  isComplete: i < current,
                  onTap: i < current ? () => onStepTapped(i) : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.number,
    required this.label,
    required this.isCurrent,
    required this.isComplete,
    required this.onTap,
  });

  final int number;
  final String label;
  final bool isCurrent;
  final bool isComplete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = isCurrent || isComplete;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 32,
              width: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? scheme.primary : Colors.transparent,
                border: Border.all(
                  color: active ? scheme.primary : scheme.outlineVariant,
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: isComplete
                  ? Icon(Icons.check, size: 18, color: scheme.onPrimary)
                  : Text(
                      '$number',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: active ? scheme.onPrimary : scheme.outline,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Icon + heading + explanation shown at the top of each wizard step.
class _StepIntro extends StatelessWidget {
  const _StepIntro({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(
                description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small pill showing a count next to a [SectionHeader].
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.tone});

  final int count;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = tone ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── step 1 pieces ────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.index,
    required this.name,
    required this.assignedCount,
    required this.onDelete,
  });

  final int index;
  final String name;
  final int assignedCount;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: Container(
          height: 34,
          width: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
        title: Text(name, style: theme.textTheme.titleMedium),
        subtitle: Text(
          assignedCount == 0
              ? 'No variables assigned yet'
              : '$assignedCount variable${assignedCount == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: IconButton(
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete group',
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

// ── step 2 pieces ────────────────────────────────────────────────────────────

IconData _iconForType(VariableType type) => switch (type) {
      VariableType.discrete => Icons.checklist_rtl,
      VariableType.continuous => Icons.straighten,
      VariableType.time => Icons.schedule,
      VariableType.string => Icons.text_fields,
    };

/// A variable rendered as a draggable chip. Dragging it onto a
/// [_GroupDropTarget] assigns it; clicking it opens a menu with the same
/// groups, which keeps the screen usable without a mouse drag.
class _VariableChip extends StatelessWidget {
  const _VariableChip({
    required this.variable,
    required this.currentGroup,
    required this.groups,
    required this.onAssign,
  });

  final OrangeVariable variable;
  final String? currentGroup;
  final List<String> groups;

  /// Called with the target group, or `null` to unassign.
  final ValueChanged<String?> onAssign;

  @override
  Widget build(BuildContext context) {
    final visual = _visual(context);
    return Draggable<String>(
      data: variable.name,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: _visual(context, dragging: true)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: visual),
      child: PopupMenuButton<String>(
        tooltip: 'Assign to a group',
        position: PopupMenuPosition.under,
        onSelected: (value) =>
            onAssign(value == _unassignSentinel ? null : value),
        itemBuilder: (_) => [
          for (final group in groups)
            CheckedPopupMenuItem(
              value: group,
              checked: group == currentGroup,
              child: Text(group),
            ),
          if (currentGroup != null) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _unassignSentinel,
              child: Text('Remove from group'),
            ),
          ],
        ],
        child: visual,
      ),
    );
  }

  Widget _visual(BuildContext context, {bool dragging = false}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final assigned = currentGroup != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: dragging
            ? scheme.primary
            : (assigned
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surfaceContainerHighest),
        borderRadius: BorderRadius.circular(AppSpacing.smallRadius),
        border: Border.all(
          color: dragging
              ? scheme.primary
              : (assigned
                  ? scheme.primary.withValues(alpha: 0.35)
                  : scheme.outlineVariant),
        ),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForType(variable.type),
            size: 16,
            color: dragging
                ? scheme.onPrimary
                : (assigned ? scheme.primary : scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 8),
          Text(
            variable.name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: dragging ? scheme.onPrimary : scheme.onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.expand_more,
            size: 16,
            color: dragging
                ? scheme.onPrimary
                : scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

/// One group on step 2: a titled panel that accepts dropped variables and
/// lists the ones already assigned to it.
class _GroupDropTarget extends StatelessWidget {
  const _GroupDropTarget({
    required this.name,
    required this.variables,
    required this.groups,
    required this.onAssign,
  });

  final String name;
  final List<OrangeVariable> variables;
  final List<String> groups;
  final void Function(String variableName, String? group) onAssign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          variables.every((v) => v.name != details.data),
      onAcceptWithDetails: (details) => onAssign(details.data, name),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: active
                ? scheme.primary.withValues(alpha: 0.06)
                : theme.cardTheme.color,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            border: Border.all(
              color: active ? scheme.primary : scheme.outlineVariant,
              width: active ? 1.6 : 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(name, style: theme.textTheme.titleSmall),
                  ),
                  _CountBadge(count: variables.length),
                ],
              ),
              const SizedBox(height: 14),
              if (variables.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.smallRadius),
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.04),
                  ),
                  child: Text(
                    active ? 'Release to add' : 'Drop variables here',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final variable in variables)
                      _VariableChip(
                        variable: variable,
                        currentGroup: name,
                        groups: groups,
                        onAssign: (group) => onAssign(variable.name, group),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── step 3 pieces ────────────────────────────────────────────────────────────

class _RangeCard extends StatelessWidget {
  const _RangeCard({
    required this.variable,
    required this.group,
    required this.minController,
    required this.maxController,
    required this.error,
    required this.onChanged,
  });

  final OrangeVariable variable;
  final String? group;
  final TextEditingController minController;
  final TextEditingController maxController;
  final String? error;
  final VoidCallback onChanged;

  String get _hint {
    if (variable.min == null && variable.max == null) {
      return 'No range provided by the model';
    }
    final min = variable.min == null
        ? '−∞'
        : _formatNumber(variable.min);
    final max = variable.max == null
        ? '+∞'
        : _formatNumber(variable.max);
    return 'Model hint: $min – $max';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        side: BorderSide(
          color: error != null ? scheme.error : scheme.outlineVariant,
          width: error != null ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  height: 34,
                  width: 34,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconForType(variable.type),
                      size: 18, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(variable.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        group == null ? _hint : '$group · $_hint',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _RangeInput(
                    label: 'Minimum',
                    controller: minController,
                    onChanged: onChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RangeInput(
                    label: 'Maximum',
                    controller: maxController,
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Text(
                    error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.error),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeInput extends StatelessWidget {
  const _RangeInput({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(labelText: label, hintText: 'none'),
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true, signed: true),
      onChanged: (_) => onChanged(),
    );
  }
}
