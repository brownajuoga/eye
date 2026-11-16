import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class NightVisionCamPanel extends StatefulWidget {
  const NightVisionCamPanel({
    super.key,
    required this.vision,
    required this.sourcesStatus,
    required this.palette,
    required this.privacyMode,
    required this.onToggleHostScan,
    required this.onControlSimulator,
    required this.onChangePalette,
    required this.onTogglePrivacy,
    required this.onUpdateAnchors,
    required this.onReplayAction,
    required this.onRefresh,
  });

  final WifiVisionState vision;
  final WifiSourcesStatus sourcesStatus;
  final String palette;
  final bool privacyMode;
  final Future<void> Function(bool start) onToggleHostScan;
  final Future<void> Function(String action, String scenario) onControlSimulator;
  final Future<void> Function(String palette) onChangePalette;
  final Future<void> Function(bool enabled) onTogglePrivacy;
  final Future<void> Function(Map<String, Map<String, double>> anchors) onUpdateAnchors;
  final Future<void> Function(String action, String captureId, int frameIndex) onReplayAction;
  final Future<void> Function() onRefresh;

  @override
  State<NightVisionCamPanel> createState() => _NightVisionCamPanelState();
}

class _NightVisionCamPanelState extends State<NightVisionCamPanel> with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  String? _selectedEntityKey;
  String? _draggingKey;
  Offset? _draggingNormPos;
  String _selectedScenario = 'mixed';

  @override
  void initState() {
    super.initState();
    _selectedScenario = widget.sourcesStatus.simulatorScenario;
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant NightVisionCamPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sourcesStatus.simulatorRunning && widget.sourcesStatus.simulatorScenario.isNotEmpty) {
      _selectedScenario = widget.sourcesStatus.simulatorScenario;
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  WifiEntity? get _selectedEntity {
    if (_selectedEntityKey == null) return null;
    for (final e in widget.vision.entities) {
      if (e.rawKey == _selectedEntityKey || e.id == _selectedEntityKey) {
        return e;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final vision = widget.vision;
    final status = widget.sourcesStatus;
    final selected = _selectedEntity;
    final replay = vision.replay;

    return PanelShell(
      title: 'Wi-Fi Night-Vision Cam',
      subtitle: 'Live spatial RF field, Fresnel motion waves, WIDS alerts & 2.4 GHz spectrum',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: Text(widget.privacyMode ? 'ANON ON' : 'ANON OFF'),
            selected: widget.privacyMode,
            avatar: Icon(widget.privacyMode ? Icons.visibility_off : Icons.visibility, size: 16),
            onSelected: (val) => widget.onTogglePrivacy(val),
          ),
          IconButton(
            tooltip: 'Refresh Telemetry',
            onPressed: () => widget.onRefresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Palette & live source quick-action strip
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _paletteChip('night_vision', 'Night Vision', Icons.nightlight_round),
              _paletteChip('thermal', 'Thermal RF', Icons.thermostat),
              _paletteChip('radar', 'Radar', Icons.radar),
              _paletteChip('spectrum', '2.4GHz Spectrum', Icons.equalizer),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: status.hostScanRunning ? const Color(0xFFB2452F) : const Color(0xFF1E6F5C),
                ),
                onPressed: () => widget.onToggleHostScan(!status.hostScanRunning),
                icon: Icon(status.hostScanRunning ? Icons.stop : Icons.wifi_tethering, size: 18),
                label: Text(
                  status.hostScanRunning ? 'Stop ${status.hostInterface}' : 'Scan ${status.hostInterface}',
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: () => widget.onControlSimulator(
                  status.simulatorRunning ? 'stop' : 'start',
                  _selectedScenario,
                ),
                icon: Icon(status.simulatorRunning ? Icons.stop_circle : Icons.play_circle, size: 18),
                label: Text(status.simulatorRunning ? 'Stop Sim' : 'Simulate RF'),
              ),
              DropdownButton<String>(
                value: _scenarios.contains(_selectedScenario) ? _selectedScenario : 'mixed',
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 'mixed', child: Text('Scenario: Mixed')),
                  DropdownMenuItem(value: 'motion', child: Text('Scenario: Motion Tripwire')),
                  DropdownMenuItem(value: 'deauth', child: Text('Scenario: Deauth Attack')),
                  DropdownMenuItem(value: 'evil_twin', child: Text('Scenario: Evil Twin AP')),
                  DropdownMenuItem(value: 'crowd', child: Text('Scenario: Busy Crowd')),
                  DropdownMenuItem(value: 'congestion', child: Text('Scenario: Ch Congestion')),
                  DropdownMenuItem(value: 'quiet', child: Text('Scenario: Quiet Room')),
                ],
                onChanged: (val) {
                  if (val == null) return;
                  setState(() => _selectedScenario = val);
                  if (status.simulatorRunning) {
                    widget.onControlSimulator('start', val);
                  } else {
                    widget.onControlSimulator('step', val);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Main Night-Vision CCAM Video Canvas
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        onTapDown: (details) => _handleTap(details.localPosition, size),
                        onPanStart: (details) => _handlePanStart(details.localPosition, size),
                        onPanUpdate: (details) => _handlePanUpdate(details.localPosition, size),
                        onPanEnd: (_) => _handlePanEnd(),
                        child: AnimatedBuilder(
                          animation: _animController,
                          builder: (context, _) {
                            return CustomPaint(
                              painter: _NightVisionPainter(
                                vision: vision,
                                palette: widget.palette,
                                phase: _animController.value,
                                selectedKey: _selectedEntityKey,
                                draggingKey: _draggingKey,
                                draggingPos: _draggingNormPos,
                              ),
                              size: size,
                            );
                          },
                        ),
                      ),

                      // Top HUD Status Overlay
                      Positioned(
                        top: 10,
                        left: 12,
                        right: 12,
                        child: IgnorePointer(
                          child: Row(
                            children: [
                              _hudBadge(
                                icon: Icons.fiber_manual_record,
                                iconColor: status.hostScanRunning || status.simulatorRunning || vision.sourceKind == 'nodemcu_serial'
                                    ? const Color(0xFFFF4D4D)
                                    : const Color(0xFF8FB8A0),
                                text:
                                    '${vision.sourceName.toUpperCase()}  •  ${vision.mode.toUpperCase()}${vision.privacyMode ? "  •  ANON" : ""}',
                              ),
                              const Spacer(),
                              _hudBadge(
                                text:
                                    'OCC:${vision.occupancyEstimate} (${vision.occupancyDensity.toUpperCase()})  •  DIST:${vision.disturbance.toStringAsFixed(2)}  •  PKTS:${vision.totalPackets}',
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Active Threat / Motion Alert Banner inside Cam HUD
                      if (vision.alertBanner.isNotEmpty)
                        Positioned(
                          top: 44,
                          left: 12,
                          right: 12,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xCC9E1C1C),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFF6B6B)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      vision.alertBanner,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Selected Target Floating HUD Card
                      if (selected != null)
                        Positioned(
                          right: 12,
                          bottom: 72,
                          child: Container(
                            width: 240,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xDD081810),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF2CE680)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        selected.label,
                                        style: const TextStyle(color: Color(0xFF7BFFB2), fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: () => setState(() => _selectedEntityKey = null),
                                      child: const Icon(Icons.close, color: Color(0xFF7BFFB2), size: 16),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Type: ${selected.category.toUpperCase()}${selected.randomized ? " (Randomized MAC)" : ""}\n'
                                  'ID: ${selected.bssid}\n'
                                  'Channel: ${selected.channel}  |  RSSI: ${selected.rssi} dBm\n'
                                  'Baseline: ${selected.ewmaRssi} dBm  |  Z: ${selected.zScore.toStringAsFixed(2)}\n'
                                  'Disturbance: ${selected.disturbance.toStringAsFixed(2)}  |  Rate: ${selected.pps}/s'
                                  '${selected.security.isNotEmpty ? "\nSecurity: ${selected.security}" : ""}'
                                  '${selected.threat != null ? "\nTHREAT: ${selected.threat!.toUpperCase()}" : ""}',
                                  style: const TextStyle(color: Color(0xFFD6F7E2), fontSize: 11, height: 1.35),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Drag hint pill bottom-left above oscilloscope
                      Positioned(
                        left: 12,
                        bottom: 66,
                        child: IgnorePointer(
                          child: Text(
                            'Tip: Tap any signal blip to inspect • Drag sensor/AP nodes to match your room layout',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // Replay Bar if viewing a PCAP/CSV/JSONL capture
          if (replay != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10241B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF28694C)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.replay, color: Color(0xFF55F29E), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Replay: ${replay['filename']} (Frame ${((replay['frame_index'] as num?)?.toInt() ?? 0) + 1}/${replay['total_frames'] ?? 1})',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      status.replayRunning ? Icons.pause : Icons.play_arrow,
                      color: const Color(0xFF55F29E),
                    ),
                    onPressed: () {
                      final cid = replay['capture_id'] as String? ?? '';
                      final idx = (replay['frame_index'] as num?)?.toInt() ?? 0;
                      widget.onReplayAction(status.replayRunning ? 'stop' : 'play', cid, idx);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white70),
                    onPressed: () {
                      final cid = replay['capture_id'] as String? ?? '';
                      final idx = math.max(0, ((replay['frame_index'] as num?)?.toInt() ?? 0) - 1);
                      widget.onReplayAction('load_frame', cid, idx);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white70),
                    onPressed: () {
                      final cid = replay['capture_id'] as String? ?? '';
                      final total = (replay['total_frames'] as num?)?.toInt() ?? 1;
                      final idx = math.min(total - 1, ((replay['frame_index'] as num?)?.toInt() ?? 0) + 1);
                      widget.onReplayAction('load_frame', cid, idx);
                    },
                  ),
                  TextButton(
                    onPressed: () => widget.onReplayAction('stop', replay['capture_id'] as String? ?? '', 0),
                    child: const Text('Exit Replay', style: TextStyle(color: Color(0xFFFF8888))),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static const _scenarios = {
    'mixed',
    'motion',
    'deauth',
    'evil_twin',
    'crowd',
    'congestion',
    'quiet',
  };

  Widget _paletteChip(String key, String label, IconData icon) {
    final selected = widget.palette == key;
    return ChoiceChip(
      label: Text(label),
      avatar: Icon(icon, size: 15),
      selected: selected,
      onSelected: (_) => widget.onChangePalette(key),
    );
  }

  Widget _hudBadge({IconData? icon, Color? iconColor, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xAA040C08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x444AF28A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: iconColor ?? Colors.greenAccent),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF9CFFC3),
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  double _hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

  void _handleTap(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0 || widget.palette == 'spectrum') return;
    final nx = local.dx / size.width;
    final ny = local.dy / size.height;
    WifiEntity? closest;
    double bestDist = 0.06;
    for (final e in widget.vision.entities) {
      final d = _hypot(e.x - nx, e.y - ny);
      if (d < bestDist) {
        bestDist = d;
        closest = e;
      }
    }
    setState(() {
      _selectedEntityKey = closest?.rawKey.isNotEmpty == true ? closest!.rawKey : closest?.id;
    });
  }

  void _handlePanStart(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0 || widget.palette == 'spectrum') return;
    final nx = local.dx / size.width;
    final ny = local.dy / size.height;

    final sx = widget.vision.sensorX;
    final sy = widget.vision.sensorY;
    if (_hypot(sx - nx, sy - ny) < 0.06) {
      setState(() {
        _draggingKey = 'sensor';
        _draggingNormPos = Offset(nx, ny);
      });
      return;
    }

    for (final e in widget.vision.entities) {
      if (_hypot(e.x - nx, e.y - ny) < 0.055) {
        setState(() {
          _draggingKey = e.rawKey.isNotEmpty ? e.rawKey : e.id;
          _draggingNormPos = Offset(nx, ny);
        });
        return;
      }
    }
  }

  void _handlePanUpdate(Offset local, Size size) {
    if (_draggingKey == null || size.width <= 0 || size.height <= 0) return;
    final nx = (local.dx / size.width).clamp(0.05, 0.95);
    final ny = (local.dy / size.height).clamp(0.08, 0.84);
    setState(() {
      _draggingNormPos = Offset(nx, ny);
    });
  }

  void _handlePanEnd() {
    final key = _draggingKey;
    final pos = _draggingNormPos;
    setState(() {
      _draggingKey = null;
      _draggingNormPos = null;
    });
    if (key != null && pos != null) {
      widget.onUpdateAnchors({
        key: {'x': pos.dx, 'y': pos.dy},
      });
    }
  }
}

class _NightVisionPainter extends CustomPainter {
  const _NightVisionPainter({
    required this.vision,
    required this.palette,
    required this.phase,
    required this.selectedKey,
    required this.draggingKey,
    required this.draggingPos,
  });

  final WifiVisionState vision;
  final String palette;
  final double phase;
  final String? selectedKey;
  final String? draggingKey;
  final Offset? draggingPos;

  @override
  void paint(Canvas canvas, Size size) {
    if (palette == 'spectrum') {
      _paintSpectrum(canvas, size);
      return;
    }

    final colors = _PaletteColors.fromName(palette);

    // 1. Dark Phosphor / Thermal / Radar backdrop + radial vignette
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          colors: [colors.bgCenter, colors.bgEdge],
          radius: 0.95,
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // 2. Subtle tactical floorplan grid
    final gridPaint = Paint()
      ..color = colors.grid.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    const step = 42.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Center ESP8266 position (supports live drag preview)
    final sensorNorm = draggingKey == 'sensor' && draggingPos != null
        ? draggingPos!
        : Offset(vision.sensorX, vision.sensorY);
    final sensorPt = Offset(sensorNorm.dx * size.width, sensorNorm.dy * size.height);

    // 3. Concentric dBm distance rings
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = colors.primary.withValues(alpha: palette == 'radar' ? 0.35 : 0.18);
    final maxR = math.min(size.width, size.height) * 0.68;
    for (var i = 1; i <= 4; i++) {
      final r = maxR * (i / 4.0);
      canvas.drawCircle(sensorPt, r, ringPaint);
      _drawLabel(
        canvas,
        '-${25 + i * 16} dBm',
        Offset(sensorPt.dx + r * 0.72, sensorPt.dy - r * 0.68),
        colors.primary.withValues(alpha: 0.48),
        9,
      );
    }

    // Radar rotating beam wedge (subtle in Night Vision, vivid in Radar)
    final sweepAngle = phase * math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: sensorPt, radius: maxR),
      sweepAngle - 0.38,
      0.38,
      true,
      Paint()
        ..shader = SweepGradient(
          startAngle: sweepAngle - 0.38,
          endAngle: sweepAngle,
          colors: [Colors.transparent, colors.primary.withValues(alpha: palette == 'radar' ? 0.28 : 0.10)],
        ).createShader(Rect.fromCircle(center: sensorPt, radius: maxR)),
    );

    // 4. Fresnel Link Beams & Disturbance Motion Waves
    for (final link in vision.links) {
      Offset endPt = Offset(link.toX * size.width, link.toY * size.height);
      if (draggingKey != null && draggingPos != null && link.id.contains(draggingKey!)) {
        endPt = Offset(draggingPos!.dx * size.width, draggingPos!.dy * size.height);
      }
      final beamColor = link.crossing
          ? colors.alert
          : (link.disturbance > 0.35 ? colors.warn : colors.primary);
      final beamPaint = Paint()
        ..color = beamColor.withValues(alpha: link.crossing ? 0.85 : 0.42 + link.disturbance * 0.4)
        ..strokeWidth = link.crossing ? 3.0 : 1.6;
      canvas.drawLine(sensorPt, endPt, beamPaint);

      // Animated motion ripple along disturbed Fresnel corridor
      if (link.disturbance > 0.22 || link.crossing) {
        final mid = Offset((sensorPt.dx + endPt.dx) / 2, (sensorPt.dy + endPt.dy) / 2);
        for (var k = 0; k < 2; k++) {
          final rp = (phase + k * 0.5) % 1.0;
          final rippleR = 12.0 + rp * (54.0 + link.disturbance * 40.0);
          canvas.drawCircle(
            mid,
            rippleR,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..color = beamColor.withValues(alpha: (1.0 - rp) * 0.85),
          );
        }
        canvas.drawCircle(
          mid,
          26.0 + link.disturbance * 24.0,
          Paint()
            ..shader = RadialGradient(
              colors: [beamColor.withValues(alpha: 0.38), Colors.transparent],
            ).createShader(Rect.fromCircle(center: mid, radius: 50)),
        );
      }
    }

    // 5. Spatial Emitter Heat / Night-Vision Blobs & Target Boxes
    for (final ent in vision.entities) {
      final isDragged = draggingKey != null && (ent.rawKey == draggingKey || ent.id == draggingKey);
      final normPos = isDragged && draggingPos != null ? draggingPos! : Offset(ent.x, ent.y);
      final pt = Offset(normPos.dx * size.width, normPos.dy * size.height);
      final isSelected = selectedKey != null && (ent.rawKey == selectedKey || ent.id == selectedKey);

      final strength = ((100 + ent.rssi) / 65.0).clamp(0.2, 1.0);
      final blobRadius = 18.0 + strength * 30.0 + ent.disturbance * 24.0;
      final col = ent.threat != null
          ? colors.alert
          : (ent.disturbance > 0.45
              ? colors.warn
              : (ent.category == 'ap' ? colors.primary : colors.secondary));

      // Night-Vision / Thermal spatial cloud
      canvas.drawCircle(
        pt,
        blobRadius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              col.withValues(alpha: 0.42 * ent.fade),
              col.withValues(alpha: 0.14 * ent.fade),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: pt, radius: blobRadius)),
      );

      // Pulse ring for moving/bursting emitters
      if (ent.disturbance > 0.3 || ent.threat != null) {
        final pulse = (phase * 2.0) % 1.0;
        canvas.drawCircle(
          pt,
          8 + pulse * 24,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = col.withValues(alpha: (1.0 - pulse) * 0.85),
        );
      }

      // Target core & CCAM reticle brackets
      canvas.drawCircle(pt, ent.category == 'ap' ? 5.5 : 4.2, Paint()..color = col);
      if (isSelected || ent.threat != null || ent.category == 'ap') {
        _drawBrackets(
          canvas,
          Rect.fromCenter(center: pt, width: isSelected ? 34 : 26, height: isSelected ? 34 : 26),
          col.withValues(alpha: 0.9),
        );
      }

      _drawLabel(
        canvas,
        '${ent.label} (${ent.rssi}dBm)',
        Offset(pt.dx + 14, pt.dy - 8),
        col.withValues(alpha: 0.95),
        10.5,
      );
    }

    // 6. NodeMCU Sensor Anchor Icon
    canvas.drawRect(
      Rect.fromCenter(center: sensorPt, width: 16, height: 16),
      Paint()..color = colors.secondary,
    );
    _drawBrackets(
      canvas,
      Rect.fromCenter(center: sensorPt, width: 26, height: 26),
      colors.primary,
    );
    _drawLabel(
      canvas,
      'NODEMCU ESP8266',
      Offset(sensorPt.dx + 16, sensorPt.dy - 6),
      colors.secondary,
      11,
    );

    // 7. Live RSSI & Disturbance Oscilloscope at Bottom of Cam
    _paintWaveformStrip(canvas, size, colors);

    // 8. CRT Night-Vision Scanlines + Corner Surveillance Reticles
    final scanPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    for (double y = (phase * 6) % 4; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanPaint);
    }
    _drawCorners(canvas, size, colors.primary.withValues(alpha: 0.65));
  }

  void _paintWaveformStrip(Canvas canvas, Size size, _PaletteColors colors) {
    const stripHeight = 52.0;
    final top = size.height - stripHeight;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, stripHeight),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawLine(
      Offset(0, top),
      Offset(size.width, top),
      Paint()..color = colors.primary.withValues(alpha: 0.35),
    );

    final pts = vision.waveform;
    if (pts.length < 2) {
      _drawLabel(canvas, 'AWAITING RF WAVEFORM...', Offset(14, top + 18), colors.primary.withValues(alpha: 0.6), 11);
      return;
    }

    final rssiPath = Path();
    final basePath = Path();
    final usableW = size.width - 28;
    for (var i = 0; i < pts.length; i++) {
      final p = pts[i];
      final x = 14 + (i / (pts.length - 1)) * usableW;
      final normRssi = ((p.rssi + 95) / 65).clamp(0.0, 1.0);
      final normBase = ((p.baseline + 95) / 65).clamp(0.0, 1.0);
      final yRssi = size.height - 8 - normRssi * (stripHeight - 16);
      final yBase = size.height - 8 - normBase * (stripHeight - 16);
      if (i == 0) {
        rssiPath.moveTo(x, yRssi);
        basePath.moveTo(x, yBase);
      } else {
        rssiPath.lineTo(x, yRssi);
        basePath.lineTo(x, yBase);
      }

      if (p.disturbance > 0.3) {
        final barH = p.disturbance * (stripHeight - 10);
        canvas.drawLine(
          Offset(x, size.height - 4),
          Offset(x, size.height - 4 - barH),
          Paint()
            ..color = (p.disturbance > 0.6 ? colors.alert : colors.warn).withValues(alpha: 0.45)
            ..strokeWidth = 3,
        );
      }
    }

    canvas.drawPath(
      basePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = colors.secondary.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      rssiPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = colors.primary,
    );
    _drawLabel(
      canvas,
      'RSSI WAVEFORM (${pts.last.rssi.toStringAsFixed(0)} dBm)',
      Offset(12, top + 4),
      colors.secondary.withValues(alpha: 0.8),
      9.5,
    );
  }

  void _paintSpectrum(Canvas canvas, Size size) {
    final colors = _PaletteColors.fromName('night_vision');
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF05130C));

    final channels = vision.channels;
    const chartLeft = 40.0;
    final chartRight = size.width - 24.0;
    const chartTop = 58.0;
    final chartBottom = size.height - 76.0;
    final chartW = chartRight - chartLeft;
    final chartH = chartBottom - chartTop;

    // Gridlines
    for (var g = 0; g <= 4; g++) {
      final y = chartTop + chartH * (g / 4.0);
      canvas.drawLine(
        Offset(chartLeft, y),
        Offset(chartRight, y),
        Paint()..color = colors.grid.withValues(alpha: 0.4),
      );
    }

    if (channels.isEmpty) {
      _drawLabel(canvas, 'NO 2.4 GHZ SPECTRUM DATA YET', const Offset(chartLeft + 20, chartTop + 40), colors.primary, 13);
    } else {
      final barW = (chartW / 13.0) * 0.62;
      for (var i = 0; i < channels.length; i++) {
        final ch = channels[i];
        final cx = chartLeft + ((i + 0.5) / 13.0) * chartW;
        final h = ch.congestion.clamp(0.03, 1.0) * chartH;
        final isRec = ch.channel == vision.recommendedChannel;
        final col = ch.congestion > 0.72
            ? colors.alert
            : (ch.congestion > 0.45 ? colors.warn : (isRec ? const Color(0xFF56FFB0) : colors.primary));

        // Bell-curve 20MHz channel envelope behind bar
        final bell = Path()
          ..moveTo(cx - barW * 1.4, chartBottom)
          ..quadraticBezierTo(cx, chartBottom - h * 1.15, cx + barW * 1.4, chartBottom);
        canvas.drawPath(bell, Paint()..color = col.withValues(alpha: 0.14));

        final rect = Rect.fromLTWH(cx - barW / 2, chartBottom - h, barW, h);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(6), topRight: const Radius.circular(6)),
          Paint()..color = col.withValues(alpha: 0.72),
        );

        _drawLabel(canvas, 'Ch${ch.channel}', Offset(cx - 12, chartBottom + 8), colors.secondary, 10.5);
        if (ch.apCount > 0) {
          _drawLabel(canvas, '${ch.apCount}AP', Offset(cx - 11, chartBottom - h - 15), col, 9.5);
        }
      }
      _drawLabel(
        canvas,
        'CLEANEST NON-OVERLAPPING CHANNEL: CH ${vision.recommendedChannel} (1 / 6 / 11)',
        Offset(chartLeft, chartBottom + 28),
        const Color(0xFF69FFB4),
        11,
      );
    }
    _paintWaveformStrip(canvas, size, colors);
  }

  void _drawBrackets(Canvas canvas, Rect rect, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    const len = 6.0;
    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + len)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + len, rect.top),
      p,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + len),
      p,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - len)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + len, rect.bottom),
      p,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - len),
      p,
    );
  }

  void _drawCorners(Canvas canvas, Size size, Color color) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    const pad = 8.0;
    const arm = 18.0;
    canvas.drawPath(
      Path()
        ..moveTo(pad, pad + arm)
        ..lineTo(pad, pad)
        ..lineTo(pad + arm, pad)
        ..moveTo(size.width - pad - arm, pad)
        ..lineTo(size.width - pad, pad)
        ..lineTo(size.width - pad, pad + arm)
        ..moveTo(pad, size.height - pad - arm)
        ..lineTo(pad, size.height - pad)
        ..lineTo(pad + arm, size.height - pad)
        ..moveTo(size.width - pad - arm, size.height - pad)
        ..lineTo(size.width - pad, size.height - pad)
        ..lineTo(size.width - pad, size.height - pad - arm),
      p,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
          shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 220);
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(covariant _NightVisionPainter oldDelegate) => true;
}

