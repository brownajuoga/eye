import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class LiveFeedPanel extends StatelessWidget {
  const LiveFeedPanel({
    super.key,
    required this.latestFrameUrl,
    required this.latestResult,
    required this.onRefresh,
  });

  final String? latestFrameUrl;
  final LatestResult? latestResult;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Live Feed',
      subtitle: 'Latest analyzed frame with detection overlays',
      trailing: FilledButton(
        onPressed: () => onRefresh(),
        child: const Text('Refresh'),
      ),
      child: latestFrameUrl == null || latestResult?.frame == null
          ? const Center(child: Text('No frame received yet from the scout'))
          : LayoutBuilder(
              builder: (context, constraints) {
                final frame = latestResult!.frame!;
                final frameWidth = frame.width.toDouble();
                final frameHeight = frame.height.toDouble();
                final scale = math.min(
                  constraints.maxWidth / frameWidth,
                  constraints.maxHeight / frameHeight,
                );
                final displayWidth = frameWidth * scale;
                final displayHeight = frameHeight * scale;

                return Center(
                  child: SizedBox(
                    width: displayWidth,
                    height: displayHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            latestFrameUrl!,
                            fit: BoxFit.fill,
                            errorBuilder: (context, error, stackTrace) =>
                                const ColoredBox(color: Color(0xFF081C15), child: Center(child: Text('Failed to load frame'))),
                          ),
                        ),
                        ...latestResult!.detections.map(
                          (item) => _DetectionOverlay(
                            detection: item,
                            scale: scale,
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: latestResult!.detections
                                .map(
                                  (item) => Chip(
                                    label: Text('${item.label} ${(item.confidence * 100).round()}%'),
                                    backgroundColor: _colorFor(item.label).withValues(alpha: 0.14),
                                    side: BorderSide(color: _colorFor(item.label)),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  static Color _colorFor(String label) {
    final colors = [
      const Color(0xFF1E6F5C),
      const Color(0xFFB2452F),
      const Color(0xFF3267A8),
      const Color(0xFF6A4C93),
    ];
    return colors[label.hashCode.abs() % colors.length];
  }
}

class _DetectionOverlay extends StatelessWidget {
  const _DetectionOverlay({
    required this.detection,
    required this.scale,
  });

  final DetectionItem detection;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (detection.box.length != 4) {
      return const SizedBox.shrink();
    }
    final left = detection.box[0] * scale;
    final top = detection.box[1] * scale;
    final width = (detection.box[2] - detection.box[0]) * scale;
    final height = (detection.box[3] - detection.box[1]) * scale;
    final color = LiveFeedPanel._colorFor(detection.label);

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Align(
            alignment: Alignment.topLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Text(
                '${detection.label} ${(detection.confidence * 100).round()}%',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
