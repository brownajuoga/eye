import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.availableFeeds,
    required this.onSave,
  });

  final SettingsConfig settings;
  final List<FeedSnapshot> availableFeeds;
  final Future<void> Function(SettingsConfig settings) onSave;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late SettingsConfig settings;
  late TextEditingController videoIntervalController;
  late TextEditingController videoFramesController;
  late TextEditingController refreshIntervalController;
  late TextEditingController memoryMaxController;
  late TextEditingController memoryRecentController;
  late TextEditingController memoryPatternController;
  late TextEditingController ollamaController;
  late TextEditingController transformersController;
  late TextEditingController retriesController;
  late TextEditingController timeoutController;
  late TextEditingController missionController;
  late TextEditingController instructionsController;
  late TextEditingController taskController;
  bool _dirty = false;

  static const _modes = {'lightweight', 'balanced', 'performance'};
  static const _backends = {'mock', 'ollama', 'transformers'};
  static const _profiles = {'wifi_security', 'tripwire', 'privacy_occupancy', 'spectrum_audit', 'general'};

  @override
  void initState() {
    super.initState();
    settings = widget.settings;
    videoIntervalController = TextEditingController(text: settings.videoSampleIntervalSeconds.toString());
    videoFramesController = TextEditingController(text: settings.videoMaxFrames.toString());
    refreshIntervalController = TextEditingController(text: settings.refreshIntervalSeconds.toString());
    memoryMaxController = TextEditingController(text: settings.memoryMaxEvents.toString());
    memoryRecentController = TextEditingController(text: settings.memoryRecentLimit.toString());
    memoryPatternController = TextEditingController(text: settings.memoryPatternWindow.toString());
    ollamaController = TextEditingController(text: settings.ollamaModel);
    transformersController = TextEditingController(text: settings.transformersModel);
    retriesController = TextEditingController(text: settings.maxRetries.toString());
    timeoutController = TextEditingController(text: settings.timeoutSeconds.toString());
    missionController = TextEditingController(text: settings.mission);
    instructionsController = TextEditingController(text: settings.operatorInstructions);
    taskController = TextEditingController(text: settings.activeTask);
  }

  @override
  void didUpdateWidget(covariant SettingsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty) {
      settings = widget.settings;
      videoIntervalController.text = settings.videoSampleIntervalSeconds.toString();
      videoFramesController.text = settings.videoMaxFrames.toString();
      refreshIntervalController.text = settings.refreshIntervalSeconds.toString();
      memoryMaxController.text = settings.memoryMaxEvents.toString();
      memoryRecentController.text = settings.memoryRecentLimit.toString();
      memoryPatternController.text = settings.memoryPatternWindow.toString();
      ollamaController.text = settings.ollamaModel;
      transformersController.text = settings.transformersModel;
      retriesController.text = settings.maxRetries.toString();
      timeoutController.text = settings.timeoutSeconds.toString();
      missionController.text = settings.mission;
      instructionsController.text = settings.operatorInstructions;
      taskController.text = settings.activeTask;
    }
  }

  @override
  void dispose() {
    videoIntervalController.dispose();
    videoFramesController.dispose();
    refreshIntervalController.dispose();
    memoryMaxController.dispose();
    memoryRecentController.dispose();
    memoryPatternController.dispose();
    ollamaController.dispose();
    transformersController.dispose();
    retriesController.dispose();
    timeoutController.dispose();
    missionController.dispose();
    instructionsController.dispose();
    taskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final validFeedIds = {'', ...widget.availableFeeds.map((f) => f.id)};
    final currentFeedId = validFeedIds.contains(settings.defaultFeedId) ? settings.defaultFeedId : '';

    return PanelShell(
      title: 'Settings',
      subtitle: 'Global Wi-Fi intelligence configuration, capture slicing & persistence',
      child: ListView(
        children: [
          Text('System', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(settings.mode),
            initialValue: _modes.contains(settings.mode) ? settings.mode : 'balanced',
            decoration: const InputDecoration(labelText: 'Runtime Mode'),
            items: const [
              DropdownMenuItem(value: 'lightweight', child: Text('Lightweight')),
              DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
              DropdownMenuItem(value: 'performance', child: Text('Performance')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                settings = copy(mode: value);
              });
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.detectionEnabled,
            onChanged: (value) => setState(() {
              _dirty = true;
              settings = copy(detectionEnabled: value);
            }),
            title: const Text('RF Rule Evaluation Enabled'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.autoMode,
            onChanged: (value) => setState(() {
              _dirty = true;
              settings = copy(autoMode: value);
            }),
            title: const Text('Adaptive Auto Mode'),
          ),
          const SizedBox(height: 12),
          _numberField(refreshIntervalController, 'Dashboard Refresh Interval Seconds'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(currentFeedId),
            initialValue: currentFeedId,
            decoration: const InputDecoration(labelText: 'Default Sensor Feed'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Latest available RF feed')),
              ...widget.availableFeeds.map(
                (feed) => DropdownMenuItem(
                  value: feed.id,
                  child: Text(feed.name.isEmpty ? feed.id : feed.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() {
              _dirty = true;
              settings = copy(defaultFeedId: value ?? '');
            }),
          ),
          _slider('Minimum Alert Confidence', settings.confidenceThreshold.clamp(0.0, 1.0), (value) => setState(() {
                _dirty = true;
                settings = copy(confidenceThreshold: value);
              })),
          const SizedBox(height: 20),
          Text('Capture Slicing & Replay', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _numberField(videoIntervalController, 'PCAP Time-Slice Bucket Seconds'),
          const SizedBox(height: 12),
          _numberField(videoFramesController, 'Max Replay Timeline Slices'),
          const SizedBox(height: 20),
          Text('Memory', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _numberField(memoryMaxController, 'Max Stored RF Events'),
          const SizedBox(height: 12),
          _numberField(memoryRecentController, 'Recent Memory Limit'),
          const SizedBox(height: 12),
          _numberField(memoryPatternController, 'Pattern Window'),
          const SizedBox(height: 20),
          Text('Expert Reasoning', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(settings.expertBackend),
            initialValue: _backends.contains(settings.expertBackend) ? settings.expertBackend : 'mock',
            decoration: const InputDecoration(labelText: 'Expert Backend'),
            items: const [
              DropdownMenuItem(value: 'mock', child: Text('Mock')),
              DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
              DropdownMenuItem(value: 'transformers', child: Text('Transformers')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                settings = copy(expertBackend: value);
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ollamaController,
            decoration: const InputDecoration(labelText: 'Ollama Model'),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: transformersController,
            decoration: const InputDecoration(labelText: 'Transformers Model'),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          _numberField(retriesController, 'Retries'),
          const SizedBox(height: 12),
          _numberField(timeoutController, 'Timeout Seconds'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(settings.taskProfile),
            initialValue: _profiles.contains(settings.taskProfile) ? settings.taskProfile : 'wifi_security',
            decoration: const InputDecoration(labelText: 'Task Profile'),
            items: const [
              DropdownMenuItem(value: 'wifi_security', child: Text('Wi-Fi Security')),
              DropdownMenuItem(value: 'tripwire', child: Text('Motion Tripwire')),
              DropdownMenuItem(value: 'privacy_occupancy', child: Text('Privacy Occupancy')),
              DropdownMenuItem(value: 'spectrum_audit', child: Text('Spectrum Audit')),
              DropdownMenuItem(value: 'general', child: Text('General')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                settings = copy(taskProfile: value);
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: missionController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Mission'),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: taskController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Active Task'),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: instructionsController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Operator Instructions'),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await widget.onSave(
                copy(
                  videoSampleIntervalSeconds:
                      double.tryParse(videoIntervalController.text) ?? settings.videoSampleIntervalSeconds,
                  videoMaxFrames: int.tryParse(videoFramesController.text) ?? settings.videoMaxFrames,
                  refreshIntervalSeconds:
                      double.tryParse(refreshIntervalController.text) ?? settings.refreshIntervalSeconds,
                  memoryMaxEvents: int.tryParse(memoryMaxController.text) ?? settings.memoryMaxEvents,
                  memoryRecentLimit: int.tryParse(memoryRecentController.text) ?? settings.memoryRecentLimit,
                  memoryPatternWindow: int.tryParse(memoryPatternController.text) ?? settings.memoryPatternWindow,
                  ollamaModel: ollamaController.text,
                  transformersModel: transformersController.text,
                  maxRetries: int.tryParse(retriesController.text) ?? settings.maxRetries,
                  timeoutSeconds: int.tryParse(timeoutController.text) ?? settings.timeoutSeconds,
                  mission: missionController.text,
                  operatorInstructions: instructionsController.text,
                  activeTask: taskController.text,
                ),
              );
              setState(() => _dirty = false);
            },
            child: const Text('Save Settings'),
          ),
        ],
      ),
    );
  }

  SettingsConfig copy({
    String? mode,
    bool? detectionEnabled,
    bool? autoMode,
    double? confidenceThreshold,
    double? iouThreshold,
    double? videoSampleIntervalSeconds,
    int? videoMaxFrames,
    double? refreshIntervalSeconds,
    String? defaultFeedId,
    int? memoryMaxEvents,
    int? memoryRecentLimit,
    int? memoryPatternWindow,
    String? expertBackend,
    String? ollamaModel,
    String? transformersModel,
    int? maxRetries,
    int? timeoutSeconds,
    String? taskProfile,
    String? mission,
    String? operatorInstructions,
    String? activeTask,
    Map<String, TaskRouteConfig>? taskRouting,
  }) {
    return SettingsConfig(
      mode: mode ?? settings.mode,
      detectionEnabled: detectionEnabled ?? settings.detectionEnabled,
      autoMode: autoMode ?? settings.autoMode,
      confidenceThreshold: confidenceThreshold ?? settings.confidenceThreshold,
      iouThreshold: iouThreshold ?? settings.iouThreshold,
      videoSampleIntervalSeconds: videoSampleIntervalSeconds ?? settings.videoSampleIntervalSeconds,
      videoMaxFrames: videoMaxFrames ?? settings.videoMaxFrames,
      refreshIntervalSeconds: refreshIntervalSeconds ?? settings.refreshIntervalSeconds,
      defaultFeedId: defaultFeedId ?? settings.defaultFeedId,
      memoryMaxEvents: memoryMaxEvents ?? settings.memoryMaxEvents,
      memoryRecentLimit: memoryRecentLimit ?? settings.memoryRecentLimit,
      memoryPatternWindow: memoryPatternWindow ?? settings.memoryPatternWindow,
      expertBackend: expertBackend ?? settings.expertBackend,
      ollamaModel: ollamaModel ?? settings.ollamaModel,
      transformersModel: transformersModel ?? settings.transformersModel,
      maxRetries: maxRetries ?? settings.maxRetries,
      timeoutSeconds: timeoutSeconds ?? settings.timeoutSeconds,
      taskProfile: taskProfile ?? settings.taskProfile,
      mission: mission ?? settings.mission,
      operatorInstructions: operatorInstructions ?? settings.operatorInstructions,
      activeTask: activeTask ?? settings.activeTask,
      taskRouting: taskRouting ?? settings.taskRouting,
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => _dirty = true,
    );
  }

  Widget _slider(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(2)}'),
        Slider(value: value, min: 0.0, max: 1.0, onChanged: onChanged),
      ],
    );
  }
}
