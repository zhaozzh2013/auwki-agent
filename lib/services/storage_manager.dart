import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'backup_service.dart';
import 'log_service.dart';
import 'workspace_manager.dart';

/// 存储占用统计与清理（F07）。
class StorageUsage {
  StorageUsage({
    required this.appSupportBytes,
    required this.chatsDbBytes,
    required this.backupsBytes,
    required this.backupCount,
    required this.logsBytes,
    required this.workspacesBytes,
  });

  /// 数据目录总占用。
  final int appSupportBytes;

  /// chats.db（含 WAL/SHM）。
  final int chatsDbBytes;

  final int backupsBytes;
  final int backupCount;
  final int logsBytes;

  /// 对话工作空间（conversations/ 目录）。
  final int workspacesBytes;

  String get fmtTotal => _fmt(appSupportBytes);

  static String _fmt(int n) {
    if (n >= 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (n >= 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (n >= 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '$n B';
  }
}

class StorageManager {
  StorageManager._();

  static Future<StorageUsage> collect() async {
    final dir = await getApplicationSupportDirectory();
    final dbFile = File('${dir.path}/chats.db');
    var dbBytes = 0;
    for (final f in [
      dbFile,
      File('${dir.path}/chats.db-wal'),
      File('${dir.path}/chats.db-shm'),
    ]) {
      dbBytes += await _size(f);
    }
    final backups = Directory('${dir.path}/backups');
    final logs = Directory('${dir.path}/logs');
    final base = WorkspaceManager.appBaseDirectory;
    final workspaces = Directory('$base/conversations');
    var backupCount = 0;
    try {
      if (await backups.exists()) {
        backupCount = backups
            .listSync(followLinks: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .length;
      }
    } catch (_) {}
    return StorageUsage(
      appSupportBytes: await _dirSize(dir),
      chatsDbBytes: dbBytes,
      backupsBytes: await _dirSize(backups),
      backupCount: backupCount,
      logsBytes: await _dirSize(logs),
      workspacesBytes: await _dirSize(workspaces),
    );
  }

  /// 清理旧备份（保留最近 keep 份）。
  static Future<int> pruneBackups({int keep = 20}) =>
      BackupService.pruneBackups(keep: keep);

  /// 清空日志文件，返回清除的字节数。
  static Future<int> clearLogs() async {
    final path = await LogService.logFilePath();
    final size = path == null ? 0 : await _size(File(path));
    await LogService.clear();
    return size;
  }

  /// 删除空的工作空间目录（对话已删但目录残留）。
  static Future<int> removeEmptyWorkspaces() async {
    final base = WorkspaceManager.appBaseDirectory;
    final conversations = Directory('$base/conversations');
    var removed = 0;
    try {
      if (!await conversations.exists()) return 0;
      await for (final date in conversations.list(followLinks: false)) {
        if (date is! Directory) continue;
        await for (final hash in date.list(followLinks: false)) {
          if (hash is! Directory) continue;
          var empty = true;
          await for (final _ in hash.list(followLinks: false)) {
            empty = false;
            break;
          }
          if (empty) {
            try {
              await hash.delete(recursive: true);
              removed++;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return removed;
  }

  static Future<String> appSupportPath() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  static Future<int> _size(File f) async {
    try {
      if (await f.exists()) return await f.length();
    } catch (_) {}
    return 0;
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
