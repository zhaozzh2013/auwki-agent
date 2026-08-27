import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_info.dart';
import 'chat_database.dart';
import 'log_service.dart';

/// 崩溃/问题诊断包（E03）：收集应用信息、存储状态、配置快照与最近日志。
class DiagnosticsService {
  DiagnosticsService._();

  static Future<Map<String, dynamic>> collect({
    required Map<String, dynamic> settingsExport,
  }) async {
    final dir = await getApplicationSupportDirectory();
    return {
      'generatedAt': DateTime.now().toIso8601String(),
      'app': AppInfo.title,
      'version': AppInfo.version,
      'platform': {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'dart': Platform.version,
      },
      'storage': {
        'usingSqlite': ChatDatabase.instance.usingSqlite,
        'usingLegacy': ChatDatabase.instance.usingLegacy,
        'appSupportBytes': await _dirSize(dir),
      },
      'startupMilestones': LogService.startupMilestones,
      'settings': settingsExport,
      'recentLogs': LogService.recent.takeLast(100).toList(),
    };
  }

  static Future<void> saveTo(String path, Map<String, dynamic> data) async {
    await File(path).writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  static Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }
}

extension _TakeLast<T> on List<T> {
  List<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
