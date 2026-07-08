import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/model_domain.dart';
import '../models/prediction_result.dart';
import '../models/session_record.dart';
import '../services/api_service.dart';
import '../services/csv_service.dart';
import '../widgets/dynamic_form.dart';
import '../widgets/evaluation_dialog.dart';

/// Renders a [DynamicForm] for the currently loaded model's domain and lets
/// the user submit values to `/predict`.
///
/// If [initialDomain] is supplied (normally passed by [HomeScreen] right
/// after a successful model load) it is used directly; otherwise the domain
/// is fetched from the backend, which keeps this screen reachable on its own
/// (e.g. after a hot restart).
class InputScreen extends StatefulWidget {
  const InputScreen({super.key, this.initialDomain});

  final ModelDomain? initialDomain;

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  final _formKey = GlobalKey<FormState>();
  final _values = ValueNotifier<Map<String, dynamic>>({});

  ModelDomain? _domain;
  bool _loadingDomain = false;
  String? _domainError;

  bool _predicting = false;
  String? _predictError;
  PredictionResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.initialDomain != null) {
      _domain = widget.initialDomain;
    } else {
      _fetchDomain();
    }
  }

  @override
  void dispose() {
    _values.dispose();
    super.dispose();
  }

  Future<void> _fetchDomain() async {
    setState(() {
      _loadingDomain = true;
      _domainError = null;
    });
    try {
      final domain = await context.read<ApiService>().getDomain();
      if (!mounted) return;
      setState(() => _domain = domain);
    } catch (e) {
      if (!mounted) return;
      setState(() => _domainError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingDomain = false);
    }
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
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _predictError = e.toString());
    } finally {
      if (mounted) setState(() => _predicting = false);
    }
    if (result != null && mounted) {
      await _handlePostPrediction(result);
    }
  }

  Future<void> _handlePostPrediction(PredictionResult result) async {
    final config = context.read<AppConfig>();

    EvaluationResult? evaluation;
    if (config.evaluationDialogEnabled &&
        config.evaluationDialogAutoOpenAfterResult) {
      evaluation = await EvaluationDialog.show(context, config: config);
      if (!mounted) return;
    }

    final domain = _domain;
    if (config.csvLoggingEnabled && domain != null) {
      final record = SessionRecord(
        timestamp: result.timestamp,
        inputs: _values.value,
        predictedClass: result.predictedClass,
        probabilities: result.probabilities,
        doctorDiagnosis: evaluation?.doctorDiagnosis,
        notes: evaluation?.notes,
      );
      await const CsvService()
          .appendRecord(record, domain: domain, config: config);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Patient Data')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loadingDomain) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_domainError != null) {
      return _ErrorState(message: _domainError!, onRetry: _fetchDomain);
    }
    final domain = _domain;
    if (domain == null) {
      return const Center(child: Text('No model loaded.'));
    }

    final showRangeHints = context.watch<AppConfig>().showRangeHints;

    return Column(
      children: [
        Expanded(
          child: DynamicForm(
            formKey: _formKey,
            domain: domain,
            values: _values,
            showRangeHints: showRangeHints,
          ),
        ),
        if (_predictError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _predictError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_result != null) _ResultSummary(result: _result!),
        SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _predicting ? null : _submit,
            icon: _predicting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_predicting ? 'Predicting…' : 'Predict'),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.result});

  final PredictionResult result;

  @override
  Widget build(BuildContext context) {
    final sorted = result.probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Predicted: ${result.predictedClass}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final entry in sorted)
              Text('${entry.key}: ${(entry.value * 100).toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }
}
