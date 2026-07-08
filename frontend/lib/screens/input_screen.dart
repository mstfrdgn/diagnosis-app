import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../models/model_domain.dart';
import '../models/prediction_result.dart';
import '../services/api_service.dart';
import '../widgets/dynamic_form.dart';
import 'result_screen.dart';

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
