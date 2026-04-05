import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class VideoAnalysisPanel extends StatelessWidget {
  const VideoAnalysisPanel({
    super.key,
    required this.history,
    required this.onAnalyzeVideo,
  });

  final List<VideoAnalysisResult> history;
  final Future<void> Function() onAnalyzeVideo;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Video Analysis',
      subtitle: 'Upload a recorded video and get timeline analysis through the same backend',
      trailing: FilledButton(
        onPressed: () => onAnalyzeVideo(),
        child: const Text('Analyze Video'),
      ),
      child: history.isEmpty
          ? const Center(child: Text('No uploaded video analyses yet'))
          : ListView.separated(
              itemCount: history.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final item = history[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE1E8E3)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    title: Text(item.filename),
                    subtitle: Text(
                      '${item.createdAt}\nFrames: ${item.framesProcessed} • Action: ${item.dominantAction}\nLabels: ${item.aggregatedLabels.join(', ')}',
                    ),
                  ),
                );
              },
            ),
    );
  }
}
