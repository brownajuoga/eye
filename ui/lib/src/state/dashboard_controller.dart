import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import '../services/eye_api_client.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({EyeApiClient? apiClient}) : _apiClient = apiClient ?? EyeApiClient();

  final EyeApiClient _apiClient;
  Timer? _poller;
  Duration _pollInterval = const Duration(seconds: 2);

  DashboardSnapshot? snapshot;
  bool loading = false;
  bool busy = false;
  String? error;

  void start() {
    refresh();
    _ensurePoller();
  }

  @override
  void dispose() {
    _poller?.cancel();
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
      _updatePollingFromSnapshot();
      error = null;
    } catch (exc) {
      error = exc.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> saveControls(ControlState controls) async {
    await _runBusy(() async {
      snapshot = await _apiClient.updateControls(controls);
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

  bool _pollingPaused = false;

  void setPollingPaused(bool paused) {
    if (_pollingPaused == paused) return;
    _pollingPaused = paused;
    if (paused) {
      _poller?.cancel();
      _poller = null;
    } else {
      _ensurePoller();
    }
  }

  void _ensurePoller() {
    _poller?.cancel();
    if (_pollingPaused) return;
    _poller = Timer.periodic(_pollInterval, (_) => refresh(silent: true));
  }

  void _updatePollingFromSnapshot() {
    final policy = snapshot?.policy ?? const <String, dynamic>{};
    final ui = policy['ui'] as Map<String, dynamic>? ?? const {};
    final seconds = (ui['refresh_interval_seconds'] as num?)?.toDouble() ?? 2.0;
    final nextInterval = Duration(milliseconds: (seconds * 1000).round().clamp(500, 60000));
    if (nextInterval != _pollInterval) {
      _pollInterval = nextInterval;
      _ensurePoller();
    }
  }
}
