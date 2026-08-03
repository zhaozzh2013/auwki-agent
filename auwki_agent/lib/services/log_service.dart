import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 稳定性兜底：捕获全局异常并写入本地日志文件。
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
      _write('FLUTTER', details.exceptionAsString(), details.stack.toString());
      FlutterError.presentError(details);
    };

    PlatformDispatcher.instance.onError = (error, stack) {
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
