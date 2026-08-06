import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../models/model_configuration.dart';
import '../models/model_domain.dart';
import '../models/orange_variable.dart';
import '../models/prediction_result.dart';
import '../services/api_service.dart';
import '../services/model_config_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/dynamic_form.dart';
import 'result_screen.dart';

/// Data passed via `extra` when navigating to [InputScreen] (normally by
/// [ConfigurationScreen] right after the user saves their per-model setup).
class InputScreenArgs {
  const InputScreenArgs({
    required this.domain,
    required this.modelPath,
    required this.modelConfig,
  });

  final ModelDomain domain;
  final String modelPath;
  final ModelConfiguration modelConfig;
}

/// One page of the Input Screen wizard: a group heading plus the feature
/// variables assigned to it (with any Configuration Screen range overrides
/// already applied).
class _InputGroup {
  const _InputGroup({required this.heading, required this.variables});

  final String heading;
  final List<OrangeVariable> variables;
}

/// Pages through one screen per input group (as configured on the
/// Configuration Screen), then lets the user submit values to `/predict`.
///
/// If [initialArgs] is supplied (normally passed by [ConfigurationScreen]
/// right after the user saves their setup) it is used directly; otherwise
/// the domain and saved configuration are fetched/looked up from scratch,
/// which keeps this screen reachable on its own (e.g. after a hot restart).
class InputScreen extends StatefulWidget {
  const InputScreen({super.key, this.initialArgs});

  final InputScreenArgs? initialArgs;

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _values = ValueNotifier<Map<String, dynamic>>({});

  ModelDomain? _domain;
  ModelConfiguration? _modelConfig;
  bool _loadingArgs = false;
  String? _argsError;

  int _groupIndex = 0;
  bool _predicting = false;
  String? _predictError;

  @override
  void initState() {
    super.initState();
    final args = widget.initialArgs;
    if (args != null) {
      _domain = args.domain;
      _modelConfig = args.modelConfig;
    } else {
      _fetchArgs();
    }
  }

  @override
  void dispose() {
    _values.dispose();
    super.dispose();
  }

  Future<void> _fetchArgs() async {
    setState(() {
      _loadingArgs = true;
      _argsError = null;
    });
    final api = context.read<ApiService>();
    final modelConfigNotifier = context.read<ModelConfigNotifier>();
    try {
      final domain = await api.getDomain();
      final status = await api.getModelStatus();
      final path = status.path ?? '';
      final modelConfig = modelConfigNotifier.configurationFor(path) ??
          ModelConfiguration.empty;
      if (!mounted) return;
      setState(() {
        _domain = domain;
        _modelConfig = modelConfig;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _argsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingArgs = false);
    }
  }

  static const _otherHeading = 'Other';

  /// Builds one wizard page per group the user created on the Configuration
  /// Screen (in creation order), plus a trailing "Other" page for any
  /// variable that was left unassigned. Empty groups are skipped.
  List<_InputGroup> _buildGroups(
    ModelDomain domain,
    ModelConfiguration modelConfig,
  ) {
    final byHeading = <String, List<OrangeVariable>>{
      for (final h in modelConfig.groups) h: [],
    };
    final unassigned = <OrangeVariable>[];
    for (final variable in domain.features) {
      final heading = modelConfig.variableGroups[variable.name];
      final range = modelConfig.variableRanges[variable.name];
      final effective = range == null
          ? variable
          : variable.copyWith(min: range.min, max: range.max);
      final bucket = heading == null ? null : byHeading[heading];
      (bucket ?? unassigned).add(effective);
    }
    return [
      for (final h in modelConfig.groups)
        if (byHeading[h]!.isNotEmpty)
          _InputGroup(heading: h, variables: byHeading[h]!),
      if (unassigned.isNotEmpty)
        _InputGroup(heading: _otherHeading, variables: unassigned),
    ];
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _predicting = true;
      _predictError = null;
    });
    PredictionResult? result;
    try {
      result = await context.read<ApiService>().predict(_values.value);
    } catch (e) {
      if (!mounted) return;
      setState(() => _predictError = e.toString());
    } finally {
      if (mounted) setState(() => _predicting = false);
    }

    final domain = _domain;
    if (result == null || domain == null || !mounted) return;

    await context.push(
      '/result',
      extra: ResultScreenArgs(
        domain: domain,
        result: result,
        inputs: Map<String, dynamic>.from(_values.value),
      ),
    );
    if (!mounted) return;
    _formKey.currentState?.reset();
    _values.value = {};
    setState(() => _groupIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final domain = _domain;
    final modelConfig = _modelConfig;
    final groups = domain != null && modelConfig != null
        ? _buildGroups(domain, modelConfig)
        : const <_InputGroup>[];
    final canGoBack = _groupIndex > 0;
    final hasGroups = groups.isNotEmpty;

    return PopScope(
      canPop: !canGoBack,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && canGoBack) {
          setState(() => _groupIndex--);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: hasGroups ? 72 : null,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hasGroups ? groups[_groupIndex].heading : 'Patient data'),
              if (hasGroups) ...[
                const SizedBox(height: 2),
                Text(
                  'Section ${_groupIndex + 1} of ${groups.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          bottom: hasGroups
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: (_groupIndex + 1) / groups.length,
                    minHeight: 3,
                  ),
                )
              : null,
        ),
        body: _buildBody(groups),
      ),
    );
  }

  Widget _buildBody(List<_InputGroup> groups) {
    if (_loadingArgs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_argsError != null) {
      return _ErrorState(message: _argsError!, onRetry: _fetchArgs);
    }
    if (_domain == null || _modelConfig == null || groups.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 360,
          child: EmptyStateCard(
            icon: Icons.inbox_outlined,
            message: 'No model loaded.',
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final showRangeHints =
        context.watch<AppConfigNotifier>().config.showRangeHints;
    final isLastGroup = _groupIndex == groups.length - 1;

    return Column(
      children: [
        Expanded(
          child: Form(
            key: _formKey,
            child: IndexedStack(
              index: _groupIndex,
              children: [
                for (final group in groups)
                  DynamicForm(
                    variables: group.variables,
                    values: _values,
                    showRangeHints: showRangeHints,
                  ),
              ],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top:
                  BorderSide(color: theme.dividerTheme.color ?? Colors.black12),
            ),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Column(
              children: [
                if (_predictError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 18, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _predictError!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    if (_groupIndex > 0)
                      OutlinedButton.icon(
                        onPressed: _predicting
                            ? null
                            : () => setState(() => _groupIndex--),
                        icon: const Icon(Icons.arrow_back, size: 20),
                        label: const Text('Back'),
                      ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _predicting
                          ? null
                          : (isLastGroup
                              ? _submit
                              : () => setState(() => _groupIndex++)),
                      icon: _predicting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(isLastGroup ? Icons.check : Icons.arrow_forward,
                              size: 20),
                      label: Text(
                        _predicting
                            ? 'Predicting…'
                            : (isLastGroup ? 'Predict' : 'Next'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 56,
                width: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.error_outline,
                    size: 28, color: theme.colorScheme.error),
              ),
              const SizedBox(height: 18),
              Text('Could not load the model',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
