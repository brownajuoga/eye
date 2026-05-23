import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class LogsPanel extends StatelessWidget {
  const LogsPanel({
    super.key,
    required this.entries,
  });

  final List<LogEntry> entries;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Event Log',
      subtitle: 'Detection events, errors, and AI decisions',
      child: entries.isEmpty
          ? const Center(child: Text('No events yet'))
          : ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (context, index) => const Divider(height: 24),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: _colorFor(entry.level),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.message),
                          const SizedBox(height: 4),
                          Text('${entry.timestamp} • ${entry.level}', style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  Color _colorFor(String level) {
    switch (level) {
      case 'decision':
        return const Color(0xFFB2452F);
      case 'system':
        return const Color(0xFF1E6F5C);
      case 'error':
        return const Color(0xFFAA2E25);
      default:
        return const Color(0xFF4C5B56);
    }
  }
}
