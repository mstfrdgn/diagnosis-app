import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../models/model_domain.dart';
import '../models/prediction_result.dart';
import '../models/session_record.dart';
import '../services/csv_service.dart';
import '../services/model_config_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/evaluation_dialog.dart';
import '../widgets/result_display.dart';

/// Data passed via `extra` when navigating to [ResultScreen].
class ResultScreenArgs {
  const ResultScreenArgs({
    required this.domain,
    required this.result,
    required this.inputs,
    required this.modelPath,
  });

  final ModelDomain domain;
  final PredictionResult result;
  final Map<String, dynamic> inputs;

  /// Path of the loaded model file, which decides the per-model CSV log.
  final String modelPath;
}

/// Shows a [PredictionResult] and, once the first frame is up, opens the
/// evaluation dialog (if configured) and logs a [SessionRecord] to CSV (if
/// configured).
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.args});

  final ResultScreenArgs args;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  EvaluationResult? _evaluation;
  CsvWriteResult? _csvResult;
  bool _handled = false;

  /// Shared by the [Scrollbar] and the body it wraps; see the note in
  /// `home_screen.dart` for why the fallback controller will not do.
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePostResult());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handlePostResult() async {
    if (_handled || !mounted) return;
    _handled = true;

    final config = context.read<AppConfigNotifier>().config;
    final modelDisplayName =
        context.read<ModelConfigNotifier>().displayNameFor(widget.args.modelPath);

    EvaluationResult? evaluation;
    if (config.evaluationDialogEnabled &&
        config.evaluationDialogAutoOpenAfterResult) {
      // Ask first: declining skips the form and logs the session with no
      // doctor diagnosis rather than making the user dismiss an empty dialog.
      final wanted = await EvaluationDialog.confirm(context);
      if (!mounted) return;
      if (wanted) {
        evaluation = await EvaluationDialog.show(context, config: config);
        if (!mounted) return;
        setState(() => _evaluation = evaluation);
      }
    }

    if (config.csvLoggingEnabled) {
      final record = SessionRecord(
        timestamp: widget.args.result.timestamp,
        inputs: widget.args.inputs,
        predictedClass: widget.args.result.predictedClass,
        probabilities: widget.args.result.probabilities,
        doctorDiagnosis: evaluation?.doctorDiagnosis,
        notes: evaluation?.notes,
      );
      final csvResult = await const CsvService().appendRecord(
        record,
        domain: widget.args.domain,
        modelPath: widget.args.modelPath,
        config: config,
        modelDisplayName: modelDisplayName,
      );
      if (!mounted) return;
      setState(() => _csvResult = csvResult);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = context.watch<AppConfigNotifier>().config;
    final csvResult = _csvResult;
    final csvFailure =
        csvResult != null && !csvResult.succeeded ? csvResult : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prediction result'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.person_add_alt, size: 20),
              label: const Text('New patient'),
            ),
          ),
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
                  const BoxConstraints(maxWidth: AppSpacing.narrowWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ResultDisplay(result: widget.args.result, config: config),
                  if (_evaluation != null) ...[
                    const SizedBox(height: 16),
                    _EvaluationSummary(evaluation: _evaluation!),
                  ],
                  if (csvFailure != null) ...[
                    const SizedBox(height: 16),
                    _CsvErrorNotice(result: csvFailure),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Recorded ${_formatTime(widget.args.result.timestamp)}'
                    '${csvResult != null && csvResult.succeeded ? ' · saved to the session log' : ''}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back, size: 20),
                    label: const Text('New patient'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}';
  }
}

class _EvaluationSummary extends StatelessWidget {
  const _EvaluationSummary({required this.evaluation});

  final EvaluationResult evaluation;

  @override
  Widget build(BuildContext context) {
    if (evaluation.doctorDiagnosis == null && evaluation.notes == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_turned_in_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Doctor’s evaluation',
                    style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 14),
            if (evaluation.doctorDiagnosis != null)
              _SummaryRow(
                label: 'Diagnosis',
                value: evaluation.doctorDiagnosis!,
              ),
            if (evaluation.notes != null)
              _SummaryRow(label: 'Notes', value: evaluation.notes!),
          ],
        ),
      ),
    );
  }
}

/// Shown when the session could not be appended to the CSV log, so a failed
/// write is never mistaken for a saved one.
class _CsvErrorNotice extends StatelessWidget {
  const _CsvErrorNotice({required this.result});

  final CsvWriteResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 20, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Not saved to the session log',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Could not write to ${result.path} — ${result.error}. '
                    'Close the file if it is open in another program, then '
                    'run this prediction again.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
