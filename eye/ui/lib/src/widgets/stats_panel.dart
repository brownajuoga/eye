import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({
    super.key,
    required this.snapshot,
  });

  final DashboardSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final runtime = snapshot?.runtime;
    final resources = runtime?.resources ?? const {};
    final capabilities = snapshot?.capabilities ?? const {};

    return SizedBox(
      height: 320,
      child: PanelShell(
        title: 'System Status',
        subtitle: 'Runtime health, resources, and detector backend',
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _StatTile(label: 'Backend', value: runtime?.backend ?? 'offline'),
            _StatTile(label: 'Mode', value: runtime?.effectiveMode ?? 'unknown'),
            _StatTile(label: 'RAM', value: '${runtime?.ramGb.toStringAsFixed(1) ?? '0.0'} GB'),
            _StatTile(label: 'CPU', value: '${runtime?.cpuCount ?? 0} cores'),
            _StatTile(label: 'Load', value: '${resources['load_avg'] ?? ['-', '-', '-']}'),
            _StatTile(label: 'Disk Free', value: '${resources['disk_free_gb'] ?? '-'} GB'),
            _StatTile(label: 'Tracking', value: '${capabilities['tracking_status'] ?? 'unknown'}'),
            _StatTile(label: 'Multicam', value: capabilities['supports_multicamera_sync'] == true ? 'ready' : 'planned'),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
