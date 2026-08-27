import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 一条定时任务（A13）。
class ScheduledTask {
  ScheduledTask({
    required this.id,
    required this.conversationId,
    required this.prompt,
    required this.hour,
    required this.minute,
    this.weekdays = const [],
    this.enabled = true,
    this.lastRun,
  });

  final String id;
  final String conversationId;
  final String prompt;
  final int hour;
  final int minute;

  /// 1=周一 ... 7=周日；空表示每天。
  final List<int> weekdays;
  bool enabled;
  DateTime? lastRun;

  DateTime nextFire(DateTime now) {
    var candidate = DateTime(now.year, now.month, now.day, hour, minute);
    if (!candidate.isAfter(now)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    if (weekdays.isNotEmpty) {
      var guard = 0;
      while (!weekdays.contains(candidate.weekday) && guard < 8) {
        candidate = candidate.add(const Duration(days: 1));
        guard++;
      }
    }
    return candidate;
  }

  factory ScheduledTask.fromJson(Map<String, dynamic> m) => ScheduledTask(
    id: (m['id'] ?? '').toString(),
    conversationId: (m['conversationId'] ?? '').toString(),
    prompt: (m['prompt'] ?? '').toString(),
    hour: (m['hour'] as num?)?.toInt() ?? 9,
    minute: (m['minute'] as num?)?.toInt() ?? 0,
    weekdays: ((m['weekdays'] as List?) ?? const [])
        .whereType<num>()
        .map((e) => e.toInt())
        .toList(),
    enabled: m['enabled'] as bool? ?? true,
    lastRun: DateTime.tryParse((m['lastRun'] ?? '').toString()),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'conversationId': conversationId,
    'prompt': prompt,
    'hour': hour,
    'minute': minute,
    'weekdays': weekdays,
    'enabled': enabled,
    'lastRun': lastRun?.toIso8601String(),
  };
}

/// 定时任务服务（A13）：每 30 秒检查一次到点任务并触发。
class ScheduledTaskService extends ChangeNotifier {
  ScheduledTaskService._();

  static final ScheduledTaskService instance = ScheduledTaskService._();

  /// 测试用：覆盖存储文件位置。
  static File? debugFile;

  /// 到点回调（由应用层注入，负责真正执行 AI 任务）。
  Future<void> Function(ScheduledTask task)? onFire;

  final List<ScheduledTask> _tasks = [];
  Timer? _timer;
  bool _loaded = false;
  Future<void>? _pendingPersist;

  List<ScheduledTask> get tasks => List.unmodifiable(_tasks);

  Future<File> _file() async {
    final override = debugFile;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/scheduled_tasks.json');
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
              .map((e) => ScheduledTask.fromJson(Map<String, dynamic>.from(e))),
        );
      }
    } catch (_) {}
  }

  /// 启动轮询（幂等）。
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      _tick(DateTime.now());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _tick(DateTime now) {
    for (final t in _tasks) {
      if (!t.enabled) continue;
      final last = t.lastRun;
      final fire = DateTime(now.year, now.month, now.day, t.hour, t.minute);
      if (last != null &&
          last.year == now.year &&
          last.month == now.month &&
          last.day == now.day &&
          !last.isBefore(fire)) {
        continue;
      }
      if (!fire.isAfter(now)) {
        if (t.weekdays.isEmpty || t.weekdays.contains(now.weekday)) {
          t.lastRun = now;
          final cb = onFire;
          if (cb != null) {
            unawaited(cb(t).catchError((Object e) {
              debugPrint('scheduled task failed: $e');
            }));
          }
        }
      }
    }
    if (_tasks.any((t) => t.lastRun != null)) {
      _pendingPersist = _persist();
    }
  }

  Future<ScheduledTask> add({
    required String conversationId,
    required String prompt,
    required int hour,
    required int minute,
    List<int> weekdays = const [],
  }) async {
    await _ensureLoaded();
    final task = ScheduledTask(
      id: 'sched_${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      prompt: prompt,
      hour: hour.clamp(0, 23),
      minute: minute.clamp(0, 59),
      weekdays: weekdays,
    );
    _tasks.add(task);
    await _persist();
    notifyListeners();
    return task;
  }

  Future<void> setEnabled(String id, bool v) async {
    for (final t in _tasks) {
      if (t.id == id) {
        t.enabled = v;
        break;
      }
    }
    await _persist();
    notifyListeners();
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

  Future<void> resetForTest() async {
    _timer?.cancel();
    _timer = null;
    _loaded = false;
    _tasks.clear();
    onFire = null;
    debugFile = null;
    await _pendingPersist;
    _pendingPersist = null;
  }

  /// 测试用：手动触发一次到点检查。
  void tickForTest(DateTime now) => _tick(now);
}
