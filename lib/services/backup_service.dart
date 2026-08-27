import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'chat_database.dart';

/// 数据安全感：自动/手动备份聊天记录与设置。
class BackupService {
  BackupService._();

  static const int _keepBackups = 20;
  static bool _initialBackupScheduled = false;

  static Future<Directory> _backupDir() async {
    final dir = await getApplicationSupportDirectory();
    final backups = Directory('${dir.path}/backups');
    await backups.create(recursive: true);
    return backups;
  }

  /// 合并导出 chats + settings。
  /// 对话数据优先从 ChatDatabase 导出（SQLite 或回退模式），
  /// 未打开时回退到读取 chats.json 文件。
  static Future<Map<String, dynamic>> collectData() async {
    final dir = await getApplicationSupportDirectory();
    final settingsFile = File('${dir.path}/settings.json');

    Map<String, dynamic> chats = {};
    final db = ChatDatabase.instance;
    if (db.isOpen) {
      chats = db.exportJson();
    } else {
      final chatsFile = File('${dir.path}/chats.json');
      if (await chatsFile.exists()) {
        try {
          chats = jsonDecode(await chatsFile.readAsString())
              as Map<String, dynamic>;
        } catch (_) {}
      }
    }

    Map<String, dynamic> settings = {};
    if (await settingsFile.exists()) {
      try {
        settings = jsonDecode(await settingsFile.readAsString())
            as Map<String, dynamic>;
      } catch (_) {}
    }
    return {
      'exportedAt': DateTime.now().toIso8601String(),
      'app': 'AUWKI Agent',
      'chats': chats,
      'settings': settings,
    };
  }

  /// 创建一份带时间戳的备份，返回备份文件路径。
  static Future<String> createBackup() async {
    final data = await collectData();
    final backups = await _backupDir();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File('${backups.path}/backup-$stamp.json');
    await file.writeAsString(jsonEncode(data));
    await pruneBackups(keep: _keepBackups);
    return file.path;
  }

  static Future<List<File>> listBackups() async {
    final backups = await _backupDir();
    final files = backups
        .listSync(followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static Future<String?> latestBackupTime() async {
    final backups = await listBackups();
    if (backups.isEmpty) return null;
    final name = backups.first.path
        .split(Platform.pathSeparator)
        .last
        .replaceAll('backup-', '')
        .replaceAll('.json', '');
    // 文件名里时间部分的 ':' 被替换成了 '-'，这里只还原时间部分，
    // 避免把日期里的 '-' 也一起替换导致显示错乱。
    final parts = name.split('T');
    final time = parts.length > 1 ? parts[1].replaceAll('-', ':') : '';
    return '${parts[0]} $time'.trim();
  }

  /// 导出到用户选择的位置（完整 JSON）。
  static Future<void> exportTo(String path) async {
    final data = await collectData();
    final file = File(path);
    await file.writeAsString(jsonEncode(data));
  }

  /// 应用启动后延迟执行一次初始备份（避免启动卡顿）。
  static void scheduleInitialBackup() {
    if (_initialBackupScheduled) return;
    _initialBackupScheduled = true;
    Future<void>.delayed(const Duration(seconds: 5), () async {
      try {
        await createBackup();
      } catch (_) {}
    });
  }

  /// 清理旧备份（保留最近 keep 份），返回删除数量（F07）。
  static Future<int> pruneBackups({int keep = _keepBackups}) async {
    final files = await listBackups();
    var removed = 0;
    for (final f in files.skip(keep)) {
      try {
        await f.delete();
        removed++;
      } catch (_) {}
    }
    return removed;
  }
}
