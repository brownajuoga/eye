import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class FeedsPanel extends StatelessWidget {
  const FeedsPanel({
    super.key,
    required this.feeds,
  });

  final List<FeedSnapshot> feeds;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Feeds',
      subtitle: 'Live and recorded sources tracked by the backend',
      child: feeds.isEmpty
          ? const Center(child: Text('No feeds registered yet. Start Scout with one or more sources.'))
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisExtent: 320,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: feeds.length,
              itemBuilder: (context, index) {
                final feed = feeds[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE1E8E3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(feed.name.isEmpty ? feed.id : feed.name, style: Theme.of(context).textTheme.titleMedium),
                            ),
                            Chip(label: Text(feed.live ? 'Live' : 'Recorded')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: feed.frameUrl == null
                                ? const ColoredBox(
                                    color: Color(0xFFEEF2EF),
                                    child: Center(child: Text('No frame yet')),
                                  )
                                : Image.network(
                                    feed.frameUrl!,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const ColoredBox(
                                      color: Color(0xFFEEF2EF),
                                      child: Center(child: Text('Frame unavailable')),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text('Detections: ${feed.detections.map((item) => item.label).join(', ').ifEmpty('none')}'),
                        const SizedBox(height: 6),
                        Text('Event: ${feed.eventReason.ifEmpty('No event reasoning yet')}'),
                        const SizedBox(height: 4),
                        Text('Expert: ${feed.expertReason.ifEmpty('No expert decision yet')}'),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
