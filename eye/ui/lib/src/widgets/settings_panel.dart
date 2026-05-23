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
  final Map<String, TextEditingController> _routeModelControllers = {};
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
    widget.settings.taskRouting.forEach((intent, route) {
      if (_routeModelControllers.containsKey(intent)) {
        if (_routeModelControllers[intent]!.text != route.preferredModel) {
          _routeModelControllers[intent]!.text = route.preferredModel;
        }
      }
    });
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
    for (final controller in _routeModelControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Settings',
      subtitle: 'Global system configuration and customization',
      child: ListView(
        children: [
          Text('System', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(settings.mode),
            initialValue: settings.mode,
            decoration: const InputDecoration(labelText: 'Runtime Mode'),
            items: const [
              DropdownMenuItem(value: 'lightweight', child: Text('Lightweight')),
              DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
              DropdownMenuItem(value: 'performance', child: Text('Performance')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => settings = copy(mode: value));
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.detectionEnabled,
            onChanged: (value) => setState(() => settings = copy(detectionEnabled: value)),
            title: const Text('Detection Enabled'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.autoMode,
            onChanged: (value) => setState(() => settings = copy(autoMode: value)),
            title: const Text('Auto Mode'),
          ),
          const SizedBox(height: 12),
          _numberField(refreshIntervalController, 'UI Refresh Interval Seconds'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(settings.defaultFeedId),
            initialValue: settings.defaultFeedId,
            decoration: const InputDecoration(labelText: 'Default Feed'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Latest available feed')),
              ...widget.availableFeeds.map(
                (feed) => DropdownMenuItem(
                  value: feed.id,
                  child: Text(feed.name.isEmpty ? feed.id : feed.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() => settings = copy(defaultFeedId: value ?? '')),
          ),
          _slider('Confidence Threshold', settings.confidenceThreshold, (value) => setState(() => settings = copy(confidenceThreshold: value))),
          _slider('IoU Threshold', settings.iouThreshold, (value) => setState(() => settings = copy(iouThreshold: value))),
          const SizedBox(height: 20),
          Text('Video Analysis', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _numberField(videoIntervalController, 'Sample Interval Seconds'),
          const SizedBox(height: 12),
          _numberField(videoFramesController, 'Max Frames'),
          const SizedBox(height: 20),
          Text('Memory', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _numberField(memoryMaxController, 'Max Events'),
          const SizedBox(height: 12),
          _numberField(memoryRecentController, 'Recent Limit'),
          const SizedBox(height: 12),
          _numberField(memoryPatternController, 'Pattern Window'),
          const SizedBox(height: 20),
          Text('Expert', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Recommended for this project: `llava:7b-v1.6` for the best lightweight balance of scene awareness and instruction following on a 16GB machine.'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(settings.expertBackend),
            initialValue: settings.expertBackend,
            decoration: const InputDecoration(labelText: 'Expert Backend'),
            items: const [
              DropdownMenuItem(value: 'mock', child: Text('Mock')),
              DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
              DropdownMenuItem(value: 'transformers', child: Text('Transformers')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => settings = copy(expertBackend: value));
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ollamaController,
            decoration: const InputDecoration(labelText: 'Ollama Model'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: transformersController,
            decoration: const InputDecoration(labelText: 'Transformers Model'),
          ),
          const SizedBox(height: 12),
          _numberField(retriesController, 'Retries'),
          const SizedBox(height: 12),
          _numberField(timeoutController, 'Timeout Seconds'),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(settings.taskProfile),
            initialValue: settings.taskProfile,
            decoration: const InputDecoration(labelText: 'Task Profile'),
            items: const [
              DropdownMenuItem(value: 'general', child: Text('General')),
              DropdownMenuItem(value: 'security', child: Text('Security')),
              DropdownMenuItem(value: 'tracking', child: Text('Tracking')),
              DropdownMenuItem(value: 'loitering', child: Text('Loitering')),
              DropdownMenuItem(value: 'theft', child: Text('Theft')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => settings = copy(taskProfile: value));
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: missionController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Mission'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: taskController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Active Task'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: instructionsController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Operator Instructions'),
          ),
          const SizedBox(height: 20),
          Text('Task Routing', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('These policies let the operator agent choose mode/backend/model/feed strategy automatically for each task type.'),
          const SizedBox(height: 12),
          ...settings.taskRouting.entries.map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _routingEditor(entry.key, entry.value),
              )),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              await widget.onSave(
                copy(
                  videoSampleIntervalSeconds: double.tryParse(videoIntervalController.text) ?? settings.videoSampleIntervalSeconds,
                  videoMaxFrames: int.tryParse(videoFramesController.text) ?? settings.videoMaxFrames,
                  refreshIntervalSeconds: double.tryParse(refreshIntervalController.text) ?? settings.refreshIntervalSeconds,
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

  Widget _routingEditor(String intent, TaskRouteConfig route) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1E8E3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(intent, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('${intent}_mode_${route.mode}'),
              initialValue: route.mode,
              decoration: const InputDecoration(labelText: 'Mode'),
              items: const [
                DropdownMenuItem(value: 'lightweight', child: Text('Lightweight')),
                DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
                DropdownMenuItem(value: 'performance', child: Text('Performance')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings = copy(taskRouting: {
                      ...settings.taskRouting,
                      intent: route.copyWith(mode: value),
                    }));
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('${intent}_expert_${route.expertBackend}'),
              initialValue: route.expertBackend,
              decoration: const InputDecoration(labelText: 'Expert Backend'),
              items: const [
                DropdownMenuItem(value: 'mock', child: Text('Mock')),
                DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
                DropdownMenuItem(value: 'transformers', child: Text('Transformers')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings = copy(taskRouting: {
                      ...settings.taskRouting,
                      intent: route.copyWith(expertBackend: value),
                    }));
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _routeModelControllers.putIfAbsent(
                intent,
                () => TextEditingController(text: route.preferredModel),
              ),
              decoration: const InputDecoration(labelText: 'Preferred Model'),
              onChanged: (value) => settings = copy(taskRouting: {
                ...settings.taskRouting,
                intent: route.copyWith(preferredModel: value),
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('${intent}_strategy_${route.feedStrategy}'),
              initialValue: route.feedStrategy,
              decoration: const InputDecoration(labelText: 'Feed Strategy'),
              items: const [
                DropdownMenuItem(value: 'latest', child: Text('Latest')),
                DropdownMenuItem(value: 'selected', child: Text('Selected')),
                DropdownMenuItem(value: 'all_feeds', child: Text('All Feeds')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings = copy(taskRouting: {
                      ...settings.taskRouting,
                      intent: route.copyWith(feedStrategy: value),
                    }));
              },
            ),
          ],
        ),
      ),
    );
  }
}
