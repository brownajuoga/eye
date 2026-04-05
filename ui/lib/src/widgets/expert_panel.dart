import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class ExpertPanel extends StatefulWidget {
  const ExpertPanel({
    super.key,
    required this.expert,
    required this.watchlist,
    required this.onSaveExpert,
    required this.onSaveWatchlist,
  });

  final ExpertSettings expert;
  final WatchlistSettings watchlist;
  final Future<void> Function(ExpertSettings expert) onSaveExpert;
  final Future<void> Function(WatchlistSettings settings) onSaveWatchlist;

  @override
  State<ExpertPanel> createState() => _ExpertPanelState();
}

class _ExpertPanelState extends State<ExpertPanel> {
  late ExpertSettings expert;
  late TextEditingController watchController;
  late TextEditingController ignoreController;
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
    expert = widget.expert;
    watchController = TextEditingController(text: widget.watchlist.watchFor.join(', '));
    ignoreController = TextEditingController(text: widget.watchlist.ignore.join(', '));
    ollamaController = TextEditingController(text: widget.expert.ollamaModel);
    transformersController = TextEditingController(text: widget.expert.transformersModel);
    retriesController = TextEditingController(text: widget.expert.maxRetries.toString());
    timeoutController = TextEditingController(text: widget.expert.timeoutSeconds.toString());
    missionController = TextEditingController(text: widget.expert.mission);
    instructionsController = TextEditingController(text: widget.expert.operatorInstructions);
    taskController = TextEditingController(text: widget.expert.activeTask);
  }

  @override
  void didUpdateWidget(covariant ExpertPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    expert = widget.expert;
    watchController.text = widget.watchlist.watchFor.join(', ');
    ignoreController.text = widget.watchlist.ignore.join(', ');
    ollamaController.text = widget.expert.ollamaModel;
    transformersController.text = widget.expert.transformersModel;
    retriesController.text = widget.expert.maxRetries.toString();
    timeoutController.text = widget.expert.timeoutSeconds.toString();
    missionController.text = widget.expert.mission;
    instructionsController.text = widget.expert.operatorInstructions;
    taskController.text = widget.expert.activeTask;
  }

  @override
  void dispose() {
    watchController.dispose();
    ignoreController.dispose();
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
    return PanelShell(
      title: 'Expert Controller',
      subtitle: 'Choose backend, task profile, and watchlist behavior',
      child: ListView(
        children: [
          DropdownButtonFormField<String>(
            initialValue: expert.backend,
            decoration: const InputDecoration(labelText: 'Expert Backend'),
            items: const [
              DropdownMenuItem(value: 'mock', child: Text('Mock')),
              DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
              DropdownMenuItem(value: 'transformers', child: Text('Transformers')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => expert = expert.copyWith(backend: value));
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: expert.taskProfile,
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
              setState(() => expert = expert.copyWith(taskProfile: value));
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ollamaController,
            decoration: const InputDecoration(labelText: 'Ollama Model'),
            onChanged: (value) => expert = expert.copyWith(ollamaModel: value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: transformersController,
            decoration: const InputDecoration(labelText: 'Transformers Model'),
            onChanged: (value) => expert = expert.copyWith(transformersModel: value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: missionController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Mission'),
            onChanged: (value) => expert = expert.copyWith(mission: value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: taskController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Active Task'),
            onChanged: (value) => expert = expert.copyWith(activeTask: value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: instructionsController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Operator Instructions'),
            onChanged: (value) => expert = expert.copyWith(operatorInstructions: value),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Retries'),
                  keyboardType: TextInputType.number,
                  controller: retriesController,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      expert = expert.copyWith(maxRetries: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Timeout Seconds'),
                  keyboardType: TextInputType.number,
                  controller: timeoutController,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      expert = expert.copyWith(timeoutSeconds: parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          TextField(
            controller: watchController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Watch For (comma separated)'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: ignoreController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Ignore (comma separated)'),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton(
                onPressed: () => widget.onSaveExpert(
                  expert.copyWith(
                    ollamaModel: ollamaController.text,
                    transformersModel: transformersController.text,
                    maxRetries: int.tryParse(retriesController.text) ?? expert.maxRetries,
                    timeoutSeconds: int.tryParse(timeoutController.text) ?? expert.timeoutSeconds,
                    mission: missionController.text,
                    operatorInstructions: instructionsController.text,
                    activeTask: taskController.text,
                  ),
                ),
                child: const Text('Save Expert'),
              ),
              OutlinedButton(
                onPressed: () => widget.onSaveWatchlist(
                  WatchlistSettings(
                    watchFor: _splitCsv(watchController.text),
                    ignore: _splitCsv(ignoreController.text),
                  ),
                ),
                child: const Text('Save Watchlist'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _splitCsv(String raw) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
