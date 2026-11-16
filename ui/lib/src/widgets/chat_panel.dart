import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.messages,
    required this.feeds,
    required this.defaultFeedId,
    required this.onSend,
  });

  final List<ChatMessage> messages;
  final List<FeedSnapshot> feeds;
  final String defaultFeedId;
  final Future<void> Function(String message, {String? feedId}) onSend;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  late final TextEditingController messageController;
  String selectedFeedId = '';

  @override
  void initState() {
    super.initState();
    messageController = TextEditingController();
    selectedFeedId = widget.defaultFeedId;
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (selectedFeedId.isEmpty && widget.defaultFeedId.isNotEmpty) {
      selectedFeedId = widget.defaultFeedId;
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  Future<void> _submit([String? overrideText]) async {
    final text = (overrideText ?? messageController.text).trim();
    if (text.isEmpty) return;
    if (overrideText == null) {
      messageController.clear();
    }
    await widget.onSend(text, feedId: selectedFeedId.isEmpty ? null : selectedFeedId);
  }

  @override
  Widget build(BuildContext context) {
    final validFeedIds = {'', ...widget.feeds.map((f) => f.id)};
    final effectiveFeed = validFeedIds.contains(selectedFeedId) ? selectedFeedId : '';

    return PanelShell(
      title: 'Expert RF Chat',
      subtitle: 'Query WIDS intrusions, channel congestion, room occupancy & NodeMCU feeds',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: effectiveFeed,
            decoration: const InputDecoration(labelText: 'Focus RF Sensor Feed'),
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('All RF sensors')),
              ...widget.feeds.map(
                (feed) => DropdownMenuItem<String>(
                  value: feed.id,
                  child: Text(feed.name.isEmpty ? feed.id : feed.name),
                ),
              ),
            ],
            onChanged: (value) => setState(() => selectedFeedId = value ?? ''),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('Any deauth or evil twin attacks?'),
                  onPressed: () => _submit('Are there any deauth attacks or evil twin alerts right now?'),
                ),
                ActionChip(
                  label: const Text('Cleanest Wi-Fi channel?'),
                  onPressed: () => _submit('Which 2.4 GHz channel has the lowest congestion and interference?'),
                ),
                ActionChip(
                  label: const Text('Room occupancy & motion?'),
                  onPressed: () => _submit('Is anyone detected in the room or crossing the RSSI tripwire?'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.messages.isEmpty
                ? const Center(child: Text('Ask about your 2.4 GHz spectrum, NodeMCU telemetry, or recent alerts.'))
                : ListView.separated(
                    itemCount: widget.messages.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final message = widget.messages[index];
                      final assistant = message.role == 'assistant';
                      return Align(
                        alignment: assistant ? Alignment.centerLeft : Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 560),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: assistant ? Colors.white : const Color(0xFFEAF4EE),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE1E8E3)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(assistant ? 'RF Expert' : 'Operator', style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: 6),
                                  Text(message.content),
                                  if (message.taskSummary.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(message.taskSummary, style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                  if (assistant && message.evidence.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _ListBlock(label: 'Evidence', items: message.evidence),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  maxLines: 3,
                  minLines: 1,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: 'Message the RF Expert',
                    hintText: 'Example: Which channel has the least congestion or were deauths detected?',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _submit(),
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ListBlock extends StatelessWidget {
  const _ListBlock({
    required this.label,
    required this.items,
  });

  final String label;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        ...items.take(4).map(
              (item) => Text(
                item.entries.map((entry) => '${entry.key}: ${entry.value}').join(', '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
      ],
    );
  }
}
