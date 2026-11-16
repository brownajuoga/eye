import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../state/dashboard_controller.dart';
import '../widgets/capabilities_panel.dart';
import '../widgets/chat_panel.dart';
import '../widgets/control_panel.dart';
import '../widgets/expert_panel.dart';
import '../widgets/feeds_panel.dart';
import '../widgets/logs_panel.dart';
import '../widgets/model_manager_panel.dart';
import '../widgets/night_vision_cam_panel.dart';
import '../widgets/rules_panel.dart';
import '../widgets/settings_panel.dart';
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
        final vision = controller.liveVision ?? snapshot?.wifiVision ?? WifiVisionState.empty();
        final sourcesStatus = controller.liveSourcesStatus ?? snapshot?.wifiSourcesStatus ?? WifiSourcesStatus.empty();
        final controlState = snapshot?.controlState ??
            const ControlState(
              confidenceThreshold: 0.35,
              iouThreshold: 0.5,
              autoMode: true,
              detectionEnabled: true,
              mode: 'balanced',
            );
        final wifiSettings = snapshot?.wifiSettings ?? WifiPolicySettings.fromPolicy(const {});
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
                    : '${wifiSettings.mode.toUpperCase()} • ${snapshot.runtime.backend}\nSource: ${vision.sourceKind}',
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth > 1060;

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
                              if (controller.busy)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                                ),
                              if (!controller.busy)
                                IconButton(
                                  tooltip: 'Refresh Dashboard',
                                  onPressed: () => controller.refresh(),
                                  icon: const Icon(Icons.refresh),
                                ),
                            ],
                          ),
                          if (controller.error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                controller.error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: switch (section) {
                              AppSection.dashboard => wide
                                  ? Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: NightVisionCamPanel(
                                            vision: vision,
                                            sourcesStatus: sourcesStatus,
                                            palette: controller.activePalette,
                                            privacyMode: wifiSettings.privacyMode,
                                            onToggleHostScan: (start) => controller.controlHostScan(start ? 'start' : 'stop'),
                                            onControlSimulator: (action, scenario) =>
                                                controller.controlSimulator(action, scenario: scenario),
                                            onChangePalette: (pal) => controller.updateWifiPatch({'vision_palette': pal}),
                                            onTogglePrivacy: (priv) => controller.updateWifiPatch({'privacy_mode': priv}),
                                            onUpdateAnchors: controller.updateAnchors,
                                            onReplayAction: (act, cid, idx) =>
                                                controller.replayCapture(act, captureId: cid, frameIndex: idx),
                                            onRefresh: () => controller.refresh(),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          flex: 2,
                                          child: ListView(
                                            children: [
                                              StatsPanel(snapshot: snapshot, liveVision: vision),
                                              const SizedBox(height: 16),
                                              SizedBox(
                                                height: 300,
                                                child: CapabilitiesPanel(snapshot: snapshot),
                                              ),
                                              const SizedBox(height: 16),
                                              SizedBox(
                                                height: 360,
                                                child: LogsPanel(entries: snapshot?.logs ?? const []),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    )
                                  : ListView(
                                      children: [
                                        SizedBox(
                                          height: 480,
                                          child: NightVisionCamPanel(
                                            vision: vision,
                                            sourcesStatus: sourcesStatus,
                                            palette: controller.activePalette,
                                            privacyMode: wifiSettings.privacyMode,
                                            onToggleHostScan: (start) => controller.controlHostScan(start ? 'start' : 'stop'),
                                            onControlSimulator: (action, scenario) =>
                                                controller.controlSimulator(action, scenario: scenario),
                                            onChangePalette: (pal) => controller.updateWifiPatch({'vision_palette': pal}),
                                            onTogglePrivacy: (priv) => controller.updateWifiPatch({'privacy_mode': priv}),
                                            onUpdateAnchors: controller.updateAnchors,
                                            onReplayAction: (act, cid, idx) =>
                                                controller.replayCapture(act, captureId: cid, frameIndex: idx),
                                            onRefresh: () => controller.refresh(),
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        StatsPanel(snapshot: snapshot, liveVision: vision),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          height: 300,
                                          child: CapabilitiesPanel(snapshot: snapshot),
                                        ),
                                      ],
                                    ),
                              AppSection.settings => SettingsPanel(
                                  settings: SettingsConfig.fromPolicy(snapshot?.policy ?? const {}),
                                  availableFeeds: snapshot?.feeds ?? const [],
                                  onSave: controller.saveSettings,
                                ),
                              AppSection.models => ModelManagerPanel(
                                  models: snapshot?.models ?? const [],
                                  onActivate: (path) => controller.activateModel(path),
                                  onUpload: controller.uploadModel,
                                ),
                              AppSection.feeds => FeedsPanel(
                                  feeds: snapshot?.feeds ?? const [],
                                  nodemcuConfig: snapshot?.nodemcuConfig ?? NodeMcuConfig.fromJson(const {}),
                                  sourcesStatus: sourcesStatus,
                                  onSaveNodeMcu: controller.saveNodeMcuConfig,
                                  onSendNodeMcuCommand: controller.sendNodeMcuCommand,
                                  onToggleHostScan: (start) => controller.controlHostScan(start ? 'start' : 'stop'),
                                ),
                              AppSection.chat => ChatPanel(
                                  messages: snapshot?.chatHistory ?? const [],
                                  feeds: snapshot?.feeds ?? const [],
                                  defaultFeedId: SettingsConfig.fromPolicy(snapshot?.policy ?? const {}).defaultFeedId,
                                  onSend: controller.sendChatMessage,
                                ),
                              AppSection.controls => ControlPanel(
                                  controls: controlState,
                                  wifiSettings: wifiSettings,
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
                                  onReplayCapture: (act, cid, idx) async {
                                    await controller.replayCapture(act, captureId: cid, frameIndex: idx);
                                    if (mounted) {
                                      setState(() => section = AppSection.dashboard);
                                    }
                                  },
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
      AppSection.dashboard => 'Wi-Fi Night-Vision Cam',
      AppSection.settings => 'System Settings',
      AppSection.feeds => 'Sensors & NodeMCU',
      AppSection.chat => 'Expert RF Chat',
      AppSection.models => 'RF Sensing Profiles',
      AppSection.controls => 'RF & Privacy Controls',
      AppSection.expert => 'Expert & Trusted APs',
      AppSection.videos => 'Captures & Replay',
      AppSection.logs => 'Event Logs',
      AppSection.rules => 'Automation Rules',
    };
  }
}
