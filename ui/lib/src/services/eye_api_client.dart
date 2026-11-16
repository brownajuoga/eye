import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/app_models.dart';

class WifiVisionFrameBundle {
  const WifiVisionFrameBundle({
    required this.vision,
    required this.sourcesStatus,
    required this.palette,
  });

  final WifiVisionState vision;
  final WifiSourcesStatus sourcesStatus;
  final String palette;
}

class EyeApiClient {
  EyeApiClient({
    http.Client? client,
    String? baseUrl,
  })  : _client = client ?? http.Client(),
        baseUrl = baseUrl ?? _resolveBaseUrl();

  final http.Client _client;
  final String baseUrl;

  String get mjpegStreamUrl => '$baseUrl/wifi/stream.mjpeg';

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

  Future<WifiVisionFrameBundle> fetchWifiVision() async {
    final response = await _client.get(Uri.parse('$baseUrl/wifi/vision'));
    _ensureSuccess(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final wifi = body['wifi'] as Map<String, dynamic>? ?? const {};
    return WifiVisionFrameBundle(
      vision: WifiVisionState.fromJson(body['vision'] as Map<String, dynamic>? ?? const {}),
      sourcesStatus: WifiSourcesStatus.fromJson(body['sources_status'] as Map<String, dynamic>? ?? const {}),
      palette: wifi['vision_palette'] as String? ?? 'night_vision',
    );
  }

  Future<DashboardSnapshot> controlSimulator(String action, {String? scenario}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wifi/simulator'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        if (scenario != null) 'scenario': scenario,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> controlHostScan(String action, {String? interfaceName}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wifi/host-scan'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        if (interfaceName != null && interfaceName.isNotEmpty) 'interface': interfaceName,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<void> updateAnchors(Map<String, Map<String, double>> anchors) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wifi/anchors'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'anchors': anchors}),
    );
    _ensureSuccess(response);
  }

  Future<DashboardSnapshot> updateControls(ControlState controls, {Map<String, dynamic>? wifiPatch}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/controls'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'mode': controls.mode,
        'detection_enabled': controls.detectionEnabled,
        'auto_mode': controls.autoMode,
        'confidence_threshold': controls.confidenceThreshold,
        'iou_threshold': controls.iouThreshold,
        if (wifiPatch != null) 'wifi': wifiPatch,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> updateWifiPatch(Map<String, dynamic> wifiPatch) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/controls'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'wifi': wifiPatch}),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> updateNodeMcuConfig(Map<String, dynamic> configPatch) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wifi/nodemcu/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(configPatch),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<void> sendNodeMcuCommand(String command) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wifi/nodemcu/command'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'command': command}),
    );
    _ensureSuccess(response);
  }

  Future<DashboardSnapshot> replayCapture(
    String action, {
    required String captureId,
    int frameIndex = 0,
    double speed = 1.0,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/wifi/replay'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': action,
        'capture_id': captureId,
        'frame_index': frameIndex,
        'speed': speed,
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
        'realtime_enabled': expert.realtimeEnabled,
        'realtime_only_important': expert.realtimeOnlyImportant,
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
        'known_aps': settings.knownAps,
      }),
    );
    _ensureSuccess(response);
    return fetchDashboard();
  }

  Future<DashboardSnapshot> uploadModel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['profile', 'yaml', 'json', 'pt', 'onnx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return fetchDashboard();
    }

    final file = result.files.single;
    if (file.bytes == null) {
      throw Exception('Could not read the selected file');
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
      allowedExtensions: const ['pcap', 'pcapng', 'csv', 'jsonl', 'ndjson', 'json', 'mp4', 'avi', 'mov'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return fetchDashboard();
    }

    final file = result.files.single;
    if (file.bytes == null) {
      throw Exception('Could not read the selected capture file');
    }

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/wifi/upload'))
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

  Future<DashboardSnapshot> updateSettings(SettingsConfig settings) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/settings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(settings.toPolicyPatch()),
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