class _PaletteColors {
  const _PaletteColors({
    required this.bgCenter,
    required this.bgEdge,
    required this.grid,
    required this.primary,
    required this.secondary,
    required this.warn,
    required this.alert,
  });

  final Color bgCenter;
  final Color bgEdge;
  final Color grid;
  final Color primary;
  final Color secondary;
  final Color warn;
  final Color alert;

  factory _PaletteColors.fromName(String name) {
    switch (name) {
      case 'thermal':
        return const _PaletteColors(
          bgCenter: Color(0xFF1A0F3B),
          bgEdge: Color(0xFF090617),
          grid: Color(0xFF3E2978),
          primary: Color(0xFFFF8826),
          secondary: Color(0xFFFFE169),
          warn: Color(0xFFFF4D88),
          alert: Color(0xFFFFFFFF),
        );
      case 'radar':
        return const _PaletteColors(
          bgCenter: Color(0xFF06202B),
          bgEdge: Color(0xFF020C12),
          grid: Color(0xFF145970),
          primary: Color(0xFF2AE4F5),
          secondary: Color(0xFF99FFE8),
          warn: Color(0xFFFFC947),
          alert: Color(0xFFFF5252),
        );
      default:
        return const _PaletteColors(
          bgCenter: Color(0xFF0A2416),
          bgEdge: Color(0xFF030D08),
          grid: Color(0xFF154E30),
          primary: Color(0xFF31FF8C),
          secondary: Color(0xFFADFFCC),
          warn: Color(0xFFFFC947),
          alert: Color(0xFFFF4D4D),
        );
    }
  }
}
