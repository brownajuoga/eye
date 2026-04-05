import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_models.dart';

class EyeApiClient {
  EyeApiClient({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _resolveBaseUrl();

  final http.Client _client;
  final String baseUrl;

  static String _resolveBaseUrl() {
    const configured = String.fromEnvironment('EYE_API_BASE_URL', defaultValue: '');
    if (configured.isNotEmpty) {
      return configured;
    }

    if (kIsWeb) {
      final host = Uri.base.host.isEmpty ? '127.0.0.1' : Uri.base.host;
      final scheme = Uri.base.scheme.isEmpty ? 'http' : Uri.base.scheme;
      return '$scheme://$host:8080';
    }

    return 'http://127.0.0.1:8080';
  }

  Future<DashboardSnapshot> fetchDashboard() async {
    final response = await _client.get(Uri.parse('$baseUrl/dashboard'));
    _ensureSuccess(response);
    return DashboardSnapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>, baseUrl: baseUrl);
  }

  Future<DashboardSnapshot> updateControls(ControlState controls) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/controls'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'mode': controls.mode,
        'detection_enabled': controls.detectionEnabled,
        'auto_mode': controls.autoMode,
        'confidence_threshold': controls.confidenceThreshold,
        'iou_threshold': controls.iouThreshold,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> activateModel(String modelPath) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/models/activate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'model_path': modelPath}),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> updateRules(List<RuleItem> rules) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/rules'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'automation_rules': rules.map((rule) => rule.toJson()).toList()}),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> updateExpert(ExpertSettings expert) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/experts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'backend': expert.backend,
        'ollama_model': expert.ollamaModel,
        'transformers_model': expert.transformersModel,
        'max_retries': expert.maxRetries,
        'timeout_seconds': expert.timeoutSeconds,
        'task_profile': expert.taskProfile,
        'mission': expert.mission,
        'operator_instructions': expert.operatorInstructions,
        'active_task': expert.activeTask,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> updateWatchlist(WatchlistSettings settings) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/watchlist'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'watch_for': settings.watchFor,
        'ignore': settings.ignore,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> uploadModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pt', 'onnx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return fetchDashboard();
    }

    final file = result.files.single;
    if (file.bytes == null) {
      throw Exception('Could not read the selected model file');
    }

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/models/upload'))
      ..files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> analyzeVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'avi', 'mov', 'mkv', 'webm', 'mpeg', 'mpg', 'm4v'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return fetchDashboard();
    }

    final file = result.files.single;
    if (file.bytes == null) {
      throw Exception('Could not read the selected video');
    }

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/videos/analyze'))
      ..files.add(http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> sendChatMessage(String message, {String? feedId}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/chat/message'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'message': message,
        if (feedId != null && feedId.isNotEmpty) 'feed_id': feedId,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  static void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw Exception('Request failed (${response.statusCode}): ${response.body}');
  }
}
