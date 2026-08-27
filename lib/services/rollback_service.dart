import 'dart:io';

import 'round_changes.dart';

/// 文件回滚（A07）：保存本轮开始前的文本快照，一键恢复被改动文件。
class RollbackService {
  RollbackService._();

  static final RollbackService instance = RollbackService._();

  /// convId -> (文件绝对路径 -> 原始内容)
  final Map<String, Map<String, String>> _snapshots = {};
  final Map<String, List<String>> _createdFiles = {};

  /// 记录本轮开始前的文本文件内容。
  void capture(
    String convId,
    WorkspaceSnapshot snapshot, {
    String? baseDir,
  }) {
    final files = <String, String>{};
    for (final e in snapshot.textFiles().entries) {
      final base = (baseDir ?? Directory.current.path).replaceAll('\\', '/');
      final key = e.key.isEmpty ? base : '$base/${e.key.replaceAll('\\', '/')}';
      files[key] = e.value;
    }
    if (files.isEmpty) {
      _snapshots.remove(convId);
    } else {
      _snapshots[convId] = files;
    }
  }

  bool hasSnapshot(String convId) => _snapshots.containsKey(convId);

  /// 记录本轮由 AI 创建的新文件（供回滚时删除）。
  void recordCreated(
    String convId,
    String? baseDir,
    Map<String, Set<String>> fileActions,
  ) {
    if (baseDir == null || baseDir.trim().isEmpty) return;
    final paths = <String>[];
    fileActions.forEach((key, actions) {
      if (actions.contains('created')) {
        paths.add('${baseDir.replaceAll('\\', '/')}/${key.replaceAll('\\', '/')}');
      }
    });
    if (paths.isNotEmpty) {
      _createdFiles[convId] = [
        ...?_createdFiles[convId],
        ...paths,
      ];
    }
  }

  /// 恢复指定会话本轮被改动/新增的文本文件，返回恢复数量。
  Future<int> rollback(String convId) async {
    final files = _snapshots.remove(convId);
    final created = _createdFiles.remove(convId) ?? const <String>[];
    var restored = 0;
    for (final path in created) {
      try {
        final f = File(path);
        if (await f.exists()) {
          await f.delete();
          restored++;
        }
      } catch (_) {}
    }
    if (files == null) return restored;
    for (final e in files.entries) {
      try {
        final f = File(e.key);
        // 快照里的文件一律恢复原内容（含空文件）；本轮新建文件由 created 列表删除。
        await f.parent.create(recursive: true);
        await f.writeAsString(e.value);
        restored++;
      } catch (_) {}
    }
    return restored;
  }

  void clear(String convId) {
    _snapshots.remove(convId);
    _createdFiles.remove(convId);
  }
}
