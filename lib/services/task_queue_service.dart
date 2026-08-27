import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum TaskStatus { running, cancelled, finished, failed }

/// 一个后台任务（A04）。
class AgentTask {
  AgentTask({
    required this.id,
    required this.conversationId,
    required this.title,
    this.status = TaskStatus.running,
    this.progress = '',
    this.checkpoint,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String conversationId;
  final String title;
  TaskStatus status;
  String progress;
  Map<String, dynamic>? checkpoint;
  final DateTime createdAt;
  DateTime updatedAt;

  factory AgentTask.fromJson(Map<String, dynamic> m) => AgentTask(
    id: (m['id'] ?? '').toString(),
    conversationId: (m['conversationId'] ?? '').toString(),
    title: (m['title'] ?? '').toString(),
    status: TaskStatus.values.firstWhere(
      (s) => s.name == m['status'],
      orElse: () => TaskStatus.running,
    ),
    progress: (m['progress'] ?? '').toString(),
    checkpoint: m['checkpoint'] is Map
        ? Map<String, dynamic>.from(m['checkpoint'] as Map)
        : null,
    createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()),
    updatedAt: DateTime.tryParse((m['updatedAt'] ?? '').toString()),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'title': title,
    'status': status.name,
    'progress': progress,
    'checkpoint': checkpoint,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// 任务队列/后台执行（A04）+ 断点续跑（A05）。
class TaskQueueService extends ChangeNotifier {
  TaskQueueService._();

  static final TaskQueueService instance = TaskQueueService._();

  /// 测试用：覆盖存储文件位置。
  static File? debugFile;

  final List<AgentTask> _tasks = [];
  String? _pendingResumeId;
  bool _loaded = false;

  Future<File> _file() async {
    final override = debugFile;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/tasks.json');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        _tasks.addAll(
          list
              .whereType<Map>()
              .map((e) => AgentTask.fromJson(Map<String, dynamic>.from(e))),
        );
      }
    } catch (_) {}
  }

  Future<AgentTask> start(String conversationId, String title) async {
    await _ensureLoaded();
    final task = AgentTask(
      id: 'task_${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      title: title.length > 60 ? '${title.substring(0, 60)}...' : title,
    );
    _tasks.insert(0, task);
    await _persist();
    notifyListeners();
    return task;
  }

  Future<void> updateProgress(String id, String progress) async {
    final t = _byId(id);
    if (t == null) return;
    t.progress = progress;
    t.updatedAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  Future<void> markFinished(String id) async {
    final t = _byId(id);
    if (t == null) return;
    t.status = TaskStatus.finished;
    t.progress = '';
    t.updatedAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  Future<void> markFailed(String id, String error) async {
    final t = _byId(id);
    if (t == null) return;
    t.status = TaskStatus.failed;
    t.progress = error;
    t.updatedAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  Future<void> cancelTask(String id, {Map<String, dynamic>? checkpoint}) async {
    final t = _byId(id);
    if (t == null) return;
    t.status = TaskStatus.cancelled;
    if (checkpoint != null) t.checkpoint = checkpoint;
    t.updatedAt = DateTime.now();
    await _persist();
    notifyListeners();
  }

  List<AgentTask> get tasks => List.unmodifiable(_tasks);

  AgentTask? byId(String id) => _byId(id);

  AgentTask? _byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// 请求继续某个任务（A05）：由聊天输入组件消费。
  void requestResume(String id) {
    final t = _byId(id);
    if (t == null || t.status != TaskStatus.cancelled) return;
    if (t.checkpoint == null) return;
    _pendingResumeId = id;
    notifyListeners();
  }

  /// 消费与指定会话匹配的续跑请求，返回检查点。
  Map<String, dynamic>? consumeResume(String conversationId) {
    final id = _pendingResumeId;
    if (id == null) return null;
    final t = _byId(id);
    if (t == null || t.conversationId != conversationId) return null;
    _pendingResumeId = null;
    return Map<String, dynamic>.from(t.checkpoint ?? const {});
  }

  Future<void> remove(String id) async {
    _tasks.removeWhere((t) => t.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode([for (final t in _tasks) t.toJson()]),
      );
    } catch (_) {}
  }

  /// 测试用：重置内存状态。
  Future<void> resetForTest() async {
    _loaded = false;
    _tasks.clear();
    _pendingResumeId = null;
    debugFile = null;
  }

  /// 测试用：重新从磁盘加载。
  Future<void> reloadForTest() async {
    _loaded = false;
    _tasks.clear();
    await _ensureLoaded();
  }
}
