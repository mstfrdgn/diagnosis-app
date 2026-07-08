import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/model_domain.dart';
import '../models/prediction_result.dart';

// ── exceptions ────────────────────────────────────────────────────────────────

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class BackendUnavailableException extends ApiException {
  const BackendUnavailableException(
      [super.message = 'Cannot reach the backend service.']);
}

class ModelNotLoadedException extends ApiException {
  const ModelNotLoadedException(
      [super.message = 'No model is currently loaded.'])
      : super(statusCode: 404);
}

// ── model status ──────────────────────────────────────────────────────────────

class ModelStatus {
  const ModelStatus({required this.loaded, this.path});

  final bool loaded;
  final String? path;

  factory ModelStatus.fromJson(Map<String, dynamic> json) => ModelStatus(
        loaded: json['loaded'] as bool,
        path: json['path'] as String?,
      );
}

// ── service ───────────────────────────────────────────────────────────────────

/// Typed HTTP client for the local FastAPI backend.
class ApiService {
  ApiService({required this.baseUrl, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<ModelDomain> loadModel(String path) async {
    final json = await _post('/model/load', {'path': path});
    return ModelDomain.fromJson(json);
  }

  Future<ModelDomain> getDomain() async {
    final json = await _get('/model/domain');
    return ModelDomain.fromJson(json);
  }

  Future<ModelStatus> getModelStatus() async {
    final json = await _get('/model/status');
    return ModelStatus.fromJson(json);
  }

  Future<PredictionResult> predict(Map<String, dynamic> values) async {
    final json = await _post('/predict', {'values': values});
    return PredictionResult.fromJson(json);
  }

  void dispose() => _client.close();

  // ── internals ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse('$baseUrl$path'));
    } catch (_) {
      throw const BackendUnavailableException();
    }
    return _decode(response);
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse('$baseUrl$path'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      throw const BackendUnavailableException();
    }
    return _decode(response);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 404) {
      throw ModelNotLoadedException(
        _errorDetail(response) ?? 'No model is currently loaded.',
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        _errorDetail(response) ?? 'Request failed (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw ApiException('Unexpected response format.',
        statusCode: response.statusCode);
  }

  String? _errorDetail(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        return decoded['detail'].toString();
      }
    } catch (_) {
      // response body wasn't JSON – fall through to null
    }
    return null;
  }
}
