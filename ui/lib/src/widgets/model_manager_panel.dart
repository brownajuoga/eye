import 'package:flutter/material.dart';

import '../models/app_models.dart';
import 'panel_shell.dart';

class ModelManagerPanel extends StatelessWidget {
  const ModelManagerPanel({
    super.key,
    required this.models,
    required this.onActivate,
    required this.onUpload,
  });

  final List<ModelInfo> models;
  final Future<void> Function(String path) onActivate;
  final Future<void> Function() onUpload;

  @override
  Widget build(BuildContext context) {
    return PanelShell(
      title: 'YOLO Models',
      subtitle: 'Upload, switch, and inspect detector weights',
      trailing: OutlinedButton(
        onPressed: onUpload,
        child: const Text('Upload New Model'),
      ),
      child: ListView.separated(
        itemCount: models.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final model = models[index];
          return DecoratedBox(
            decoration: BoxDecoration(
              color: model.active ? const Color(0xFFEAF4EE) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: model.active ? const Color(0xFF1E6F5C) : const Color(0xFFE1E8E3),
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              title: Text(model.name),
              subtitle: Text('${model.format.toUpperCase()} • ${_formatBytes(model.sizeBytes)}\n${model.path}'),
              trailing: model.active
                  ? const Chip(label: Text('Active'))
                  : FilledButton(onPressed: () => onActivate(model.path), child: const Text('Activate')),
            ),
          );
        },
      ),
    );
  }

  String _formatBytes(int? size) {
    if (size == null) return 'unknown size';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
