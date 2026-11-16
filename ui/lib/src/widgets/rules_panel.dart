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
  bool _dirty = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    rules = List<RuleItem>.from(widget.rules);
  }

  @override
  void didUpdateWidget(covariant RulesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty) {
      rules = List<RuleItem>.from(widget.rules);
      _revision++;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Automation Rules',
      subtitle: 'Wi-Fi WIDS alerts, doorway tripwires, congestion triggers & idle rules',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _addPresetRule,
            icon: const Icon(Icons.bolt),
            label: const Text('Add Tripwire Preset'),
          ),
          FilledButton(
            onPressed: _addRule,
            child: const Text('New Rule'),
          ),
        ],
      ),
      child: ListView.separated(
        itemCount: rules.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final rule = rules[index];
          return DecoratedBox(
            key: ValueKey('rule_${_revision}_$index'),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE1E8E3)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    initialValue: rule.name,
                    decoration: const InputDecoration(labelText: 'Rule Name'),
                    onChanged: (value) {
                      _dirty = true;
                      rules[index] = rules[index].copyWith(name: value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: rule.condition,
                    decoration: const InputDecoration(
                      labelText: 'Condition (e.g. IF deauth_flood detected, IF disturbance > 0.65, IF occupancy >= 3)',
                    ),
                    maxLines: 2,
                    onChanged: (value) {
                      _dirty = true;
                      rules[index] = rules[index].copyWith(condition: value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: rule.action,
                    decoration: const InputDecoration(labelText: 'Action'),
                    maxLines: 2,
                    onChanged: (value) {
                      _dirty = true;
                      rules[index] = rules[index].copyWith(action: value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: rules[index].enabled,
                          title: const Text('Enabled'),
                          onChanged: (value) {
                            setState(() {
                              _dirty = true;
                              rules[index] = rules[index].copyWith(enabled: value);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final nextRules = [...rules]..removeAt(index);
                          setState(() {
                            rules = nextRules;
                            _revision++;
                            _dirty = false;
                          });
                          await widget.onRulesChanged(nextRules);
                        },
                        child: const Text('Delete'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () async {
                          final nextRules = List<RuleItem>.from(rules);
                          setState(() => _dirty = false);
                          await widget.onRulesChanged(nextRules);
                        },
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
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
        name: 'New RF Rule',
        condition: 'IF rssi_tripwire_motion detected with confidence > 0.55',
        action: 'Create alert for RF link disturbance',
        enabled: true,
      ),
    ];
    setState(() {
      rules = next;
      _revision++;
      _dirty = false;
    });
    await widget.onRulesChanged(next);
  }

  Future<void> _addPresetRule() async {
    final next = [
      ...rules,
      const RuleItem(
        name: 'High Occupancy Room Trigger',
        condition: 'IF occupancy >= 3',
        action: 'Alert and notify automation webhook',
        enabled: true,
      ),
    ];
    setState(() {
      rules = next;
      _revision++;
      _dirty = false;
    });
    await widget.onRulesChanged(next);
  }
}
