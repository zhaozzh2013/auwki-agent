import 'dart:io';

import 'package:flutter/foundation.dart';

/// 对话工作空间目录的解析、默认路径与创建。
///
/// 默认结构：`<软件所在目录>/conversations/<对话日期>/<对话哈希>/workspace`
/// 每个对话独立一个目录，AI 的文件操作、命令和 Git 都基于该目录。
class WorkspaceManager {
  WorkspaceManager._();

  /// 各平台默认的工作空间根目录：
  /// - Windows 发布版：exe 所在目录可写时保持绿色版便携特性；
  ///   安装在 Program Files 等只读位置时回退到 `~/\.auwki`
  /// - macOS：`~/Documents/AUWKI`（避免写入只读的 .app 包内）
  /// - Linux：`~/.auwki`
  /// - 开发模式：当前工作目录
  static String get appBaseDirectory {
    if (!kReleaseMode) return Directory.current.absolute.path;
    if (Platform.isWindows) {
      try {
        final exeDir = File(Platform.resolvedExecutable).parent.absolute.path;
        if (_isWritable(exeDir)) return exeDir;
      } catch (_) {
        // 落到下面的用户目录回退
      }
      final profile = Platform.environment['USERPROFILE']?.trim();
      if (profile != null && profile.isNotEmpty) return '$profile/.auwki';
      return Directory.current.absolute.path;
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME']?.trim();
      if (home != null && home.isNotEmpty) return '$home/Documents/AUWKI';
      return Directory.current.absolute.path;
    }
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) return '$home/.auwki';
    return Directory.current.absolute.path;
  }

  /// 目录是否可写：尝试创建并删除一个探测文件。
  static bool _isWritable(String dir) {
    try {
      final probe = File('$dir/.auwki_write_probe');
      probe.writeAsStringSync('x');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
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
