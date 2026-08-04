import 'dart:io';

import 'package:flutter/foundation.dart';

/// 对话工作空间目录的解析、默认路径与创建。
///
/// 默认结构：`<软件所在目录>/conversations/<对话日期>/<对话哈希>/workspace`
/// 每个对话独立一个目录，AI 的文件操作、命令和 Git 都基于该目录。
class WorkspaceManager {
  WorkspaceManager._();

  /// “软件所在目录”：发布版取 exe 所在目录，开发版取当前工作目录。
  static String get appBaseDirectory {
    if (kReleaseMode) {
      try {
        return File(Platform.resolvedExecutable).parent.absolute.path;
      } catch (_) {
        return Directory.current.absolute.path;
      }
    }
    return Directory.current.absolute.path;
  }

  /// 根据对话 ID 生成默认工作空间路径（统一使用正斜杠）。
  static String defaultWorkspacePath(String conversationId) {
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final hash = shortHash(conversationId);
    return normalize(
      '$appBaseDirectory/conversations/$date/$hash/workspace',
    );
  }

  /// 简易稳定哈希（FNV-1a），用于生成可读的短目录名。
  static String shortHash(String input) {
    var h = 0x811c9dc5;
    for (final c in input.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  static String normalize(String path) => path.replaceAll('\\', '/');

  /// 确保目录存在（递归创建）。
  static Future<void> ensure(String path) async {
    await Directory(path).create(recursive: true);
  }
}
