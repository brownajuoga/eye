import 'package:flutter/material.dart';

import '../models/app_models.dart';

class SidebarNavigation extends StatelessWidget {
  const SidebarNavigation({
    super.key,
    required this.activeSection,
    required this.onSectionChanged,
    required this.statusText,
  });

  final AppSection activeSection;
  final ValueChanged<AppSection> onSectionChanged;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: const Color(0xFF0E261E),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'eye',
            style: TextStyle(
              color: Color(0xFF56FFB0),
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Wi-Fi RF Control Center',
            style: TextStyle(color: Color(0xFFAAD2C0), fontSize: 12),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...AppSection.values.map((section) {
                    final selected = section == activeSection;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          _icon(section),
                          size: 18,
                          color: selected ? const Color(0xFF56FFB0) : const Color(0xFFB5D1C4),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        tileColor: selected ? const Color(0xFF1A4B3B) : Colors.transparent,
                        title: Text(
                          label(section),
                          style: TextStyle(
                            color: selected ? Colors.white : const Color(0xFFDCE8E3),
                            fontSize: 13.5,
                          ),
                        ),
                        onTap: () => onSectionChanged(section),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF173A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x3356FFB0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('RF Engine', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(statusText, style: const TextStyle(color: Color(0xFFB8CEC7), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _icon(AppSection section) {
    return switch (section) {
      AppSection.dashboard => Icons.nightlight_round,
      AppSection.feeds => Icons.router,
      AppSection.videos => Icons.upload_file,
      AppSection.controls => Icons.tune,
      AppSection.rules => Icons.rule,
      AppSection.models => Icons.layers,
      AppSection.expert => Icons.security,
      AppSection.chat => Icons.chat_bubble_outline,
      AppSection.logs => Icons.receipt_long,
      AppSection.settings => Icons.settings,
    };
  }

  String label(AppSection section) {
    return switch (section) {
      AppSection.dashboard => 'Night-Vision Cam',
      AppSection.feeds => 'Sensors & NodeMCU',
      AppSection.videos => 'Captures & Replay',
      AppSection.controls => 'RF Controls',
      AppSection.rules => 'Automation Rules',
      AppSection.models => 'RF Profiles',
      AppSection.expert => 'Expert & Watchlist',
      AppSection.chat => 'Expert Chat',
      AppSection.logs => 'Event Logs',
      AppSection.settings => 'Settings',
    };
  }
}
