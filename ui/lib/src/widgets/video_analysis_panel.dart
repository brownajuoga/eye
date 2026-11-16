import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class VideoAnalysisPanel extends StatefulWidget {
  const VideoAnalysisPanel({
    super.key,
    required this.history,
    required this.onAnalyzeVideo,
    required this.onReplayCapture,
  });

  final List<VideoAnalysisResult> history;
  final Future<void> Function() onAnalyzeVideo;
  final Future<void> Function(String action, String captureId, int frameIndex) onReplayCapture;

  @override
  State<VideoAnalysisPanel> createState() => _VideoAnalysisPanelState();
}

class _VideoAnalysisPanelState extends State<VideoAnalysisPanel> {
  String sourceKind = 'nodemcu_usb';
  String sourceValue = 'auto';
  bool jsonOutput = false;
  double intervalSeconds = 0.8;
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
      title: 'RF Captures & Replay',
      subtitle: 'Upload .pcap/.pcapng/.csv/.jsonl Wi-Fi captures or launch NodeMCU & Host Scout collectors',
      trailing: FilledButton.icon(
        onPressed: () => widget.onAnalyzeVideo(),
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload Capture'),
      ),
      child: ListView(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('NodeMCU USB Serial'),
                selected: sourceKind == 'nodemcu_usb',
                onSelected: (_) => setState(() {
                  sourceKind = 'nodemcu_usb';
                  sourceValue = 'nodemcu';
                  sourceController.text = sourceValue;
                }),
              ),
              ChoiceChip(
                label: const Text('Unplugged Bridge'),
                selected: sourceKind == 'bridge',
                onSelected: (_) => setState(() {
                  sourceKind = 'bridge';
                  sourceValue = 'bridge';
                  sourceController.text = sourceValue;
                }),
              ),
              ChoiceChip(
                label: const Text('Host Linux Wi-Fi'),
                selected: sourceKind == 'host_wifi',
                onSelected: (_) => setState(() {
                  sourceKind = 'host_wifi';
                  sourceValue = 'host-wifi';
                  sourceController.text = sourceValue;
                }),
              ),
              ChoiceChip(
                label: const Text('RF Simulator'),
                selected: sourceKind == 'sim',
                onSelected: (_) => setState(() {
                  sourceKind = 'sim';
                  sourceValue = 'sim';
                  sourceController.text = sourceValue;
                }),
              ),
              ChoiceChip(
                label: const Text('PCAP / JSONL File'),
                selected: sourceKind == 'file',
                onSelected: (_) => setState(() {
                  sourceKind = 'file';
                  sourceValue = '/path/to/capture.pcap';
                  sourceController.text = sourceValue;
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(labelText: 'Scout Source / File Path'),
            onChanged: (value) => setState(() => sourceValue = value.trim()),
            controller: sourceController,
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: jsonOutput,
            title: const Text('JSON Console Logs'),
            onChanged: (value) => setState(() => jsonOutput = value),
          ),
          Text('Batch Interval: ${intervalSeconds.toStringAsFixed(1)}s'),
          Slider(
            value: intervalSeconds,
            min: 0.2,
            max: 5.0,
            divisions: 24,
            onChanged: (value) => setState(() => intervalSeconds = value),
          ),
          const SizedBox(height: 8),
          TextField(
            readOnly: true,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Scout Collector Command',
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
          Text('Analyzed RF Captures & Timelines', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (widget.history.isEmpty)
            const SizedBox(
              height: 150,
              child: Center(
                child: Text('No uploaded .pcap / .csv / .jsonl RF captures yet. Click "Upload Capture" above.'),
              ),
            )
          else
            ...widget.history.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE1E8E3)),
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    title: Text(item.filename),
                    subtitle: Text(
                      '${item.createdAt}\nSlices: ${item.framesProcessed} | Packets: ${item.totalPackets} | Dominant: ${item.dominantAction}\nSignals: ${item.aggregatedLabels.join(', ')}',
                    ),
                    trailing: item.captureId.isEmpty
                        ? null
                        : FilledButton.tonalIcon(
                            onPressed: () => widget.onReplayCapture('play', item.captureId, 0),
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Play in Cam'),
                          ),
                    children: [
                      if (item.timeline.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No timeline slices available.'),
                        )
                      else
                        SizedBox(
                          height: 195,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: item.timeline.length,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemBuilder: (context, index) {
                              final event = item.timeline[index];
                              final isAlert = event['expert']?['action'] == 'alert';
                              return InkWell(
                                onTap: item.captureId.isEmpty
                                    ? null
                                    : () => widget.onReplayCapture('load_frame', item.captureId, index),
                                child: Container(
                                  width: 245,
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isAlert ? const Color(0xFFFDECEA) : const Color(0xFFF5F8F6),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isAlert ? Colors.red.shade200 : const Color(0xFFD9E0DB)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Slice ${event['frame_index']} • ${event['packet_count'] ?? 0} pkts',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Occ: ${event['occupancy'] ?? 0} | Dist: ${event['disturbance'] ?? 0}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: SingleChildScrollView(
                                          child: Text(
                                            event['expert']?['reason'] ?? event['event']?['reason'] ?? 'Nominal',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
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
    if (sourceKind == 'bridge') {
      return 'cd scout && go run . bridge -listen :8090 -api-url http://127.0.0.1:8080${jsonOutput ? " -json" : ""}';
    }
    final flags = [
      'go run .',
      'detect',
      '-source "$source"',
      '-api-url http://127.0.0.1:8080',
      '-interval ${intervalSeconds.toStringAsFixed(1)}s',
      if (jsonOutput) '-json',
    ];
    return 'cd scout && ${flags.join(' ')}';
  }
}
