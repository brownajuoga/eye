import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class StatsPanel extends StatelessWidget {
  const StatsPanel({
    super.key,
    required this.snapshot,
    this.liveVision,
  });

  final DashboardSnapshot? snapshot;
  final WifiVisionState? liveVision;

  @override
  Widget build(BuildContext context) {
    final runtime = snapshot?.runtime;
    final vision = liveVision ?? snapshot?.wifiVision ?? WifiVisionState.empty();

    return SizedBox(
      height: 330,
      child: PanelShell(
        title: 'RF Telemetry',
        subtitle: 'Realtime 2.4 GHz spectrum, occupancy & link health',
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          childAspectRatio: 2.1,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _StatTile(
              label: 'Disturbance',
              value: '${vision.disturbance.toStringAsFixed(2)} (z=${vision.maxZScore.toStringAsFixed(1)})',
              highlight: vision.tripwireTriggered,
            ),
            _StatTile(
              label: 'Occupancy',
              value: '${vision.occupancyEstimate} (${vision.occupancyDensity})',
            ),
            _StatTile(
              label: 'Active APs / Clients',
              value: '${vision.activeAps} AP • ${vision.activeClients} STA',
            ),
            _StatTile(
              label: 'Deauth (12s)',
              value: '${vision.deauth12s} frames',
              highlight: vision.deauth12s > 0,
            ),
            _StatTile(
              label: 'Cleanest Channel',
              value: 'Ch ${vision.recommendedChannel} (${(vision.peakCongestion * 100).round()}% load)',
            ),
            _StatTile(
              label: 'Backend',
              value: runtime?.backend ?? 'offline',
            ),
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
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFDECEA) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ? Colors.red.shade300 : const Color(0xFFE1E8E3)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: highlight ? const Color(0xFFB2452F) : null,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
