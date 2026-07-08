/// Mirrors the backend's `PredictResponse` schema, plus a client-side
/// timestamp for display/logging purposes.
class PredictionResult {
  const PredictionResult({
    required this.predictedClass,
    required this.probabilities,
    required this.timestamp,
  });

  final String predictedClass;
  final Map<String, double> probabilities;
  final DateTime timestamp;

  factory PredictionResult.fromJson(Map<String, dynamic> json) {
    final rawProbabilities = json['probabilities'] as Map<String, dynamic>;
    return PredictionResult(
      predictedClass: json['predicted_class'] as String,
      probabilities: rawProbabilities
          .map((label, value) => MapEntry(label, (value as num).toDouble())),
      timestamp: DateTime.now(),
    );
  }
}
