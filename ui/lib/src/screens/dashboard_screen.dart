import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../state/dashboard_controller.dart';
import '../widgets/control_panel.dart';
import '../widgets/capabilities_panel.dart';
import '../widgets/chat_panel.dart';
import '../widgets/expert_panel.dart';
import '../widgets/feeds_panel.dart';
import '../widgets/live_feed_panel.dart';
import '../widgets/logs_panel.dart';
import '../widgets/model_manager_panel.dart';
import '../widgets/rules_panel.dart';
import '../widgets/sidebar_navigation.dart';
import '../widgets/stats_panel.dart';
import '../widgets/video_analysis_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController controller;
  AppSection section = AppSection.dashboard;

  @override
  void initState() {
    super.initState();
    controller = DashboardController()..start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.snapshot;
        final controlState = snapshot?.controlState ??
            const ControlState(
              confidenceThreshold: 0.35,
              iouThreshold: 0.5,
              autoMode: true,
              detectionEnabled: true,
              mode: 'balanced',
            );
        final expert = snapshot == null ? ExpertSettings.fromPolicy(const {}) : ExpertSettings.fromPolicy(snapshot.policy);
        final watchlist = snapshot == null ? WatchlistSettings.fromPolicy(const {}) : WatchlistSettings.fromPolicy(snapshot.policy);

        return Scaffold(
          body: Row(
            children: [
              SidebarNavigation(
                activeSection: section,
                onSectionChanged: (next) => setState(() => section = next),
                statusText: snapshot == null
                    ? 'Connecting…'
                    : '${snapshot.runtime.effectiveMode} mode\n${snapshot.runtime.backend}',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 1100;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sectionTitle(section),
                                  style: Theme.of(context).textTheme.headlineMedium,
                                ),
                              ),
                              if (controller.busy) const CircularProgressIndicator(),
                              if (!controller.busy)
                                IconButton(
                                  onPressed: () => controller.refresh(),
                                  icon: const Icon(Icons.refresh),
                                ),
                            ],
                          ),
                          if (controller.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                controller.error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 20),
                          Expanded(
                            child: switch (section) {
                              AppSection.dashboard => wide
                                  ? Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: LiveFeedPanel(
                                            latestFrameUrl: snapshot?.latestFrameUrl,
                                            latestResult: snapshot?.latestResult,
                                            onRefresh: () => controller.refresh(),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 2,
                                          child: Column(
                                            children: [
                                              StatsPanel(snapshot: snapshot),
                                              const SizedBox(height: 16),
                                              Expanded(
                                                child: CapabilitiesPanel(snapshot: snapshot),
                                              ),
                                              const SizedBox(height: 16),
                                              Expanded(
                                                child: LogsPanel(entries: snapshot?.logs ?? const []),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        Expanded(
                                          child: LiveFeedPanel(
                                            latestFrameUrl: snapshot?.latestFrameUrl,
                                            latestResult: snapshot?.latestResult,
                                            onRefresh: () => controller.refresh(),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        StatsPanel(snapshot: snapshot),
                                        const SizedBox(height: 16),
                                        Expanded(
                                          child: CapabilitiesPanel(snapshot: snapshot),
                                        ),
                                      ],
                                    ),
                              AppSection.models => ModelManagerPanel(
                                  models: snapshot?.models ?? const [],
                                  onActivate: (path) => controller.activateModel(path),
                                  onUpload: controller.uploadModel,
                                ),
                              AppSection.feeds => FeedsPanel(
                                  feeds: snapshot?.feeds ?? const [],
                                ),
                              AppSection.chat => ChatPanel(
                                  messages: snapshot?.chatHistory ?? const [],
                                  feeds: snapshot?.feeds ?? const [],
                                  onSend: controller.sendChatMessage,
                                ),
                              AppSection.controls => ControlPanel(
                                  controls: controlState,
                                  onChanged: controller.saveControls,
                                ),
                              AppSection.expert => ExpertPanel(
                                  expert: expert,
                                  watchlist: watchlist,
                                  onSaveExpert: controller.saveExpert,
                                  onSaveWatchlist: controller.saveWatchlist,
                                ),
                              AppSection.videos => VideoAnalysisPanel(
                                  history: snapshot?.videoHistory ?? const [],
                                  onAnalyzeVideo: controller.analyzeVideo,
                                ),
                              AppSection.logs => LogsPanel(entries: snapshot?.logs ?? const []),
                              AppSection.rules => RulesPanel(
                                  rules: snapshot?.rules ?? const [],
                                  onRulesChanged: controller.saveRules,
                                ),
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String sectionTitle(AppSection section) {
    return switch (section) {
      AppSection.dashboard => 'System Dashboard',
      AppSection.feeds => 'Feed Monitor',
      AppSection.chat => 'Expert Chat',
      AppSection.models => 'Model Manager',
      AppSection.controls => 'Control Panel',
      AppSection.expert => 'Expert Controller',
      AppSection.videos => 'Video Analysis',
      AppSection.logs => 'Event Logs',
      AppSection.rules => 'Automation Rules',
    };
  }
}
