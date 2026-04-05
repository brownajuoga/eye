import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class RulesPanel extends StatefulWidget {
  const RulesPanel({
    super.key,
    required this.rules,
    required this.onRulesChanged,
  });

  final List<RuleItem> rules;
  final Future<void> Function(List<RuleItem> next) onRulesChanged;

  @override
  State<RulesPanel> createState() => _RulesPanelState();
}

class _RulesPanelState extends State<RulesPanel> {
  late List<RuleItem> rules;

  @override
  void initState() {
    super.initState();
    rules = List<RuleItem>.from(widget.rules);
  }

  @override
  void didUpdateWidget(covariant RulesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    rules = List<RuleItem>.from(widget.rules);
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Automation Rules',
      subtitle: 'Scene-aware behavior and adaptive model switching',
      trailing: FilledButton(
        onPressed: _addRule,
        child: const Text('New Rule'),
      ),
      child: ListView.separated(
        itemCount: rules.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final rule = rules[index];
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE1E8E3)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: rule.name,
                    decoration: const InputDecoration(labelText: 'Rule Name'),
                    onChanged: (value) => rules[index] = rule.copyWith(name: value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: rule.condition,
                    decoration: const InputDecoration(labelText: 'Condition'),
                    maxLines: 2,
                    onChanged: (value) => rules[index] = rules[index].copyWith(condition: value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: rule.action,
                    decoration: const InputDecoration(labelText: 'Action'),
                    maxLines: 2,
                    onChanged: (value) => rules[index] = rules[index].copyWith(action: value),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: rules[index].enabled,
                        title: const Text('Enabled'),
                        onChanged: (value) {
                          setState(() => rules[index] = rules[index].copyWith(enabled: value));
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final nextRules = [...rules]..removeAt(index);
                        setState(() => rules = nextRules);
                        await widget.onRulesChanged(nextRules);
                      },
                      child: const Text('Delete'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () async {
                        final nextRules = List<RuleItem>.from(rules);
                        await widget.onRulesChanged(nextRules);
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _addRule() async {
    final next = [
      ...rules,
      const RuleItem(
        name: 'New Rule',
        condition: 'IF object detected',
        action: 'Log the event for review',
        enabled: true,
      ),
    ];
    setState(() => rules = next);
    await widget.onRulesChanged(next);
  }
}
