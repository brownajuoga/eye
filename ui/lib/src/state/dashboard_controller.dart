import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import '../services/eye_api_client.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({EyeApiClient? apiClient}) : _apiClient = apiClient ?? EyeApiClient();

  final EyeApiClient _apiClient;
  Timer? _poller;
  Timer? _visionPoller;
  Duration _pollInterval = const Duration(milliseconds: 1500);

  DashboardSnapshot? snapshot;
  WifiVisionState? liveVision;
  WifiSourcesStatus? liveSourcesStatus;
  String activePalette = 'night_vision';
  bool loading = false;
  bool busy = false;
  String? error;

  String get mjpegStreamUrl => _apiClient.mjpegStreamUrl;

  void start() {
    refresh();
    _ensurePoller();
    _ensureVisionPoller();
  }

  @override
  void dispose() {
    _poller?.cancel();
    _visionPoller?.cancel();
    super.dispose();
  }

  Future<void> refresh({bool silent = false}) async {
    if (loading && silent) {
      return;
    }
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      snapshot = await _apiClient.fetchDashboard();
      liveVision = snapshot?.wifiVision;
      liveSourcesStatus = snapshot?.wifiSourcesStatus;
      activePalette = snapshot?.wifiSettings.visionPalette ?? activePalette;
      _updatePollingFromSnapshot();
      error = null;
    } catch (exc) {
      error = exc.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> pollVisionOnly() async {
    try {
      final bundle = await _apiClient.fetchWifiVision();
      liveVision = bundle.vision;
      liveSourcesStatus = bundle.sourcesStatus;
      activePalette = bundle.palette;
      notifyListeners();
    } catch (_) {
      // Keep last known vision frame quietly when idle/offline
    }
  }

  Future<void> controlSimulator(String action, {String? scenario}) async {
    await _runBusy(() async {
      snapshot = await _apiClient.controlSimulator(action, scenario: scenario);
      liveVision = snapshot?.wifiVision;
      liveSourcesStatus = snapshot?.wifiSourcesStatus;
    });
  }

  Future<void> controlHostScan(String action, {String? interfaceName}) async {
    await _runBusy(() async {
      snapshot = await _apiClient.controlHostScan(action, interfaceName: interfaceName);
      liveVision = snapshot?.wifiVision;
      liveSourcesStatus = snapshot?.wifiSourcesStatus;
    });
  }

  Future<void> updateWifiPatch(Map<String, dynamic> patch) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateWifiPatch(patch);
      liveVision = snapshot?.wifiVision;
      activePalette = snapshot?.wifiSettings.visionPalette ?? activePalette;
    });
  }

  Future<void> updateAnchors(Map<String, Map<String, double>> anchors) async {
    try {
      await _apiClient.updateAnchors(anchors);
      await pollVisionOnly();
    } catch (exc) {
      error = exc.toString();
      notifyListeners();
    }
  }

  Future<void> saveControls(ControlState controls, {Map<String, dynamic>? wifiPatch}) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateControls(controls, wifiPatch: wifiPatch);
      liveVision = snapshot?.wifiVision;
      activePalette = snapshot?.wifiSettings.visionPalette ?? activePalette;
    });
  }

  Future<void> saveNodeMcuConfig(Map<String, dynamic> configPatch) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateNodeMcuConfig(configPatch);
    });
  }

  Future<void> sendNodeMcuCommand(String command) async {
    await _runBusy(() async {
      await _apiClient.sendNodeMcuCommand(command);
      snapshot = await _apiClient.fetchDashboard();
    });
  }

  Future<void> replayCapture(
    String action, {
    required String captureId,
    int frameIndex = 0,
    double speed = 1.0,
  }) async {
    await _runBusy(() async {
      snapshot = await _apiClient.replayCapture(
        action,
        captureId: captureId,
        frameIndex: frameIndex,
        speed: speed,
      );
      liveVision = snapshot?.wifiVision;
      liveSourcesStatus = snapshot?.wifiSourcesStatus;
    });
  }

  Future<void> activateModel(String modelPath) async {
    await _runBusy(() async {
      snapshot = await _apiClient.activateModel(modelPath);
    });
  }

  Future<void> uploadModel() async {
    await _runBusy(() async {
      snapshot = await _apiClient.uploadModel();
    });
  }

  Future<void> saveRules(List<RuleItem> rules) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateRules(rules);
    });
  }

  Future<void> saveExpert(ExpertSettings expert) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateExpert(expert);
    });
  }

  Future<void> saveWatchlist(WatchlistSettings settings) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateWatchlist(settings);
    });
  }

  Future<void> analyzeVideo() async {
    await _runBusy(() async {
      snapshot = await _apiClient.analyzeVideo();
      liveVision = snapshot?.wifiVision;
    });
  }

  Future<void> sendChatMessage(String message, {String? feedId}) async {
    await _runBusy(() async {
      snapshot = await _apiClient.sendChatMessage(message, feedId: feedId);
    });
  }

  Future<void> saveSettings(SettingsConfig settings) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateSettings(settings);
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      await action();
      error = null;
    } catch (exc) {
      error = exc.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _ensurePoller() {
    _poller?.cancel();
    _poller = Timer.periodic(_pollInterval, (_) => refresh(silent: true));
  }

  void _ensureVisionPoller() {
    _visionPoller?.cancel();
    _visionPoller = Timer.periodic(const Duration(milliseconds: 420), (_) => pollVisionOnly());
  }

  void _updatePollingFromSnapshot() {
    final policy = snapshot?.policy ?? const <String, dynamic>{};
    final ui = policy['ui'] as Map<String, dynamic>? ?? const {};
    final seconds = (ui['refresh_interval_seconds'] as num?)?.toDouble() ?? 1.5;
    final nextInterval = Duration(milliseconds: (seconds * 1000).round().clamp(500, 60000));
    if (nextInterval != _pollInterval) {
      _pollInterval = nextInterval;
      _ensurePoller();
    }
  }
}
