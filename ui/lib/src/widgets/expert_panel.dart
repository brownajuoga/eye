import 'dart:convert';

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
  late TextEditingController knownApsController;
  late TextEditingController ollamaController;
  late TextEditingController transformersController;
  late TextEditingController retriesController;
  late TextEditingController timeoutController;
  late TextEditingController missionController;
  late TextEditingController instructionsController;
  late TextEditingController taskController;
  bool _dirty = false;

  static const _backends = {'mock', 'ollama', 'transformers'};
  static const _profiles = {'wifi_security', 'tripwire', 'privacy_occupancy', 'spectrum_audit', 'general'};

  @override
  void initState() {
    super.initState();
    expert = widget.expert;
    watchController = TextEditingController(text: widget.watchlist.watchFor.join(', '));
    ignoreController = TextEditingController(text: widget.watchlist.ignore.join(', '));
    knownApsController = TextEditingController(text: _formatKnownAps(widget.watchlist.knownAps));
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
    if (!_dirty) {
      expert = widget.expert;
      watchController.text = widget.watchlist.watchFor.join(', ');
      ignoreController.text = widget.watchlist.ignore.join(', ');
      knownApsController.text = _formatKnownAps(widget.watchlist.knownAps);
      ollamaController.text = widget.expert.ollamaModel;
      transformersController.text = widget.expert.transformersModel;
      retriesController.text = widget.expert.maxRetries.toString();
      timeoutController.text = widget.expert.timeoutSeconds.toString();
      missionController.text = widget.expert.mission;
      instructionsController.text = widget.expert.operatorInstructions;
      taskController.text = widget.expert.activeTask;
    }
  }

  @override
  void dispose() {
    watchController.dispose();
    ignoreController.dispose();
    knownApsController.dispose();
    ollamaController.dispose();
    transformersController.dispose();
    retriesController.dispose();
    timeoutController.dispose();
    missionController.dispose();
    instructionsController.dispose();
    taskController.dispose();
    super.dispose();
  }

  static String _formatKnownAps(Map<String, dynamic> raw) {
    if (raw.isEmpty) return '';
    return raw.entries.map((e) {
      final vals = e.value is List ? (e.value as List).join('|') : e.value.toString();
      return '${e.key}=$vals';
    }).join(', ');
  }

  static Map<String, dynamic> _parseKnownAps(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return {};
    if (trimmed.startsWith('{')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }
    final out = <String, dynamic>{};
    for (final entry in trimmed.split(',')) {
      final parts = entry.split('=');
      if (parts.length != 2) continue;
      final ssid = parts[0].trim();
      final bssids = parts[1].split('|').map((e) => e.trim().toLowerCase()).where((e) => e.isNotEmpty).toList();
      if (ssid.isNotEmpty && bssids.isNotEmpty) {
        out[ssid] = bssids;
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Expert & Watchlist',
      subtitle: 'Configure reasoning backend, RF watchlists & Trusted AP BSSIDs (Evil Twin guard)',
      child: ListView(
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey(expert.backend),
            initialValue: _backends.contains(expert.backend) ? expert.backend : 'mock',
            decoration: const InputDecoration(labelText: 'Expert Backend'),
            items: const [
              DropdownMenuItem(value: 'mock', child: Text('Mock (Deterministic RF Reasoner)')),
              DropdownMenuItem(value: 'ollama', child: Text('Ollama')),
              DropdownMenuItem(value: 'transformers', child: Text('Transformers')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                expert = expert.copyWith(backend: value);
              });
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: expert.realtimeEnabled,
            title: const Text('Realtime Expert Review'),
            onChanged: (value) => setState(() {
              _dirty = true;
              expert = expert.copyWith(realtimeEnabled: value);
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: expert.realtimeOnlyImportant,
            title: const Text('Important RF Events Only'),
            onChanged: expert.realtimeEnabled
                ? (value) => setState(() {
                      _dirty = true;
                      expert = expert.copyWith(realtimeOnlyImportant: value);
                    })
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(expert.taskProfile),
            initialValue: _profiles.contains(expert.taskProfile) ? expert.taskProfile : 'wifi_security',
            decoration: const InputDecoration(labelText: 'Task Profile'),
            items: const [
              DropdownMenuItem(value: 'wifi_security', child: Text('Wi-Fi Security (WIDS)')),
              DropdownMenuItem(value: 'tripwire', child: Text('Motion Tripwire')),
              DropdownMenuItem(value: 'privacy_occupancy', child: Text('Privacy Occupancy')),
              DropdownMenuItem(value: 'spectrum_audit', child: Text('Spectrum Health Audit')),
              DropdownMenuItem(value: 'general', child: Text('General')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                expert = expert.copyWith(taskProfile: value);
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ollamaController,
            decoration: const InputDecoration(labelText: 'Ollama Model'),
            onChanged: (value) {
              _dirty = true;
              expert = expert.copyWith(ollamaModel: value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: transformersController,
            decoration: const InputDecoration(labelText: 'Transformers Model'),
            onChanged: (value) {
              _dirty = true;
              expert = expert.copyWith(transformersModel: value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: missionController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Mission'),
            onChanged: (value) {
              _dirty = true;
              expert = expert.copyWith(mission: value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: taskController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Active Task'),
            onChanged: (value) {
              _dirty = true;
              expert = expert.copyWith(activeTask: value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: instructionsController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Operator Instructions'),
            onChanged: (value) {
              _dirty = true;
              expert = expert.copyWith(operatorInstructions: value);
            },
          ),
          const SizedBox(height: 12),
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
                      _dirty = true;
                      expert = expert.copyWith(maxRetries: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Timeout (s)'),
                  keyboardType: TextInputType.number,
                  controller: timeoutController,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null) {
                      _dirty = true;
                      expert = expert.copyWith(timeoutSeconds: parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () async {
                await widget.onSaveExpert(expert);
                setState(() => _dirty = false);
              },
              child: const Text('Save Expert Settings'),
            ),
          ),
          const Divider(height: 32),
          Text('RF Watchlist & Evil Twin Protection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: watchController,
            decoration: const InputDecoration(
              labelText: 'Watch RF Signals (comma separated)',
              hintText: 'deauth_flood, evil_twin, rssi_tripwire_motion, canary_hit, beacon_spam',
            ),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ignoreController,
            decoration: const InputDecoration(labelText: 'Ignore Signals (comma separated)'),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: knownApsController,
            decoration: const InputDecoration(
              labelText: 'Trusted APs (SSID=BSSID1|BSSID2, ...)',
              hintText: 'pinnacle=50:14:c1:e3:76:1c, Home_Core_AP=50:14:c1:e3:76:1c',
            ),
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () async {
                final watchFor = watchController.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
                final ignore = ignoreController.text.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
                final knownAps = _parseKnownAps(knownApsController.text);
                await widget.onSaveWatchlist(WatchlistSettings(watchFor: watchFor, ignore: ignore, knownAps: knownAps));
                setState(() => _dirty = false);
              },
              child: const Text('Save Watchlist & Trusted APs'),
            ),
          ),
        ],
      ),
    );
  }
}
