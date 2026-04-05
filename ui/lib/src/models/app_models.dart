enum AppSection { dashboard, feeds, chat, models, controls, expert, videos, logs, rules }

class DetectionItem {
  const DetectionItem({
    required this.label,
    required this.confidence,
    required this.box,
    required this.model,
  });

  final String label;
  final double confidence;
  final List<int> box;
  final String model;

  factory DetectionItem.fromJson(Map<String, dynamic> json) {
    return DetectionItem(
      label: json['label'] as String? ?? 'unknown',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      box: (json['box'] as List<dynamic>? ?? const []).map((value) => value as int).toList(),
      model: json['model'] as String? ?? '',
    );
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

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.policy,
    required this.controlState,
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
  });

  final Map<String, dynamic> policy;
  final ControlState controlState;
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

  factory DashboardSnapshot.fromJson(Map<String, dynamic> json, {required String baseUrl}) {
    final policy = json['policy'] as Map<String, dynamic>? ?? const {};
    final latestResultJson = json['latest_result'] as Map<String, dynamic>?;
    final latestFrameUrl = json['latest_frame_url'] as String?;
    return DashboardSnapshot(
      policy: policy,
      controlState: ControlState.fromPolicy(policy),
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
    );
  }
}

class ExpertSettings {
  const ExpertSettings({
    required this.backend,
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
      ollamaModel: expert['ollama_model'] as String? ?? 'llava:7b',
      transformersModel: expert['transformers_model'] as String? ?? 'vikhyatk/moondream2',
      maxRetries: expert['max_retries'] as int? ?? 2,
      timeoutSeconds: expert['timeout_seconds'] as int? ?? 20,
      taskProfile: expert['task_profile'] as String? ?? 'general',
      mission: expert['mission'] as String? ?? '',
      operatorInstructions: expert['operator_instructions'] as String? ?? '',
      activeTask: expert['active_task'] as String? ?? '',
    );
  }

  ExpertSettings copyWith({
    String? backend,
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
  });

  final List<String> watchFor;
  final List<String> ignore;

  factory WatchlistSettings.fromPolicy(Map<String, dynamic> policy) {
    return WatchlistSettings(
      watchFor: (policy['watch_for'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
      ignore: (policy['ignore'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
    );
  }
}

class VideoAnalysisResult {
  const VideoAnalysisResult({
    required this.filename,
    required this.createdAt,
    required this.framesProcessed,
    required this.dominantAction,
    required this.aggregatedLabels,
  });

  final String filename;
  final String createdAt;
  final int framesProcessed;
  final String dominantAction;
  final List<String> aggregatedLabels;

  factory VideoAnalysisResult.fromJson(Map<String, dynamic> json) {
    return VideoAnalysisResult(
      filename: json['filename'] as String? ?? 'video',
      createdAt: json['created_at'] as String? ?? '',
      framesProcessed: json['frames_processed'] as int? ?? 0,
      dominantAction: json['dominant_action'] as String? ?? 'ignore',
      aggregatedLabels: (json['aggregated_labels'] as List<dynamic>? ?? const []).map((item) => item.toString()).toList(),
    );
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
