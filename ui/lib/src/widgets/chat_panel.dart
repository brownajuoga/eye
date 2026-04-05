import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.messages,
    required this.feeds,
    required this.onSend,
  });

  final List<ChatMessage> messages;
  final List<FeedSnapshot> feeds;
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
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Expert Chat',
      subtitle: 'Talk to the expert, assign tasks, and query a specific feed',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedFeedId,
                  decoration: const InputDecoration(labelText: 'Focus Feed'),
                  items: [
                    const DropdownMenuItem<String>(value: '', child: Text('All feeds')),
                    ...widget.feeds.map(
                      (feed) => DropdownMenuItem<String>(
                        value: feed.id,
                        child: Text(feed.name.isEmpty ? feed.id : feed.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => selectedFeedId = value ?? ''),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: widget.messages.isEmpty
                ? const Center(child: Text('No chat messages yet'))
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
                                  Text(assistant ? 'Expert' : 'Operator', style: Theme.of(context).textTheme.titleSmall),
                                  const SizedBox(height: 6),
                                  Text(message.content),
                                  if (message.taskSummary.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(message.taskSummary, style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                  if (assistant && message.plan.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    _LabeledBlock(label: 'Intent', value: '${message.plan['intent'] ?? 'unknown'}'),
                                    if ((message.plan['resources'] as Map?)?.isNotEmpty ?? false)
                                      _LabeledBlock(
                                        label: 'Resources',
                                        value: (message.plan['resources'] as Map).entries
                                            .map((entry) => '${entry.key}: ${entry.value}')
                                            .join(', '),
                                      ),
                                  ],
                                  if (assistant && message.actions.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _ListBlock(label: 'Actions', items: message.actions),
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
                  decoration: const InputDecoration(
                    labelText: 'Message the expert',
                    hintText: 'Example: Focus on feed 0 and explain whether the bag interaction is suspicious.',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () async {
                  final message = messageController.text.trim();
                  if (message.isEmpty) return;
                  await widget.onSend(message, feedId: selectedFeedId.isEmpty ? null : selectedFeedId);
                  messageController.clear();
                },
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabeledBlock extends StatelessWidget {
  const _LabeledBlock({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text('$label: $value', style: Theme.of(context).textTheme.bodySmall);
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
        ...items.take(4).map((item) => Text(item.entries.map((entry) => '${entry.key}: ${entry.value}').join(', '), style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}
