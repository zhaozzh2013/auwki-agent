import 'dart:convert';
import 'dart:io';

/// 一轮对话期间发生的单个文件变化。
class FileChange {
  FileChange({
    required this.path,
    this.added,
    this.removed,
    this.deleted = false,
  });

  final String path;

  /// 新增行数；无法计算时为 null（例如二进制文件）。
  final int? added;

  /// 删除行数；无法计算时为 null。
  final int? removed;

  /// 文件是否在本轮被删除。
  final bool deleted;

  /// 动作提示：'created' 表示本轮调用过 writefile 成功创建，
  /// 'modified' 表示本轮调用过 replacefile 成功修改。
  final Set<String> actions = <String>{};
}

/// 工作目录文件快照，用于对比一轮对话前后的文件变化。
class WorkspaceSnapshot {
  WorkspaceSnapshot._(this._files);

  final Map<String, _SnapFile> _files;

  static const int _maxFileBytes = 2 * 1024 * 1024;
  static const int _maxContentBytes = 512 * 1024;
  static const int _maxEntries = 10000;

  static const Set<String> _skipDirs = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.idea',
    '.vscode',
    'target',
    'dist',
    'out',
    '__pycache__',
    '.venv',
    'venv',
    'coverage',
    '.codex',
    '.agents',
    '.vs',
    '.plugin_symlinks',
    'ephemeral',
    'CMakeFiles',
  };

  /// 归一化路径：统一为正斜杠、去掉开头的 ./，若在 root 下则转为相对路径。
  static String normalizePath(String path, {String? base}) {
    final root = (base ?? Directory.current.absolute.path).replaceAll('\\', '/');
    var p = path.trim().replaceAll('\\', '/');
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    if (p == root) return '';
    if (root.endsWith('/')) {
      if (p.startsWith(root)) p = p.substring(root.length);
    } else if (p.startsWith('$root/')) {
      p = p.substring(root.length + 1);
    }
    return p;
  }

  /// 用于 map 键的规范形式（Windows 下忽略大小写）。
  static String keyForPath(String path, {String? base}) {
    final normalized = normalizePath(path, base: base);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static Future<WorkspaceSnapshot> capture({String? rootPath}) async {
    final rootDir = Directory(rootPath ?? Directory.current.absolute.path);
    final root = rootDir.absolute.path;
    final files = <String, _SnapFile>{};
    await _walk(rootDir, root, files);
    return WorkspaceSnapshot._(files);
  }

  static Future<void> _walk(
    Directory dir,
    String root,
    Map<String, _SnapFile> out,
  ) async {
    if (out.length >= _maxEntries) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (out.length >= _maxEntries) return;
        try {
          final name = entity.path.split(Platform.pathSeparator).last;
          if (entity is Directory) {
            if (_skipDirs.contains(name)) continue;
            await _walk(entity, root, out);
          } else if (entity is File) {
            final rel = normalizePath(entity.path, base: root);
            if (rel.isEmpty) continue;
            final snap = await _snapFile(entity, rel);
            if (snap != null) {
              out[keyForPath(rel, base: root)] = snap;
            }
          }
        } catch (_) {
          // 单个条目失败不影响同目录下的其他条目。
        }
      }
    } catch (_) {
      // 整个目录无法列出时跳过该子树，不影响整体快照。
    }
  }

  static Future<_SnapFile?> _snapFile(File file, String rel) async {
    try {
      final stat = await file.stat();
      if (stat.size > _maxFileBytes) return null;
      final bytes = await file.readAsBytes();
      if (bytes.contains(0)) {
        // 二进制文件：只记录大小，用于判断是否被修改。
        return _SnapFile(displayPath: rel, size: bytes.length);
      }
      final text = utf8Decode(bytes);
      // 行数按常见约定：以换行结尾不额外计数空尾行。
      final lineCount = text.isEmpty
          ? 0
          : '\n'.allMatches(text).length +
                (text.endsWith('\n') ? 0 : 1);
      return _SnapFile(
        displayPath: rel,
        size: bytes.length,
        lineCount: lineCount,
        content: bytes.length <= _maxContentBytes ? text : null,
      );
    } catch (_) {
      return null;
    }
  }

  static String utf8Decode(List<int> bytes) =>
      const Utf8Decoder(allowMalformed: true).convert(bytes);

  /// 与一份“更晚”的快照对比，返回期间发生的文件变化（按路径排序）。
  /// 调用方式：`earlier.diff(later)`。
  List<FileChange> diff(WorkspaceSnapshot later) {
    final changes = <FileChange>[];
    final allKeys = {..._files.keys, ...later._files.keys}.toList()..sort();
    for (final key in allKeys) {
      final oldFile = _files[key];
      final newFile = later._files[key];
      if (oldFile == null && newFile != null) {
        changes.add(
          FileChange(
            path: newFile.displayPath,
            added: newFile.lineCount,
            removed: 0,
          ),
        );
      } else if (oldFile != null && newFile == null) {
        changes.add(
          FileChange(path: oldFile.displayPath, deleted: true),
        );
      } else if (oldFile != null &&
          newFile != null &&
          (oldFile.size != newFile.size ||
              oldFile.lineCount != newFile.lineCount ||
              oldFile.content != newFile.content)) {
        final stats = _diffStats(oldFile, newFile);
        changes.add(
          FileChange(
            path: newFile.displayPath,
            added: stats.$1,
            removed: stats.$2,
          ),
        );
      }
    }
    return changes;
  }

  static (int?, int?) _diffStats(_SnapFile oldFile, _SnapFile newFile) {
    if (oldFile.content != null && newFile.content != null) {
      return _lineDiff(oldFile.content!, newFile.content!);
    }
    if (oldFile.lineCount != null && newFile.lineCount != null) {
      final delta = newFile.lineCount! - oldFile.lineCount!;
      return (delta > 0 ? delta : 0, delta < 0 ? -delta : 0);
    }
    return (null, null);
  }

  /// 基于 LCS 的简单行级 diff，返回 (新增行, 删除行)。
  static (int, int) _lineDiff(String oldText, String newText) {
    final a = oldText.split('\n');
    final b = newText.split('\n');
    if (a.length > 1500 || b.length > 1500) {
      final delta = b.length - a.length;
      return (delta > 0 ? delta : 0, delta < 0 ? -delta : 0);
    }
    final m = a.length;
    final n = b.length;
    var prev = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0);
      for (var j = 1; j <= n; j++) {
        cur[j] = a[i - 1] == b[j - 1]
            ? prev[j - 1] + 1
            : (prev[j] >= cur[j - 1] ? prev[j] : cur[j - 1]);
      }
      prev = cur;
    }
    final lcs = prev[n];
    return (b.length - lcs, a.length - lcs);
  }
}

class _SnapFile {
  _SnapFile({
    required this.displayPath,
    required this.size,
    this.lineCount,
    this.content,
  });

  final String displayPath;
  final int size;
  final int? lineCount;
  final String? content;
}
