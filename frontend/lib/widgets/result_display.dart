import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../models/prediction_result.dart';

/// Renders a [PredictionResult] using one of three styles selected by
/// `config.resultDisplay.style`: card | banner | detailed.
class ResultDisplay extends StatelessWidget {
  const ResultDisplay({super.key, required this.result, required this.config});

  final PredictionResult result;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    switch (config.resultDisplayStyle) {
      case 'banner':
        return _BannerResult(result: result, config: config);
      case 'detailed':
        return _DetailedResult(result: result, config: config);
      case 'card':
      default:
        return _CardResult(result: result, config: config);
    }
  }
}

// ── shared helpers ───────────────────────────────────────────────────────────

List<MapEntry<String, double>> _sortedProbabilities(PredictionResult result) {
  return result.probabilities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
}

String _formatProbability(double value, String format) {
  return format == 'decimal'
      ? value.toStringAsFixed(3)
      : '${(value * 100).toStringAsFixed(1)}%';
}

Color _parseHexColor(String hex) {
  var value = hex.replaceFirst('#', '');
  if (value.length == 6) value = 'FF$value';
  return Color(int.parse(value, radix: 16));
}

const _positiveLabels = {
  'positive',
  'yes',
  'present',
  'disease',
  'malignant',
  'sick',
  'true',
  '1',
};
const _negativeLabels = {
  'negative',
  'no',
  'absent',
  'healthy',
  'benign',
  'false',
  '0',
};

/// Best-effort guess at whether [label] represents the "condition present"
/// outcome, used only to pick a banner color. Returns `null` (neutral) when
/// the label doesn't match either common convention.
bool? _isPositiveLabel(String label) {
  final normalized = label.trim().toLowerCase();
  if (_positiveLabels.contains(normalized)) return true;
  if (_negativeLabels.contains(normalized)) return false;
  return null;
}

// ── card ──────────────────────────────────────────────────────────────────

class _CardResult extends StatelessWidget {
  const _CardResult({required this.result, required this.config});

  final PredictionResult result;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedProbabilities(result);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Predicted class',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              result.predictedClass,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (config.resultDisplayShowProbability) ...[
              const SizedBox(height: 20),
              for (final entry in sorted)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _ProbabilityBar(
                    label: entry.key,
                    value: entry.value,
                    highlighted: entry.key == result.predictedClass,
                    format: config.resultDisplayProbabilityFormat,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProbabilityBar extends StatelessWidget {
  const _ProbabilityBar({
    required this.label,
    required this.value,
    required this.highlighted,
    required this.format,
  });

  final String label;
  final double value;
  final bool highlighted;
  final String format;

  @override
  Widget build(BuildContext context) {
    final color = highlighted
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: highlighted ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            Text(_formatProbability(value, format)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

// ── banner ────────────────────────────────────────────────────────────────

class _BannerResult extends StatelessWidget {
  const _BannerResult({required this.result, required this.config});

  final PredictionResult result;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final positive = _isPositiveLabel(result.predictedClass);
    final backgroundColor = switch (positive) {
      true => _parseHexColor(config.resultDisplayPositiveClassColor),
      false => _parseHexColor(config.resultDisplayNegativeClassColor),
      null => Theme.of(context).colorScheme.primary,
    };
    final sorted = _sortedProbabilities(result);
    final topProbability = sorted.isNotEmpty ? sorted.first.value : null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            result.predictedClass,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          if (config.resultDisplayShowProbability &&
              topProbability != null) ...[
            const SizedBox(height: 8),
            Text(
              _formatProbability(
                topProbability,
                config.resultDisplayProbabilityFormat,
              ),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

// ── detailed ──────────────────────────────────────────────────────────────

class _DetailedResult extends StatelessWidget {
  const _DetailedResult({required this.result, required this.config});

  final PredictionResult result;
  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final sorted = _sortedProbabilities(result);
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Predicted class',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              result.predictedClass,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (config.resultDisplayShowProbability) ...[
              const SizedBox(height: 16),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(),
                  1: IntrinsicColumnWidth(),
                },
                children: [
                  for (final entry in sorted)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontWeight: entry.key == result.predictedClass
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            _formatProbability(
                              entry.value,
                              config.resultDisplayProbabilityFormat,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
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
