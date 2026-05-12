import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class VideoAnalysisPanel extends StatefulWidget {
  const VideoAnalysisPanel({
    super.key,
    required this.history,
    required this.onAnalyzeVideo,
  });

  final List<VideoAnalysisResult> history;
  final Future<void> Function() onAnalyzeVideo;

  @override
  State<VideoAnalysisPanel> createState() => _VideoAnalysisPanelState();
}

class _VideoAnalysisPanelState extends State<VideoAnalysisPanel> {
  String sourceKind = 'camera';
  String sourceValue = 'auto';
  bool headless = true;
  bool jsonOutput = false;
  double triggerSeconds = 1.0;
  late final TextEditingController sourceController;
  late final TextEditingController commandController;

  @override
  void initState() {
    super.initState();
    sourceController = TextEditingController(text: sourceValue);
    commandController = TextEditingController(text: _buildScoutCommand());
  }

  @override
  void dispose() {
    sourceController.dispose();
    commandController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scoutCommand = _buildScoutCommand();
    if (commandController.text != scoutCommand) {
      commandController.text = scoutCommand;
    }
    return PanelShell(
      title: 'Video Analysis',
      subtitle: 'Upload recordings or prepare Scout source commands',
      trailing: FilledButton.icon(
        onPressed: () => widget.onAnalyzeVideo(),
        icon: const Icon(Icons.video_file),
        label: const Text('Analyze Video'),
      ),
      child: ListView(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Camera'),
                selected: sourceKind == 'camera',
                onSelected: (_) => setState(() {
                  sourceKind = 'camera';
                  sourceValue = 'auto';
                  sourceController.text = sourceValue;
                }),
              ),
              ChoiceChip(
                label: const Text('Video File'),
                selected: sourceKind == 'video',
                onSelected: (_) => setState(() {
                  sourceKind = 'video';
                  sourceValue = '/path/to/video.mp4';
                  sourceController.text = sourceValue;
                }),
              ),
              ChoiceChip(
                label: const Text('Folder'),
                selected: sourceKind == 'folder',
                onSelected: (_) => setState(() {
                  sourceKind = 'folder';
                  sourceValue = '/path/to/media-folder';
                  sourceController.text = sourceValue;
                }),
              ),
              ChoiceChip(
                label: const Text('RTSP'),
                selected: sourceKind == 'rtsp',
                onSelected: (_) => setState(() {
                  sourceKind = 'rtsp';
                  sourceValue = 'rtsp://camera/stream';
                  sourceController.text = sourceValue;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(labelText: 'Scout Source'),
            onChanged: (value) => setState(() => sourceValue = value.trim()),
            controller: sourceController,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: headless,
                  title: const Text('Headless'),
                  onChanged: (value) => setState(() => headless = value),
                ),
              ),
              Expanded(
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: jsonOutput,
                  title: const Text('JSON Logs'),
                  onChanged: (value) => setState(() => jsonOutput = value),
                ),
              ),
            ],
          ),
          Text('Trigger interval: ${triggerSeconds.toStringAsFixed(1)}s'),
          Slider(
            value: triggerSeconds,
            min: 0.2,
            max: 10,
            divisions: 49,
            onChanged: (value) => setState(() => triggerSeconds = value),
          ),
          const SizedBox(height: 8),
          TextField(
            readOnly: true,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Scout Command',
              suffixIcon: IconButton(
                tooltip: 'Copy command',
                icon: const Icon(Icons.copy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: scoutCommand));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scout command copied')));
                  }
                },
              ),
            ),
            controller: commandController,
          ),
          const SizedBox(height: 20),
          Text('Uploaded Analyses', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (widget.history.isEmpty)
            const SizedBox(height: 160, child: Center(child: Text('No uploaded video analyses yet')))
          else
            ...widget.history.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE1E8E3)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    title: Text(item.filename),
                    subtitle: Text(
                      '${item.createdAt}\nFrames: ${item.framesProcessed} | Action: ${item.dominantAction}\nLabels: ${item.aggregatedLabels.join(', ')}',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _buildScoutCommand() {
    final source = sourceValue.trim().isEmpty ? 'auto' : sourceValue.trim();
    final flags = [
      'go run .',
      'detect',
      '-source "$source"',
      '-api-url http://127.0.0.1:8080',
      '-trigger-interval ${triggerSeconds.toStringAsFixed(1)}s',
      if (headless) '-headless',
      if (jsonOutput) '-json',
    ];
    return 'cd scout && ${flags.join(' ')}';
  }
}
