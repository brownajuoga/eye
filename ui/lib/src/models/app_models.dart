enum AppSection { dashboard, settings, feeds, chat, models, controls, expert, videos, logs, rules }

class DetectionItem {
  const DetectionItem({
    required this.label,
    required this.confidence,
    required this.box,
    required this.model,
    this.reason = '',
  });

  final String label;
  final double confidence;
  final List<int> box;
  final String model;
  final String reason;

  factory DetectionItem.fromJson(Map<String, dynamic> json) {
    return DetectionItem(
      label: json['label'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      box: (json['box'] as List<dynamic>? ?? const []).map((value) => (value as num).toInt()).toList(),
      model: json['model'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }
}

class WifiEntity {
  const WifiEntity({
    required this.id,
    required this.rawKey,
    required this.label,
    required this.bssid,
    required this.ssid,
    required this.security,
    required this.category,
    required this.threat,
    required this.channel,
    required this.rssi,
    required this.ewmaRssi,
    required this.zScore,
    required this.disturbance,
    required this.pps,
    required this.randomized,
    required this.inUse,
    required this.fade,
    required this.x,
    required this.y,
  });

  final String id;
  final String rawKey;
  final String label;
  final String bssid;
  final String ssid;
  final String security;
  final String category;
  final String? threat;
  final int channel;
  final int rssi;
  final double ewmaRssi;
  final double zScore;
  final double disturbance;
  final double pps;
  final bool randomized;
  final bool inUse;
  final double fade;
  final double x;
  final double y;

  factory WifiEntity.fromJson(Map<String, dynamic> json) {
    return WifiEntity(
      id: json['id'] as String? ?? '',
      rawKey: json['raw_key'] as String? ?? '',
      label: json['label'] as String? ?? 'unknown',
      bssid: json['bssid'] as String? ?? '',
      ssid: json['ssid'] as String? ?? '',
      security: json['security'] as String? ?? '',
      category: json['category'] as String? ?? 'client',
      threat: json['threat'] as String?,
      channel: (json['channel'] as num?)?.toInt() ?? 6,
      rssi: (json['rssi'] as num?)?.toInt() ?? -70,
      ewmaRssi: (json['ewma_rssi'] as num?)?.toDouble() ?? -70,
      zScore: (json['z_score'] as num?)?.toDouble() ?? 0,
      disturbance: (json['disturbance'] as num?)?.toDouble() ?? 0,
      pps: (json['pps'] as num?)?.toDouble() ?? 0,
      randomized: json['randomized'] as bool? ?? false,
      inUse: json['in_use'] as bool? ?? false,
      fade: (json['fade'] as num?)?.toDouble() ?? 1.0,
      x: (json['x'] as num?)?.toDouble() ?? 0.5,
      y: (json['y'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

class WifiLink {
  const WifiLink({
    required this.id,
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
    required this.label,
    required this.rssi,
    required this.disturbance,
    required this.crossing,
  });

  final String id;
  final double fromX;
  final double fromY;
  final double toX;
  final double toY;
  final String label;
  final int rssi;
  final double disturbance;
  final bool crossing;

  factory WifiLink.fromJson(Map<String, dynamic> json) {
    return WifiLink(
      id: json['id'] as String? ?? '',
      fromX: (json['from_x'] as num?)?.toDouble() ?? 0.5,
      fromY: (json['from_y'] as num?)?.toDouble() ?? 0.68,
      toX: (json['to_x'] as num?)?.toDouble() ?? 0.5,
      toY: (json['to_y'] as num?)?.toDouble() ?? 0.35,
      label: json['label'] as String? ?? 'AP',
      rssi: (json['rssi'] as num?)?.toInt() ?? -60,
      disturbance: (json['disturbance'] as num?)?.toDouble() ?? 0,
      crossing: json['crossing'] as bool? ?? false,
    );
  }
}

class WifiChannelMetric {
  const WifiChannelMetric({
    required this.channel,
    required this.frames,
    required this.apCount,
    required this.congestion,
    required this.meanRssi,
  });

  final int channel;
  final int frames;
  final int apCount;
  final double congestion;
  final double meanRssi;

  factory WifiChannelMetric.fromJson(Map<String, dynamic> json) {
    return WifiChannelMetric(
      channel: (json['channel'] as num?)?.toInt() ?? 1,
      frames: (json['frames'] as num?)?.toInt() ?? 0,
      apCount: (json['ap_count'] as num?)?.toInt() ?? 0,
      congestion: (json['congestion'] as num?)?.toDouble() ?? 0,
      meanRssi: (json['mean_rssi'] as num?)?.toDouble() ?? -95,
    );
  }
}

class WifiWaveformPoint {
  const WifiWaveformPoint({
    required this.rssi,
    required this.baseline,
    required this.disturbance,
  });

  final double rssi;
  final double baseline;
  final double disturbance;

  factory WifiWaveformPoint.fromJson(Map<String, dynamic> json) {
    return WifiWaveformPoint(
      rssi: (json['rssi'] as num?)?.toDouble() ?? -65,
      baseline: (json['baseline'] as num?)?.toDouble() ?? -65,
      disturbance: (json['disturbance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class WifiAlertItem {
  const WifiAlertItem({
    required this.timestamp,
    required this.type,
    required this.confidence,
    required this.reason,
  });

  final String timestamp;
  final String type;
  final double confidence;
  final String reason;

  factory WifiAlertItem.fromJson(Map<String, dynamic> json) {
    return WifiAlertItem(
      timestamp: json['timestamp'] as String? ?? '',
      type: json['type'] as String? ?? 'alert',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      reason: json['reason'] as String? ?? '',
    );
  }
}

class WifiVisionState {
  const WifiVisionState({
    required this.timestamp,
    required this.sourceId,
    required this.sourceName,
    required this.sourceKind,
    required this.mode,
    required this.privacyMode,
    required this.sensorX,
    required this.sensorY,
    required this.entities,
    required this.links,
    required this.channels,
    required this.waveform,
    required this.occupancyEstimate,
    required this.occupancyDensity,
    required this.activeClients,
    required this.activeAps,
    required this.totalPackets,
    required this.recentPackets45s,
    required this.deauth12s,
    required this.disturbance,
    required this.maxZScore,
    required this.tripwireTriggered,
    required this.peakCongestion,
    required this.recommendedChannel,
    required this.alerts,
    required this.alertBanner,
    this.replay,
  });

  final String timestamp;
  final String sourceId;
  final String sourceName;
  final String sourceKind;
  final String mode;
  final bool privacyMode;
  final double sensorX;
  final double sensorY;
  final List<WifiEntity> entities;
  final List<WifiLink> links;
  final List<WifiChannelMetric> channels;
  final List<WifiWaveformPoint> waveform;
  final int occupancyEstimate;
  final String occupancyDensity;
  final int activeClients;
  final int activeAps;
  final int totalPackets;
  final int recentPackets45s;
  final int deauth12s;
  final double disturbance;
  final double maxZScore;
  final bool tripwireTriggered;
  final double peakCongestion;
  final int recommendedChannel;
  final List<WifiAlertItem> alerts;
  final String alertBanner;
  final Map<String, dynamic>? replay;

  factory WifiVisionState.empty() {
    return const WifiVisionState(
      timestamp: '',
      sourceId: 'standby',
      sourceName: 'Standby',
      sourceKind: 'standby',
      mode: 'multi',
      privacyMode: false,
      sensorX: 0.5,
      sensorY: 0.68,
      entities: [],
      links: [],
      channels: [],
      waveform: [],
      occupancyEstimate: 0,
      occupancyDensity: 'empty',
      activeClients: 0,
      activeAps: 0,
      totalPackets: 0,
      recentPackets45s: 0,
      deauth12s: 0,
      disturbance: 0,
      maxZScore: 0,
      tripwireTriggered: false,
      peakCongestion: 0,
      recommendedChannel: 6,
      alerts: [],
      alertBanner: '',
    );
  }

  factory WifiVisionState.fromJson(Map<String, dynamic> json) {
    final sensor = json['sensor'] as Map<String, dynamic>? ?? const {};
    final occ = json['occupancy'] as Map<String, dynamic>? ?? const {};
    final metrics = json['metrics'] as Map<String, dynamic>? ?? const {};
    return WifiVisionState(
      timestamp: json['timestamp'] as String? ?? '',
      sourceId: json['source_id'] as String? ?? 'standby',
      sourceName: json['source_name'] as String? ?? 'Standby',
      sourceKind: json['source_kind'] as String? ?? 'standby',
      mode: json['mode'] as String? ?? 'multi',
      privacyMode: json['privacy_mode'] as bool? ?? false,
      sensorX: (sensor['x'] as num?)?.toDouble() ?? 0.5,
      sensorY: (sensor['y'] as num?)?.toDouble() ?? 0.68,
      entities: (json['entities'] as List<dynamic>? ?? const [])
          .map((e) => WifiEntity.fromJson(e as Map<String, dynamic>))
          .toList(),
      links: (json['links'] as List<dynamic>? ?? const [])
          .map((e) => WifiLink.fromJson(e as Map<String, dynamic>))
          .toList(),
      channels: (json['channels'] as List<dynamic>? ?? const [])
          .map((e) => WifiChannelMetric.fromJson(e as Map<String, dynamic>))
          .toList(),
      waveform: (json['waveform'] as List<dynamic>? ?? const [])
          .map((e) => WifiWaveformPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      occupancyEstimate: (occ['estimate'] as num?)?.toInt() ?? 0,
      occupancyDensity: occ['density'] as String? ?? 'empty',
      activeClients: (occ['active_clients'] as num?)?.toInt() ?? 0,
      activeAps: (occ['active_aps'] as num?)?.toInt() ?? 0,
      totalPackets: (metrics['total_packets'] as num?)?.toInt() ?? 0,
      recentPackets45s: (metrics['recent_packets_45s'] as num?)?.toInt() ?? 0,
      deauth12s: (metrics['deauth_12s'] as num?)?.toInt() ?? 0,
      disturbance: (metrics['disturbance'] as num?)?.toDouble() ?? 0,
      maxZScore: (metrics['max_z_score'] as num?)?.toDouble() ?? 0,
      tripwireTriggered: metrics['tripwire_triggered'] as bool? ?? false,
      peakCongestion: (metrics['peak_congestion'] as num?)?.toDouble() ?? 0,
      recommendedChannel: (metrics['recommended_channel'] as num?)?.toInt() ?? 6,
      alerts: (json['alerts'] as List<dynamic>? ?? const [])
          .map((e) => WifiAlertItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      alertBanner: json['alert_banner'] as String? ?? '',
      replay: json['replay'] as Map<String, dynamic>?,
    );
  }
}

class WifiSourcesStatus {
  const WifiSourcesStatus({
    required this.simulatorRunning,
    required this.simulatorScenario,
    required this.hostScanRunning,
    required this.hostInterface,
    required this.replayRunning,
  });

  final bool simulatorRunning;
  final String simulatorScenario;
  final bool hostScanRunning;
  final String hostInterface;
  final bool replayRunning;

  factory WifiSourcesStatus.empty() {
    return const WifiSourcesStatus(
      simulatorRunning: false,
      simulatorScenario: 'mixed',
      hostScanRunning: false,
      hostInterface: 'wlp13s0',
      replayRunning: false,
    );
  }

  factory WifiSourcesStatus.fromJson(Map<String, dynamic> json) {
    return WifiSourcesStatus(
      simulatorRunning: json['simulator_running'] as bool? ?? false,
      simulatorScenario: json['simulator_scenario'] as String? ?? 'mixed',
      hostScanRunning: json['host_scan_running'] as bool? ?? false,
      hostInterface: json['host_interface'] as String? ?? 'wlp13s0',
      replayRunning: json['replay_running'] as bool? ?? false,
    );
  }
}

class NodeMcuConfig {
  const NodeMcuConfig({
    required this.mode,
    required this.channelHop,
    required this.lockedChannel,
    required this.privacyMode,
    required this.canarySsid,
    required this.wifiSsid,
    required this.serverUrl,
  });

  final String mode;
  final bool channelHop;
  final int lockedChannel;
  final bool privacyMode;
  final String canarySsid;
  final String wifiSsid;
  final String serverUrl;

  factory NodeMcuConfig.fromJson(Map<String, dynamic> json) {
    return NodeMcuConfig(
      mode: json['mode'] as String? ?? 'promisc',
      channelHop: json['channel_hop'] as bool? ?? true,
      lockedChannel: (json['locked_channel'] as num?)?.toInt() ?? 6,
      privacyMode: json['privacy_mode'] as bool? ?? false,
      canarySsid: json['canary_ssid'] as String? ?? 'EYE_CANARY_AP',
      wifiSsid: json['wifi_ssid'] as String? ?? '',
      serverUrl: json['server_url'] as String? ?? 'http://192.168.1.100:8080/wifi/ingest',
    );
  }

  NodeMcuConfig copyWith({
    String? mode,
    bool? channelHop,
    int? lockedChannel,
    bool? privacyMode,
    String? canarySsid,
    String? wifiSsid,
    String? serverUrl,
  }) {
    return NodeMcuConfig(
      mode: mode ?? this.mode,
      channelHop: channelHop ?? this.channelHop,
      lockedChannel: lockedChannel ?? this.lockedChannel,
      privacyMode: privacyMode ?? this.privacyMode,
      canarySsid: canarySsid ?? this.canarySsid,
      wifiSsid: wifiSsid ?? this.wifiSsid,
      serverUrl: serverUrl ?? this.serverUrl,
    );
  }
}

class WifiPolicySettings {
  const WifiPolicySettings({
    required this.mode,
    required this.visionPalette,
    required this.privacyMode,
    required this.tripwireZThreshold,
    required this.deauthRateThreshold,
    required this.channelHop,
    required this.lockedChannel,
    required this.nodemcuMode,
    required this.canarySsid,
    required this.knownAps,
  });

  final String mode;
  final String visionPalette;
  final bool privacyMode;
  final double tripwireZThreshold;
  final int deauthRateThreshold;
  final bool channelHop;
  final int lockedChannel;
  final String nodemcuMode;
  final String canarySsid;
  final Map<String, dynamic> knownAps;

  factory WifiPolicySettings.fromPolicy(Map<String, dynamic> policy) {
    final w = policy['wifi'] as Map<String, dynamic>? ?? const {};
    return WifiPolicySettings(
      mode: w['mode'] as String? ?? 'multi',
      visionPalette: w['vision_palette'] as String? ?? 'night_vision',
      privacyMode: w['privacy_mode'] as bool? ?? false,
      tripwireZThreshold: (w['tripwire_z_threshold'] as num?)?.toDouble() ?? 2.1,
      deauthRateThreshold: (w['deauth_rate_threshold'] as num?)?.toInt() ?? 5,
      channelHop: w['channel_hop'] as bool? ?? true,
      lockedChannel: (w['locked_channel'] as num?)?.toInt() ?? 6,
      nodemcuMode: w['nodemcu_mode'] as String? ?? 'promisc',
      canarySsid: w['canary_ssid'] as String? ?? 'EYE_CANARY_AP',
      knownAps: w['known_aps'] as Map<String, dynamic>? ?? const {},
    );
  }

  WifiPolicySettings copyWith({
    String? mode,
    String? visionPalette,
    bool? privacyMode,
    double? tripwireZThreshold,
    int? deauthRateThreshold,
    bool? channelHop,
    int? lockedChannel,
    String? nodemcuMode,
    String? canarySsid,
    Map<String, dynamic>? knownAps,
  }) {
    return WifiPolicySettings(
      mode: mode ?? this.mode,
      visionPalette: visionPalette ?? this.visionPalette,
      privacyMode: privacyMode ?? this.privacyMode,
      tripwireZThreshold: tripwireZThreshold ?? this.tripwireZThreshold,
      deauthRateThreshold: deauthRateThreshold ?? this.deauthRateThreshold,
      channelHop: channelHop ?? this.channelHop,
      lockedChannel: lockedChannel ?? this.lockedChannel,
      nodemcuMode: nodemcuMode ?? this.nodemcuMode,
      canarySsid: canarySsid ?? this.canarySsid,
      knownAps: knownAps ?? this.knownAps,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'vision_palette': visionPalette,
      'privacy_mode': privacyMode,
      'tripwire_z_threshold': tripwireZThreshold,
      'deauth_rate_threshold': deauthRateThreshold,
      'channel_hop': channelHop,
      'locked_channel': lockedChannel,
      'nodemcu_mode': nodemcuMode,
      'canary_ssid': canarySsid,
      'known_aps': knownAps,
    };
  }
}

class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.format,
    required this.sizeBytes,
    this.active = false,
  });

  final String id;
  final String name;
  final String path;
  final String format;
  final int? sizeBytes;
  final bool active;

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'unknown',
      path: json['path'] as String? ?? '',
      format: json['format'] as String? ?? '',
      sizeBytes: json['size_bytes'] as int?,
      active: json['active'] as bool? ?? false,
    );
  }
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.message,
    required this.level,
  });

  final String timestamp;
  final String message;
  final String level;

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: json['timestamp'] as String? ?? '',
      message: json['message'] as String? ?? '',
      level: json['level'] as String? ?? 'info',
    );
  }
}

class RuleItem {
  const RuleItem({
    required this.name,
    required this.condition,
    required this.action,
    this.enabled = true,
  });

  final String name;
  final String condition;
  final String action;
  final bool enabled;

  RuleItem copyWith({
    String? name,
    String? condition,
    String? action,
    bool? enabled,
  }) {
    return RuleItem(
      name: name ?? this.name,
      condition: condition ?? this.condition,
      action: action ?? this.action,
      enabled: enabled ?? this.enabled,
    );
  }

  factory RuleItem.fromJson(Map<String, dynamic> json) {
    return RuleItem(
      name: json['name'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
      action: json['action'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'condition': condition,
      'action': action,
      'enabled': enabled,
    };
  }
}

class ControlState {
  const ControlState({
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.autoMode,
    required this.detectionEnabled,
    required this.mode,
  });

  final double confidenceThreshold;
  final double iouThreshold;
  final bool autoMode;
  final bool detectionEnabled;
  final String mode;

  factory ControlState.fromPolicy(Map<String, dynamic> policy) {
    final controls = policy['controls'] as Map<String, dynamic>? ?? const {};
    return ControlState(
      confidenceThreshold: (controls['confidence_threshold'] as num?)?.toDouble() ?? 0.35,
      iouThreshold: (controls['iou_threshold'] as num?)?.toDouble() ?? 0.5,
      autoMode: controls['auto_mode'] as bool? ?? true,
      detectionEnabled: controls['detection_enabled'] as bool? ?? true,
      mode: policy['mode'] as String? ?? 'balanced',
    );
  }

  ControlState copyWith({
    double? confidenceThreshold,
    double? iouThreshold,
    bool? autoMode,
    bool? detectionEnabled,
    String? mode,
  }) {
    return ControlState(
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      iouThreshold: iouThreshold ?? this.iouThreshold,
      autoMode: autoMode ?? this.autoMode,
      detectionEnabled: detectionEnabled ?? this.detectionEnabled,
      mode: mode ?? this.mode,
    );
  }
}

class RuntimeInfo {
  const RuntimeInfo({
    required this.backend,
    required this.ramGb,
    required this.cpuCount,
    required this.effectiveMode,
    required this.resources,
  });

  final String backend;
  final double ramGb;
  final int cpuCount;
  final String effectiveMode;
  final Map<String, dynamic> resources;

  factory RuntimeInfo.fromJson(Map<String, dynamic> json) {
    return RuntimeInfo(
      backend: json['backend'] as String? ?? 'unknown',
      ramGb: (json['ram_gb'] as num?)?.toDouble() ?? 0,
      cpuCount: json['cpu_count'] as int? ?? 0,
      effectiveMode: json['effective_mode'] as String? ?? 'balanced',
      resources: json['resources'] as Map<String, dynamic>? ?? const {},
    );
  }
}

class FrameInfo {
  const FrameInfo({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  factory FrameInfo.fromJson(Map<String, dynamic> json) {
    return FrameInfo(
      width: json['width'] as int? ?? 0,
      height: json['height'] as int? ?? 0,
    );
  }
}

class LatestResult {
  const LatestResult({
    required this.detections,
    required this.eventImportant,
    required this.eventReason,
    required this.expertAction,
    required this.expertReason,
    required this.frame,
  });

  final List<DetectionItem> detections;
  final bool eventImportant;
  final String eventReason;
  final String expertAction;
  final String expertReason;
  final FrameInfo? frame;

  factory LatestResult.fromJson(Map<String, dynamic> json) {
    final event = json['event'] as Map<String, dynamic>? ?? const {};
    final expert = json['expert'] as Map<String, dynamic>? ?? const {};
    final frameJson = json['frame'] as Map<String, dynamic>?;
    return LatestResult(
      detections: (json['detections'] as List<dynamic>? ?? const [])
          .map((item) => DetectionItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      eventImportant: event['important'] as bool? ?? false,
      eventReason: event['reason'] as String? ?? '',
      expertAction: expert['action'] as String? ?? '',
      expertReason: expert['reason'] as String? ?? '',
      frame: frameJson == null ? null : FrameInfo.fromJson(frameJson),
    );
  }
}

class VideoAnalysisResult {
  const VideoAnalysisResult({
    required this.captureId,
    required this.filename,
    required this.createdAt,
    required this.framesProcessed,
    required this.totalPackets,
    required this.dominantAction,
    required this.aggregatedLabels,
    required this.timeline,
  });

  final String captureId;
  final String filename;
  final String createdAt;
  final int framesProcessed;
  final int totalPackets;
  final String dominantAction;
  final List<String> aggregatedLabels;
  final List<Map<String, dynamic>> timeline;

  factory VideoAnalysisResult.fromJson(Map<String, dynamic> json) {
    return VideoAnalysisResult(
      captureId: json['capture_id'] as String? ?? '',
      filename: json['filename'] as String? ?? 'capture',
      createdAt: json['created_at'] as String? ?? '',
      framesProcessed: (json['frames_processed'] as num?)?.toInt() ?? 0,
      totalPackets: (json['total_packets'] as num?)?.toInt() ?? 0,
      dominantAction: json['dominant_action'] as String? ?? 'ignore',
      aggregatedLabels: (json['aggregated_labels'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      timeline: (json['timeline'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.policy,
    required this.controlState,
    required this.wifiSettings,
    required this.runtime,
    required this.capabilities,
    required this.models,
    required this.logs,
    required this.rules,
    required this.latestResult,
    required this.latestFrameUrl,
    required this.videoHistory,
    required this.feeds,
    required this.chatHistory,
    required this.wifiVision,
    required this.wifiSourcesStatus,
    required this.nodemcuConfig,
  });

  final Map<String, dynamic> policy;
  final ControlState controlState;
  final WifiPolicySettings wifiSettings;
  final RuntimeInfo runtime;
  final Map<String, dynamic> capabilities;
  final List<ModelInfo> models;
  final List<LogEntry> logs;
  final List<RuleItem> rules;
  final LatestResult? latestResult;
  final String? latestFrameUrl;
  final List<VideoAnalysisResult> videoHistory;
  final List<FeedSnapshot> feeds;
  final List<ChatMessage> chatHistory;
  final WifiVisionState wifiVision;
  final WifiSourcesStatus wifiSourcesStatus;
  final NodeMcuConfig nodemcuConfig;

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json, {required String baseUrl}) {
    final policy = json['policy'] as Map<String, dynamic>? ?? const {};
    final latestResultJson = json['latest_result'] as Map<String, dynamic>?;
    final latestFrameUrl = json['latest_frame_url'] as String?;
    final visionJson = json['wifi_vision'] as Map<String, dynamic>?;
    final statusJson = json['wifi_sources_status'] as Map<String, dynamic>?;
    final nodeJson = json['nodemcu'] as Map<String, dynamic>?;
    return DashboardSnapshot(
      policy: policy,
      controlState: ControlState.fromPolicy(policy),
      wifiSettings: WifiPolicySettings.fromPolicy(policy),
      runtime: RuntimeInfo.fromJson(json['runtime'] as Map<String, dynamic>? ?? const {}),
      capabilities: json['capabilities'] as Map<String, dynamic>? ?? const {},
      models: (json['models'] as List<dynamic>? ?? const [])
          .map((item) => ModelInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
      logs: (json['logs'] as List<dynamic>? ?? const [])
          .map((item) => LogEntry.fromJson(item as Map<String, dynamic>))
          .toList()
          .reversed
          .toList(),
      rules: ((policy['automation_rules'] as List<dynamic>? ?? const []))
          .map((item) => RuleItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      latestResult: latestResultJson == null ? null : LatestResult.fromJson(latestResultJson),
      latestFrameUrl: latestFrameUrl == null ? null : '$baseUrl$latestFrameUrl',
      videoHistory: ((json['video_history'] as List<dynamic>? ?? const []))
          .map((item) => VideoAnalysisResult.fromJson(item as Map<String, dynamic>))
          .toList(),
      feeds: ((json['feeds'] as List<dynamic>? ?? const []))
          .map((item) => FeedSnapshot.fromJson(item as Map<String, dynamic>, baseUrl: baseUrl))
          .toList(),
      chatHistory: ((json['chat_history'] as List<dynamic>? ?? const []))
          .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList(),
      wifiVision: visionJson == null ? WifiVisionState.empty() : WifiVisionState.fromJson(visionJson),
      wifiSourcesStatus: statusJson == null ? WifiSourcesStatus.empty() : WifiSourcesStatus.fromJson(statusJson),
      nodemcuConfig: nodeJson == null ? NodeMcuConfig.fromJson(const {}) : NodeMcuConfig.fromJson(nodeJson),
    );
  }
}

class ExpertSettings {
  const ExpertSettings({
    required this.backend,
    required this.realtimeEnabled,
    required this.realtimeOnlyImportant,
    required this.ollamaModel,
    required this.transformersModel,
    required this.maxRetries,
    required this.timeoutSeconds,
    required this.taskProfile,
    required this.mission,
    required this.operatorInstructions,
    required this.activeTask,
  });

  final String backend;
  final bool realtimeEnabled;
  final bool realtimeOnlyImportant;
  final String ollamaModel;
  final String transformersModel;
  final int maxRetries;
  final int timeoutSeconds;
  final String taskProfile;
  final String mission;
  final String operatorInstructions;
  final String activeTask;

  factory ExpertSettings.fromPolicy(Map<String, dynamic> policy) {
    final expert = policy['expert'] as Map<String, dynamic>? ?? const {};
    return ExpertSettings(
      backend: expert['backend'] as String? ?? 'mock',
      realtimeEnabled: expert['realtime_enabled'] as bool? ?? false,
      realtimeOnlyImportant: expert['realtime_only_important'] as bool? ?? true,
      ollamaModel: expert['ollama_model'] as String? ?? 'llava:7b',
      transformersModel: expert['transformers_model'] as String? ?? 'vikhyatk/moondream2',
      maxRetries: (expert['max_retries'] as num?)?.toInt() ?? 2,
      timeoutSeconds: (expert['timeout_seconds'] as num?)?.toInt() ?? 20,
      taskProfile: expert['task_profile'] as String? ?? 'wifi_security',
      mission: expert['mission'] as String? ?? '',
      operatorInstructions: expert['operator_instructions'] as String? ?? '',
      activeTask: expert['active_task'] as String? ?? '',
    );
  }

  ExpertSettings copyWith({
    String? backend,
    bool? realtimeEnabled,
    bool? realtimeOnlyImportant,
    String? ollamaModel,
    String? transformersModel,
    int? maxRetries,
    int? timeoutSeconds,
    String? taskProfile,
    String? mission,
    String? operatorInstructions,
    String? activeTask,
  }) {
    return ExpertSettings(
      backend: backend ?? this.backend,
      realtimeEnabled: realtimeEnabled ?? this.realtimeEnabled,
      realtimeOnlyImportant: realtimeOnlyImportant ?? this.realtimeOnlyImportant,
      ollamaModel: ollamaModel ?? this.ollamaModel,
      transformersModel: transformersModel ?? this.transformersModel,
      maxRetries: maxRetries ?? this.maxRetries,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      taskProfile: taskProfile ?? this.taskProfile,
      mission: mission ?? this.mission,
      operatorInstructions: operatorInstructions ?? this.operatorInstructions,
      activeTask: activeTask ?? this.activeTask,
    );
  }
}

class WatchlistSettings {
  const WatchlistSettings({
    required this.watchFor,
    required this.ignore,
    this.knownAps = const {},
  });

  final List<String> watchFor;
  final List<String> ignore;
  final Map<String, dynamic> knownAps;

  factory WatchlistSettings.fromPolicy(Map<String, dynamic> policy) {
    final wifi = policy['wifi'] as Map<String, dynamic>? ?? const {};
    return WatchlistSettings(
      watchFor: (policy['watch_for'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      ignore: (policy['ignore'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      knownAps: wifi['known_aps'] as Map<String, dynamic>? ?? const {},
    );
  }
}

class SettingsConfig {
  const SettingsConfig({
    required this.mode,
    required this.detectionEnabled,
    required this.autoMode,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.videoSampleIntervalSeconds,
    required this.videoMaxFrames,
    required this.refreshIntervalSeconds,
    required this.defaultFeedId,
    required this.memoryMaxEvents,
    required this.memoryRecentLimit,
    required this.memoryPatternWindow,
    required this.expertBackend,
    required this.ollamaModel,
    required this.transformersModel,
    required this.maxRetries,
    required this.timeoutSeconds,
    required this.taskProfile,
    required this.mission,
    required this.operatorInstructions,
    required this.activeTask,
    required this.taskRouting,
  });

  final String mode;
  final bool detectionEnabled;
  final bool autoMode;
  final double confidenceThreshold;
  final double iouThreshold;
  final double videoSampleIntervalSeconds;
  final int videoMaxFrames;
  final double refreshIntervalSeconds;
  final String defaultFeedId;
  final int memoryMaxEvents;
  final int memoryRecentLimit;
  final int memoryPatternWindow;
  final String expertBackend;
  final String ollamaModel;
  final String transformersModel;
  final int maxRetries;
  final int timeoutSeconds;
  final String taskProfile;
  final String mission;
  final String operatorInstructions;
  final String activeTask;
  final Map<String, TaskRouteConfig> taskRouting;

  factory SettingsConfig.fromPolicy(Map<String, dynamic> policy) {
    final controls = policy['controls'] as Map<String, dynamic>? ?? const {};
    final video = policy['video_analysis'] as Map<String, dynamic>? ?? const {};
    final ui = policy['ui'] as Map<String, dynamic>? ?? const {};
    final memory = policy['memory'] as Map<String, dynamic>? ?? const {};
    final expert = policy['expert'] as Map<String, dynamic>? ?? const {};
    final routes = policy['task_routing'] as Map<String, dynamic>? ?? const {};
    return SettingsConfig(
      mode: policy['mode'] as String? ?? 'balanced',
      detectionEnabled: controls['detection_enabled'] as bool? ?? true,
      autoMode: controls['auto_mode'] as bool? ?? true,
      confidenceThreshold: (controls['confidence_threshold'] as num?)?.toDouble() ?? 0.35,
      iouThreshold: (controls['iou_threshold'] as num?)?.toDouble() ?? 0.5,
      videoSampleIntervalSeconds: (video['sample_interval_seconds'] as num?)?.toDouble() ?? 1.0,
      videoMaxFrames: (video['max_frames'] as num?)?.toInt() ?? 24,
      refreshIntervalSeconds: (ui['refresh_interval_seconds'] as num?)?.toDouble() ?? 1.5,
      defaultFeedId: ui['default_feed_id'] as String? ?? '',
      memoryMaxEvents: (memory['max_events'] as num?)?.toInt() ?? 500,
      memoryRecentLimit: (memory['recent_limit'] as num?)?.toInt() ?? 12,
      memoryPatternWindow: (memory['pattern_window'] as num?)?.toInt() ?? 25,
      expertBackend: expert['backend'] as String? ?? 'mock',
      ollamaModel: expert['ollama_model'] as String? ?? 'llava:7b-v1.6',
      transformersModel: expert['transformers_model'] as String? ?? 'vikhyatk/moondream2',
      maxRetries: (expert['max_retries'] as num?)?.toInt() ?? 2,
      timeoutSeconds: (expert['timeout_seconds'] as num?)?.toInt() ?? 20,
      taskProfile: expert['task_profile'] as String? ?? 'wifi_security',
      mission: expert['mission'] as String? ?? '',
      operatorInstructions: expert['operator_instructions'] as String? ?? '',
      activeTask: expert['active_task'] as String? ?? '',
      taskRouting: {
        for (final entry in routes.entries)
          entry.key: TaskRouteConfig.fromJson(entry.value as Map<String, dynamic>? ?? const {}),
      },
    );
  }

  Map<String, dynamic> toPolicyPatch() {
    return {
      'mode': mode,
      'controls': {
        'detection_enabled': detectionEnabled,
        'auto_mode': autoMode,
        'confidence_threshold': confidenceThreshold,
        'iou_threshold': iouThreshold,
      },
      'rules': {
        'min_confidence': confidenceThreshold,
      },
      'model': {
        'confidence_threshold': confidenceThreshold,
      },
      'video_analysis': {
        'sample_interval_seconds': videoSampleIntervalSeconds,
        'max_frames': videoMaxFrames,
      },
      'ui': {
        'refresh_interval_seconds': refreshIntervalSeconds,
        'default_feed_id': defaultFeedId,
      },
      'memory': {
        'max_events': memoryMaxEvents,
        'recent_limit': memoryRecentLimit,
        'pattern_window': memoryPatternWindow,
      },
      'expert': {
        'backend': expertBackend,
        'ollama_model': ollamaModel,
        'transformers_model': transformersModel,
        'max_retries': maxRetries,
        'timeout_seconds': timeoutSeconds,
        'task_profile': taskProfile,
        'mission': mission,
        'operator_instructions': operatorInstructions,
        'active_task': activeTask,
      },
      'task_routing': {
        for (final entry in taskRouting.entries) entry.key: entry.value.toJson(),
      },
    };
  }
}

class TaskRouteConfig {
  const TaskRouteConfig({
    required this.mode,
    required this.expertBackend,
    required this.preferredModel,
    required this.feedStrategy,
  });

  final String mode;
  final String expertBackend;
  final String preferredModel;
  final String feedStrategy;

  factory TaskRouteConfig.fromJson(Map<String, dynamic> json) {
    return TaskRouteConfig(
      mode: json['mode'] as String? ?? 'balanced',
      expertBackend: json['expert_backend'] as String? ?? 'mock',
      preferredModel: json['preferred_model'] as String? ?? 'rf_multi_guard.profile',
      feedStrategy: json['feed_strategy'] as String? ?? 'latest',
    );
  }

  TaskRouteConfig copyWith({
    String? mode,
    String? expertBackend,
    String? preferredModel,
    String? feedStrategy,
  }) {
    return TaskRouteConfig(
      mode: mode ?? this.mode,
      expertBackend: expertBackend ?? this.expertBackend,
      preferredModel: preferredModel ?? this.preferredModel,
      feedStrategy: feedStrategy ?? this.feedStrategy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'mode': mode,
      'expert_backend': expertBackend,
      'preferred_model': preferredModel,
      'feed_strategy': feedStrategy,
    };
  }
}

class FeedSnapshot {
  const FeedSnapshot({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.live,
    required this.updatedAt,
    required this.frameUrl,
    required this.detections,
    required this.eventReason,
    required this.expertReason,
  });

  final String id;
  final String sourceId;
  final String name;
  final bool live;
  final String updatedAt;
  final String? frameUrl;
  final List<DetectionItem> detections;
  final String eventReason;
  final String expertReason;

  factory FeedSnapshot.fromJson(Map<String, dynamic> json, {required String baseUrl}) {
    final event = json['event'] as Map<String, dynamic>? ?? const {};
    final expert = json['expert'] as Map<String, dynamic>? ?? const {};
    final frameUrl = json['frame_url'] as String?;
    return FeedSnapshot(
      id: json['id'] as String? ?? '',
      sourceId: json['source_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      live: json['live'] as bool? ?? true,
      updatedAt: json['updated_at'] as String? ?? '',
      frameUrl: frameUrl == null ? null : '$baseUrl$frameUrl',
      detections: (json['detections'] as List<dynamic>? ?? const [])
          .map((item) => DetectionItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      eventReason: event['reason'] as String? ?? '',
      expertReason: expert['reason'] as String? ?? '',
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.timestamp,
    required this.role,
    required this.content,
    this.feedId,
    this.taskSummary = '',
    this.plan = const {},
    this.evidence = const [],
    this.actions = const [],
  });

  final String timestamp;
  final String role;
  final String content;
  final String? feedId;
  final String taskSummary;
  final Map<String, dynamic> plan;
  final List<Map<String, dynamic>> evidence;
  final List<Map<String, dynamic>> actions;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      timestamp: json['timestamp'] as String? ?? '',
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      feedId: json['feed_id'] as String?,
      taskSummary: json['task_summary'] as String? ?? '',
      plan: json['plan'] as Map<String, dynamic>? ?? const {},
      evidence: (json['evidence'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      actions: (json['actions'] as List<dynamic>? ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
    );
  }
}
