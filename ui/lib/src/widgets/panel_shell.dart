import 'package:flutter/material.dart';

class PanelShell extends StatelessWidget {
  const PanelShell({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleLarge),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
