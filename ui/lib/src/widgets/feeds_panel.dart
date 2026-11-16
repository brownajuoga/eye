import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class FeedsPanel extends StatefulWidget {
  const FeedsPanel({
    super.key,
    required this.feeds,
    required this.nodemcuConfig,
    required this.sourcesStatus,
    required this.onSaveNodeMcu,
    required this.onSendNodeMcuCommand,
    required this.onToggleHostScan,
  });

  final List<FeedSnapshot> feeds;
  final NodeMcuConfig nodemcuConfig;
  final WifiSourcesStatus sourcesStatus;
  final Future<void> Function(Map<String, dynamic> patch) onSaveNodeMcu;
  final Future<void> Function(String cmd) onSendNodeMcuCommand;
  final Future<void> Function(bool start) onToggleHostScan;

  @override
  State<FeedsPanel> createState() => _FeedsPanelState();
}

class _FeedsPanelState extends State<FeedsPanel> {
  late NodeMcuConfig _cfg;
  late TextEditingController _ssidController;
  late TextEditingController _passController;
  late TextEditingController _urlController;
  late TextEditingController _canaryController;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _cfg = widget.nodemcuConfig;
    _ssidController = TextEditingController(text: _cfg.wifiSsid);
    _passController = TextEditingController();
    _urlController = TextEditingController(text: _cfg.serverUrl);
    _canaryController = TextEditingController(text: _cfg.canarySsid);
  }

  @override
  void didUpdateWidget(covariant FeedsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty) {
      _cfg = widget.nodemcuConfig;
      _ssidController.text = _cfg.wifiSsid;
      _urlController.text = _cfg.serverUrl;
      _canaryController.text = _cfg.canarySsid;
    }
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    _urlController.dispose();
    _canaryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'Sensors & NodeMCU',
      subtitle: 'Configure plugged/unplugged ESP8266 NodeMCU & inspect live RF sources',
      trailing: FilledButton.icon(
        onPressed: () => widget.onToggleHostScan(!widget.sourcesStatus.hostScanRunning),
        icon: Icon(widget.sourcesStatus.hostScanRunning ? Icons.stop : Icons.wifi),
        label: Text(
          widget.sourcesStatus.hostScanRunning
              ? 'Stop ${widget.sourcesStatus.hostInterface}'
              : 'Start ${widget.sourcesStatus.hostInterface}',
        ),
      ),
      child: ListView(
        children: [
          // NodeMCU Configuration Card
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE1E8E3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ESP8266 NodeMCU Hardware Sensor (Plugged & Unplugged)', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                    'Plugged USB runs continuous promiscuous mode via `scout`. Unplugged connects over Wi-Fi using Link Tripwire or Hybrid Sniff-and-Upload to `/wifi/ingest`.',
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: const {'promisc', 'link', 'hybrid', 'canary'}.contains(_cfg.mode) ? _cfg.mode : 'promisc',
                    decoration: const InputDecoration(labelText: 'NodeMCU Operating Mode'),
                    items: const [
                      DropdownMenuItem(value: 'promisc', child: Text('Plugged USB: Continuous Promiscuous Sniffer')),
                      DropdownMenuItem(value: 'link', child: Text('Unplugged: Continuous AP Link RSSI Tripwire')),
                      DropdownMenuItem(value: 'hybrid', child: Text('Unplugged: Hybrid WIDS Sniff + Wi-Fi Upload')),
                      DropdownMenuItem(value: 'canary', child: Text('Canary Decoy AP + Uplink')),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setState(() {
                        _dirty = true;
                        _cfg = _cfg.copyWith(mode: val);
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _cfg.channelHop,
                          title: const Text('2.4 GHz Channel Hop (1–13)'),
                          onChanged: (val) => setState(() {
                            _dirty = true;
                            _cfg = _cfg.copyWith(channelHop: val);
                          }),
                        ),
                      ),
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _cfg.privacyMode,
                          title: const Text('On-Device MAC Privacy Hash'),
                          onChanged: (val) => setState(() {
                            _dirty = true;
                            _cfg = _cfg.copyWith(privacyMode: val);
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (!_cfg.channelHop) ...[
                    Text('Locked Channel: ${_cfg.lockedChannel}'),
                    Slider(
                      value: _cfg.lockedChannel.toDouble(),
                      min: 1,
                      max: 13,
                      divisions: 12,
                      label: 'Ch ${_cfg.lockedChannel}',
                      onChanged: (val) => setState(() {
                        _dirty = true;
                        _cfg = _cfg.copyWith(lockedChannel: val.round());
                      }),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ssidController,
                          decoration: const InputDecoration(labelText: 'Unplugged Wi-Fi SSID (for standalone mode)'),
                          onChanged: (_) => _dirty = true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _passController,
                          obscureText: true,
                          decoration: const InputDecoration(labelText: 'Unplugged Wi-Fi Password'),
                          onChanged: (_) => _dirty = true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: const InputDecoration(labelText: 'Ingest Server URL (from NodeMCU)'),
                          onChanged: (_) => _dirty = true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _canaryController,
                          decoration: const InputDecoration(labelText: 'Canary Decoy SSID'),
                          onChanged: (_) => _dirty = true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: () async {
                          await widget.onSaveNodeMcu({
                            'mode': _cfg.mode,
                            'channel_hop': _cfg.channelHop,
                            'locked_channel': _cfg.lockedChannel,
                            'privacy_mode': _cfg.privacyMode,
                            'wifi_ssid': _ssidController.text.trim(),
                            if (_passController.text.isNotEmpty) 'wifi_pass': _passController.text,
                            'server_url': _urlController.text.trim(),
                            'canary_ssid': _canaryController.text.trim(),
                          });
                          setState(() => _dirty = false);
                        },
                        icon: const Icon(Icons.save),
                        label: const Text('Apply & Queue to NodeMCU'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => widget.onSendNodeMcuCommand('PORTAL'),
                        icon: const Icon(Icons.wifi_lock),
                        label: const Text('Start Unplugged Setup Portal'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => widget.onSendNodeMcuCommand('PING'),
                        icon: const Icon(Icons.sensors),
                        label: const Text('Ping NodeMCU'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text('Active Sensor Feeds', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (widget.feeds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text('No active RF feeds yet. Start Host Wi-Fi, Simulator, or NodeMCU scout.'),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 420,
                mainAxisExtent: 310,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: widget.feeds.length,
              itemBuilder: (context, index) {
                final feed = widget.feeds[index];
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
                              child: Text(
                                feed.name.isEmpty ? feed.id : feed.name,
                                style: Theme.of(context).textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Chip(label: Text(feed.live ? 'Live' : 'Replay')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: feed.frameUrl == null
                                ? const ColoredBox(
                                    color: Color(0xFF0A1D13),
                                    child: Center(child: Text('No frame yet', style: TextStyle(color: Colors.greenAccent))),
                                  )
                                : Image.network(
                                    feed.frameUrl!,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => const ColoredBox(
                                      color: Color(0xFF0A1D13),
                                      child: Center(child: Text('Render unavailable', style: TextStyle(color: Colors.greenAccent))),
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Signals: ${feed.detections.map((item) => item.label).take(4).join(', ').ifEmpty('nominal')}',
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rule: ${feed.expertReason.ifEmpty('Monitoring')}',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
