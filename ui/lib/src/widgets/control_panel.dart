import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class ControlPanel extends StatefulWidget {
  const ControlPanel({
    super.key,
    required this.controls,
    required this.onChanged,
  });

  final ControlState controls;
  final Future<void> Function(ControlState next) onChanged;

  @override
  State<ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends State<ControlPanel> {
  late ControlState controls;

  @override
  void initState() {
    super.initState();
    controls = widget.controls;
  }

  @override
  void didUpdateWidget(covariant ControlPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    controls = widget.controls;
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Detection Controls',
      subtitle: 'Tune confidence, IoU, mode, and automation',
      child: ListView(
        children: [
          _sliderTile(
            'Confidence Threshold',
            controls.confidenceThreshold,
            (value) => setState(() => controls = controls.copyWith(confidenceThreshold: value)),
          ),
          const SizedBox(height: 20),
          _sliderTile(
            'IoU Threshold',
            controls.iouThreshold,
            (value) => setState(() => controls = controls.copyWith(iouThreshold: value)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey(controls.mode),
            initialValue: controls.mode,
            decoration: const InputDecoration(labelText: 'Runtime Mode'),
            items: const [
              DropdownMenuItem(value: 'lightweight', child: Text('Lightweight')),
              DropdownMenuItem(value: 'balanced', child: Text('Balanced')),
              DropdownMenuItem(value: 'performance', child: Text('Performance')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => controls = controls.copyWith(mode: value));
            },
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            value: controls.detectionEnabled,
            onChanged: (value) => setState(() => controls = controls.copyWith(detectionEnabled: value)),
            title: const Text('Detection Enabled'),
            subtitle: const Text('Pause detection without disconnecting the feed'),
          ),
          SwitchListTile(
            value: controls.autoMode,
            onChanged: (value) => setState(() => controls = controls.copyWith(autoMode: value)),
            title: const Text('Auto Mode'),
            subtitle: const Text('Allow the system to adapt policy and model behavior automatically'),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => widget.onChanged(controls.copyWith(detectionEnabled: true)),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start'),
              ),
              OutlinedButton.icon(
                onPressed: () => widget.onChanged(controls.copyWith(detectionEnabled: false)),
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
              OutlinedButton.icon(
                onPressed: () => widget.onChanged(controls),
                icon: const Icon(Icons.sync),
                label: const Text('Apply Changes'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sliderTile(String label, double value, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(2)}'),
        Slider(value: value, min: 0.0, max: 1.0, onChanged: onChanged),
      ],
    );
  }
}
