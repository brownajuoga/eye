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
      color: const Color(0xFF15362F),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'eye',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Control Center',
            style: TextStyle(color: Color(0xFFB8CEC7)),
          ),
          const SizedBox(height: 28),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ...AppSection.values.map((section) {
                    final selected = section == activeSection;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        tileColor: selected ? const Color(0xFF1E6F5C) : Colors.transparent,
                        title: Text(
                          label(section),
                          style: TextStyle(color: selected ? Colors.white : const Color(0xFFDCE8E3)),
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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF21463E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('System', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(statusText, style: const TextStyle(color: Color(0xFFB8CEC7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String label(AppSection section) {
    return switch (section) {
      AppSection.dashboard => 'Dashboard',
      AppSection.settings => 'Settings',
      AppSection.feeds => 'Feeds',
      AppSection.chat => 'Chat',
      AppSection.models => 'Models',
      AppSection.controls => 'Controls',
      AppSection.expert => 'Expert',
      AppSection.videos => 'Videos',
      AppSection.logs => 'Logs',
      AppSection.rules => 'Rules',
    };
  }
}
