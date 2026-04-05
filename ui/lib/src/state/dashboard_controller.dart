import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import '../services/eye_api_client.dart';

class DashboardController extends ChangeNotifier {
  DashboardController({EyeApiClient? apiClient}) : _apiClient = apiClient ?? EyeApiClient();

  final EyeApiClient _apiClient;
  Timer? _poller;

  DashboardSnapshot? snapshot;
  bool loading = false;
  bool busy = false;
  String? error;

  void start() {
    refresh();
    _poller ??= Timer.periodic(const Duration(seconds: 2), (_) => refresh(silent: true));
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
}
