/// One row of the CSV session log: a prediction plus the doctor's
/// evaluation of it (if the evaluation dialog was used).
class SessionRecord {
  const SessionRecord({
    required this.timestamp,
    required this.inputs,
    required this.predictedClass,
    required this.probabilities,
    this.doctorDiagnosis,
    this.notes,
  });

  final DateTime timestamp;
  final Map<String, dynamic> inputs;
  final String predictedClass;
  final Map<String, double> probabilities;
  final String? doctorDiagnosis;
  final String? notes;
}
