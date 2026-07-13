import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_config_notifier.dart';
import '../models/model_domain.dart';
import '../models/prediction_result.dart';
import '../models/session_record.dart';
import '../services/csv_service.dart';
import '../widgets/evaluation_dialog.dart';
import '../widgets/result_display.dart';

/// Data passed via `extra` when navigating to [ResultScreen].
class ResultScreenArgs {
  const ResultScreenArgs({
    required this.domain,
    required this.result,
    required this.inputs,
  });

  final ModelDomain domain;
  final PredictionResult result;
  final Map<String, dynamic> inputs;
}

/// Shows a [PredictionResult] (styled per `config.resultDisplay`) and, once
/// the first frame is up, opens the evaluation dialog (if configured) and
/// logs a [SessionRecord] to CSV (if configured).
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.args});

  final ResultScreenArgs args;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  EvaluationResult? _evaluation;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handlePostResult());
  }

  Future<void> _handlePostResult() async {
    if (_handled || !mounted) return;
    _handled = true;

    final config = context.read<AppConfigNotifier>().config;

    EvaluationResult? evaluation;
    if (config.evaluationDialogEnabled &&
        config.evaluationDialogAutoOpenAfterResult) {
      evaluation = await EvaluationDialog.show(context, config: config);
      if (!mounted) return;
      setState(() => _evaluation = evaluation);
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
      await const CsvService().appendRecord(
        record,
        domain: widget.args.domain,
        config: config,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfigNotifier>().config;
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            ResultDisplay(result: widget.args.result, config: config),
            if (_evaluation != null)
              _EvaluationSummary(evaluation: _evaluation!),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('New Patient'),
              ),
            ),
          ],
        ),
      ),
    );
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Evaluation', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            if (evaluation.doctorDiagnosis != null)
              Text('Doctor diagnosis: ${evaluation.doctorDiagnosis}'),
            if (evaluation.notes != null) Text('Notes: ${evaluation.notes}'),
          ],
        ),
      ),
    );
  }
}
