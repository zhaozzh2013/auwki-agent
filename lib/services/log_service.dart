import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 稳定性兜底：捕获全局异常并写入本地日志文件；
/// 提供崩溃落盘（E03）、日志尾部读取（E02）与启动时序统计（E05）。
class LogService {
  LogService._();

  static const int _maxLogBytes = 1024 * 1024;
  static const int _maxRingLines = 200;

  static final List<String> _ring = [];
  static File? _file;
  static bool _ready = false;
  static bool _installed = false;

  static bool get ready => _ready;

  /// 最近若干条日志（内存环形缓冲，供界面展示）。
  static List<String> get recent => List.unmodifiable(_ring);

  static Future<void> init() async {
    if (_installed) return;
    _installed = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final logs = Directory('${dir.path}/logs');
      await logs.create(recursive: true);
      _file = File('${logs.path}/app.log');
      _ready = true;
    } catch (_) {
      _file = null;
      _ready = false;
    }

    FlutterError.onError = (details) {
      _writeCrashDump('FLUTTER', details.exceptionAsString(), details.stack.toString());
      _write('FLUTTER', details.exceptionAsString(), details.stack.toString());
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      _writeCrashDump('ASYNC', error.toString(), stack.toString());
      _write('ASYNC', error.toString(), stack.toString());
      return true;
    };

    _write('INFO', 'AUWKI Agent started (${DateTime.now().toIso8601String()})');
  }

  static void log(String message) {
    _write('INFO', message);
  }

  static void _write(String level, String message, [String? stack]) {
    final line = StringBuffer()
      ..write('[${DateTime.now().toIso8601String()}] [$level] ')
      ..write(message);
    if (stack != null && stack.isNotEmpty) {
      line.write('\n$stack');
    }
    _ring.add(line.toString());
    if (_ring.length > _maxRingLines) _ring.removeAt(0);

    final file = _file;
    if (file == null) return;
    unawaited(_append(file, line.toString()));
  }

  static Future<void> _append(File file, String line) async {
    try {
      if (await file.exists() && await file.length() > _maxLogBytes) {
        // 日志过大时保留后半段，避免无限增长。
        final text = await file.readAsString();
        final keep = text.substring(text.length ~/ 2);
        await file.writeAsString('$keep\n');
      }
      await file.writeAsString('$line\n', mode: FileMode.append);
    } catch (_) {}
  }

  /// 崩溃落盘（E03）：把最近一次崩溃写成独立文件，便于打包诊断。
  static void _writeCrashDump(String kind, String error, String stack) {
    final file = _file;
    if (file == null) return;
    unawaited(() async {
      try {
        final dump = File('${file.parent.path}/crash-last.json');
        await dump.writeAsString(
          jsonEncode({
            'time': DateTime.now().toIso8601String(),
            'kind': kind,
            'error': error,
            'stack': stack,
            'recentLogs': _ring.takeLast(40).toList(),
          }),
          mode: FileMode.write,
        );
      } catch (_) {}
    }());
  }

  /// 读取日志文件末尾若干行（E02）。
  static Future<List<String>> tail({int lines = 500}) async {
    final file = _file;
    if (file == null || !await file.exists()) return const [];
    try {
      final text = await file.readAsString();
      final all = text.split('\n').where((l) => l.isNotEmpty).toList();
      return all.length <= lines ? all : all.sublist(all.length - lines);
    } catch (_) {
      return const [];
    }
  }

  /// 清空日志文件（F07 存储管理）。
  static Future<void> clear() async {
    final file = _file;
    if (file == null) return;
    try {
      if (await file.exists()) await file.writeAsString('');
    } catch (_) {}
  }

  /// 把日志导出到指定路径（E02 日志查看器）。
  static Future<void> exportTo(String path) async {
    final lines = await tail(lines: 5000);
    await File(path).writeAsString('${lines.join('\n')}\n');
  }

  // ─────────────── E05 启动时序 ───────────────

  static final Stopwatch _startupWatch = Stopwatch()..start();
  static final List<String> _milestones = [];

  /// 记录一个启动里程碑（毫秒耗时），并写入日志。
  static void milestone(String name) {
    final ms = _startupWatch.elapsedMilliseconds;
    _milestones.add('$name: ${ms}ms');
    _write('TIMING', 'startup milestone $name at ${ms}ms');
  }

  /// 启动里程碑列表（诊断用）。
  static List<String> get startupMilestones => List.unmodifiable(_milestones);

  /// 日志文件路径（未就绪时返回 null）。
  static Future<String?> logFilePath() async {
    if (_file != null) return _file!.path;
    try {
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/logs/app.log';
    } catch (_) {
      return null;
    }
  }
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
