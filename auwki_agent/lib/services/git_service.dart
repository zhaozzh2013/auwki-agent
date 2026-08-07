import 'dart:convert';
import 'dart:io';

/// git 仓库中单个文件的状态（来自 `git status --porcelain`）。
class GitFileStatus {
  const GitFileStatus({
    required this.path,
    required this.indexStatus,
    required this.worktreeStatus,
  });

  final String path;

  /// 暂存区状态列（X）。
  final String indexStatus;

  /// 工作区状态列（Y）。
  final String worktreeStatus;

  bool get untracked => indexStatus == '?' || worktreeStatus == '?';

  bool get staged => indexStatus != ' ' && indexStatus != '?' && indexStatus != '';

  bool get deleted =>
      indexStatus == 'D' ||
      worktreeStatus == 'D' ||
      indexStatus == 'R' ||
      worktreeStatus == 'R';

  String get label =>
      (indexStatus == ' ' ? '' : indexStatus) +
      (worktreeStatus == ' ' ? '' : worktreeStatus);
}

/// 一次 git 提交的摘要信息。
class GitCommitInfo {
  const GitCommitInfo({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.date,
    required this.message,
  });

  final String hash;
  final String shortHash;
  final String author;
  final String date;
  final String message;
}

/// `git status` 的整体结果。
class GitStatus {
  const GitStatus({
    required this.branch,
    required this.files,
    this.aheadBehind = '',
  });

  final String? branch;
  final List<GitFileStatus> files;
  final String aheadBehind;
}

/// 在 AUWKI 工作目录上执行只读/受控 git 操作。
///
/// 只提供安全操作：暂存、提交、放弃工作区更改、revert 提交；
/// 不使用 `reset --hard` 等破坏性命令。
class GitService {
  static final Map<String, String?> _repoRootCache = {};

  /// 仅供测试：清除仓库根缓存（应用运行时不需要调用）。
  static void resetRepoRootCache() => _repoRootCache.clear();

  static String _pathKey(String? path) {
    final p = path?.trim();
    return (p == null || p.isEmpty) ? Directory.current.path : p;
  }

  static Future<String?> repoRoot({String? path}) async {
    final key = _pathKey(path);
    if (_repoRootCache.containsKey(key)) return _repoRootCache[key];
    final r = await _run(
      ['rev-parse', '--show-toplevel'],
      workingDirectory: path,
    );
    if (r.exitCode != 0) return null;
    final root = (r.stdout as String).trim();
    if (root.isEmpty) return null;
    _repoRootCache[key] = root;
    return root;
  }

  /// 系统是否安装了可用的 git。
  static Future<bool> gitAvailable() async {
    final r = await _run(['--version']);
    return r.exitCode == 0;
  }

  static Future<ProcessResult> _run(
    List<String> args, {
    String? workingDirectory,
  }) async {
    try {
      return await Process.run(
        'git',
        ['-c', 'core.quotepath=false', ...args],
        workingDirectory: workingDirectory,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } catch (e) {
      return ProcessResult(-1, 127, '', '$e');
    }
  }

  static Future<GitStatus> status({String? path}) async {
    final r = await _run(
      ['status', '--porcelain=v1', '-b'],
      workingDirectory: path,
    );
    if (r.exitCode != 0) {
      throw GitServiceException(r.stderr.trim().isEmpty
          ? 'git unavailable'
          : r.stderr.trim());
    }
    final lines = (r.stdout as String)
        .split('\n')
        .map((String s) => s.trimRight())
        .where((String s) => s.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const GitStatus(branch: null, files: []);

    String? branch;
    var aheadBehind = '';
    final files = <GitFileStatus>[];
    for (final line in lines) {
      if (line.startsWith('## ')) {
        final head = line.substring(3);
        final sep = head.indexOf('...');
        branch = sep < 0 ? head : head.substring(0, sep);
        final ab = sep < 0 ? '' : head.substring(sep + 3);
        if (ab.isNotEmpty) aheadBehind = ab;
        continue;
      }
      if (line.length < 4) continue;
      final x = line[0];
      final y = line[1];
      var path = line.substring(3);
      // 重命名/复制的显示格式：old -> new，只展示新路径。
      final arrow = path.indexOf(' -> ');
      if (arrow >= 0) path = path.substring(arrow + 4);
      files.add(
        GitFileStatus(
          path: path,
          indexStatus: x,
          worktreeStatus: y,
        ),
      );
    }
    return GitStatus(branch: branch, files: files, aheadBehind: aheadBehind);
  }

  static Future<List<GitCommitInfo>> log({
    int count = 15,
    String? path,
  }) async {
    final r = await _run(
      [
        'log',
        '-n',
        '$count',
        '--pretty=format:%H|%h|%an|%ad|%s',
        '--date=format:%Y-%m-%d %H:%M',
      ],
      workingDirectory: path,
    );
    if (r.exitCode != 0) {
      throw GitServiceException(r.stderr.trim());
    }
    final commits = <GitCommitInfo>[];
    for (final line in (r.stdout as String).split('\n')) {
      final parts = line.split('|');
      if (parts.length < 5) continue;
      commits.add(
        GitCommitInfo(
          hash: parts[0],
          shortHash: parts[1],
          author: parts[2],
          date: parts[3],
          message: parts.sublist(4).join('|'),
        ),
      );
    }
    return commits;
  }

  static Future<String> stage(List<String> paths, {String? path}) async {
    final r = await _run(['add', '--', ...paths], workingDirectory: path);
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  static Future<String> stageAll({String? path}) async {
    final r = await _run(['add', '-A'], workingDirectory: path);
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  static Future<String> unstage(List<String> paths, {String? path}) async {
    final r = await _run(
      ['restore', '--staged', '--', ...paths],
      workingDirectory: path,
    );
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  static Future<String> commit(String message, {String? path}) async {
    final r = await _run(['commit', '-m', message], workingDirectory: path);
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  /// 放弃指定文件的工作区更改（保留暂存区）。
  static Future<String> discard(List<String> paths, {String? path}) async {
    final r = await _run(
      ['restore', '--', ...paths],
      workingDirectory: path,
    );
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  /// 放弃所有工作区更改（保留暂存区与历史）。
  static Future<String> discardAll({String? path}) async {
    final r = await _run(['restore', '--', '.'], workingDirectory: path);
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  /// 删除未跟踪文件（谨慎使用，仅限用户明确选择的路径）。
  static Future<String> removeUntracked(
    List<String> paths, {
    String? path,
  }) async {
    final r = await _run(
      ['clean', '-fd', '--', ...paths],
      workingDirectory: path,
    );
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  /// 用一次新提交回滚指定提交（安全，不改写历史）。
  static Future<String> revertCommit(String hash, {String? path}) async {
    final r = await _run(
      ['revert', '--no-edit', hash],
      workingDirectory: path,
    );
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  /// 文件相对工作区的 diff 统计（含暂存区与未暂存更改）。
  static Future<String> diffStat(String file, {String? path}) async {
    final r = await _run(
      ['diff', 'HEAD', '--stat', '--', file],
      workingDirectory: path,
    );
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    return r.stdout.trim();
  }

  /// 初始化仓库（目录不存在会自动创建）。
  static Future<String> initRepo(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final r = await _run(['init'], workingDirectory: path);
    if (r.exitCode != 0) throw GitServiceException(r.stderr.trim());
    _repoRootCache.remove(_pathKey(path));
    return r.stdout.trim();
  }
}

class GitServiceException implements Exception {
  GitServiceException(this.message);
  final String message;

  @override
  String toString() => message;
}
