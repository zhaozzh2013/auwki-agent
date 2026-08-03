import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

  /// 合并导出 chats.json + settings.json。
  static Future<Map<String, dynamic>> collectData() async {
    final dir = await getApplicationSupportDirectory();
    final chatsFile = File('${dir.path}/chats.json');
    final settingsFile = File('${dir.path}/settings.json');

    Map<String, dynamic> chats = {};
    Map<String, dynamic> settings = {};
    if (await chatsFile.exists()) {
      try {
        chats = jsonDecode(await chatsFile.readAsString())
            as Map<String, dynamic>;
      } catch (_) {}
    }
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
    await _prune(backups);
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
        .replaceAll('.json', '')
        .replaceAll('-', ':');
    return name;
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

  static Future<void> _prune(Directory backups) async {
    final files = await listBackups();
    for (final f in files.skip(_keepBackups)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
