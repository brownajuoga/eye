import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({
    super.key,
    required this.controls,
    required this.wifiSettings,
    required this.onChanged,
  });

  final ControlState controls;
  final WifiPolicySettings wifiSettings;
  final Future<void> Function(ControlState next, {Map<String, dynamic>? wifiPatch}) onChanged;

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  late ControlState controls;
  late WifiPolicySettings wifi;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    controls = widget.controls;
    wifi = widget.wifiSettings;
  }

  @override
  void didUpdateWidget(covariant ControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty) {
      controls = widget.controls;
      wifi = widget.wifiSettings;
    }
  }

  @override
  Widget build(BuildContext context) {
    const wifiModes = {'multi', 'wids', 'tripwire', 'occupancy', 'spectrum'};
    const palettes = {'night_vision', 'thermal', 'radar', 'spectrum'};
    const runtimeModes = {'lightweight', 'balanced', 'performance'};

    return PanelShell(
      title: 'RF & Surveillance Controls',
      subtitle: 'Switch intelligence modes, night-vision palette, privacy hashing & thresholds',
      child: ListView(
        children: [
          DropdownButtonFormField<String>(
            initialValue: wifiModes.contains(wifi.mode) ? wifi.mode : 'multi',
            decoration: const InputDecoration(labelText: 'Wi-Fi Intelligence Mode'),
            items: const [
              DropdownMenuItem(value: 'multi', child: Text('Multi-Mode (WIDS + Tripwire + Occupancy + Spectrum)')),
              DropdownMenuItem(value: 'wids', child: Text('WIDS Security (Deauth, Evil Twin, Canary AP)')),
              DropdownMenuItem(value: 'tripwire', child: Text('Motion Tripwire (Link RSSI Disturbance)')),
              DropdownMenuItem(value: 'occupancy', child: Text('Privacy Occupancy (Anonymous Crowd Estimation)')),
              DropdownMenuItem(value: 'spectrum', child: Text('2.4 GHz Spectrum & Congestion Audit')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                wifi = wifi.copyWith(mode: value);
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: palettes.contains(wifi.visionPalette) ? wifi.visionPalette : 'night_vision',
            decoration: const InputDecoration(labelText: 'Cam Display Palette'),
            items: const [
              DropdownMenuItem(value: 'night_vision', child: Text('Night Vision (Phosphor Green CCAM)')),
              DropdownMenuItem(value: 'thermal', child: Text('Thermal RF Heatmap')),
              DropdownMenuItem(value: 'radar', child: Text('Tactical Range Radar')),
              DropdownMenuItem(value: 'spectrum', child: Text('2.4 GHz Channel Spectrum')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                wifi = wifi.copyWith(visionPalette: value);
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: runtimeModes.contains(controls.mode) ? controls.mode : 'balanced',
            decoration: const InputDecoration(labelText: 'Compute / Sensitivity Tier'),
            items: const [
              DropdownMenuItem(value: 'lightweight', child: Text('Lightweight')),
              DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
              DropdownMenuItem(value: 'performance', child: Text('Performance')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _dirty = true;
                controls = controls.copyWith(mode: value);
              });
            },
          ),
          const SizedBox(height: 16),
          _sliderTile(
            'Tripwire Motion Z-Score Threshold',
            wifi.tripwireZThreshold.clamp(1.0, 5.0),
            1.0,
            5.0,
            (value) => setState(() {
              _dirty = true;
              wifi = wifi.copyWith(tripwireZThreshold: double.parse(value.toStringAsFixed(2)));
            }),
          ),
          const SizedBox(height: 10),
          _sliderTile(
            'Minimum Alert Confidence',
            controls.confidenceThreshold.clamp(0.0, 1.0),
            0.0,
            1.0,
            (value) => setState(() {
              _dirty = true;
              controls = controls.copyWith(confidenceThreshold: double.parse(value.toStringAsFixed(2)));
            }),
          ),
          const SizedBox(height: 10),
          Text('Deauth Flood Threshold (frames / 12s): ${wifi.deauthRateThreshold}'),
          Slider(
            value: wifi.deauthRateThreshold.toDouble().clamp(2, 30),
            min: 2,
            max: 30,
            divisions: 28,
            onChanged: (value) => setState(() {
              _dirty = true;
              wifi = wifi.copyWith(deauthRateThreshold: value.round());
            }),
          ),
          SwitchListTile(
            value: wifi.privacyMode,
            onChanged: (value) => setState(() {
              _dirty = true;
              wifi = wifi.copyWith(privacyMode: value);
            }),
            title: const Text('Privacy-First Mode (Anonymize MACs & Client SSIDs)'),
            subtitle: const Text('Keeps occupancy & motion sensing active while hashing device identifiers'),
          ),
          SwitchListTile(
            value: controls.detectionEnabled,
            onChanged: (value) => setState(() {
              _dirty = true;
              controls = controls.copyWith(detectionEnabled: value);
            }),
            title: const Text('Rule Evaluation Enabled'),
            subtitle: const Text('Pause alert triggers while keeping raw RF monitoring live'),
          ),
          SwitchListTile(
            value: controls.autoMode,
            onChanged: (value) => setState(() {
              _dirty = true;
              controls = controls.copyWith(autoMode: value);
            }),
            title: const Text('Adaptive Auto Mode'),
            subtitle: const Text('Let the agent loop adapt sensitivity and watchlists on repeated threats'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final next = controls.copyWith(detectionEnabled: true);
                  await widget.onChanged(next, wifiPatch: wifi.toJson());
                  setState(() => _dirty = false);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start & Apply'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final next = controls.copyWith(detectionEnabled: false);
                  await widget.onChanged(next, wifiPatch: wifi.toJson());
                  setState(() => _dirty = false);
                },
                icon: const Icon(Icons.stop),
                label: const Text('Pause Rules'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.onChanged(controls, wifiPatch: wifi.toJson());
                  setState(() => _dirty = false);
                },
                icon: const Icon(Icons.sync),
                label: const Text('Apply Changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sliderTile(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(2)}'),
        Slider(value: value, min: min, max: max, onChanged: onChanged),
      ],
    );
  }
}
