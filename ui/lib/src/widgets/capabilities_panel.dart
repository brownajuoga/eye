import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class CapabilitiesPanel extends StatelessWidget {
  const CapabilitiesPanel({
    super.key,
    required this.snapshot,
  });

  final DashboardSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final capabilities = snapshot?.capabilities ?? const <String, dynamic>{};
    final inputSources = _stringList(capabilities['input_sources']);
    final detectionModules = _stringList(capabilities['detection_modules']);
    final expertBackends = _stringList(capabilities['expert_backends']);

    return PanelShell(
      title: 'RF Capabilities',
      subtitle: 'Active Wi-Fi sensing & NodeMCU edge modules',
      child: ListView(
        children: [
          _CapabilityGroup(title: 'Inputs', values: inputSources),
          const SizedBox(height: 12),
          _CapabilityGroup(title: 'RF Modules', values: detectionModules),
          const SizedBox(height: 12),
          _CapabilityGroup(title: 'Experts', values: expertBackends),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _flagChip('Live Vision', capabilities['supports_live_feed'] == true),
              _flagChip('PCAP/CSV Upload', capabilities['supports_video_upload'] == true),
              _flagChip('Hot Reload', capabilities['supports_policy_hot_reload'] == true),
              _flagChip('Profile Switch', capabilities['supports_runtime_model_switching'] == true),
              _flagChip('Multi-Node Sync', capabilities['supports_multicamera_sync'] == true),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tracking: ${capabilities['tracking_status'] ?? 'rf_ready'}\nCalibration: ${capabilities['calibration_status'] ?? 'anchors_ready'}',
          ),
        ],
      ),
    );
  }

  static List<String> _stringList(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    return raw.map((item) => item.toString()).toList();
  }

  Widget _flagChip(String label, bool enabled) {
    return Chip(
      label: Text(label),
      backgroundColor: enabled ? const Color(0xFFEAF4EE) : const Color(0xFFF1F3F2),
      side: BorderSide(color: enabled ? const Color(0xFF1E6F5C) : const Color(0xFFD9E0DB)),
    );
  }
}

class _CapabilityGroup extends StatelessWidget {
  const _CapabilityGroup({
    required this.title,
    required this.values,
  });

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.isEmpty
              ? const [Chip(label: Text('Unavailable'))]
              : values.map((value) => Chip(label: Text(value))).toList(),
        ),
      ],
    );
  }
}
