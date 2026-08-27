import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 一条记忆（A17）。
class MemoryEntry {
  MemoryEntry({
    required this.id,
    required this.text,
    this.kind = 'fact',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String text;
  final String kind;
  final DateTime createdAt;

  factory MemoryEntry.fromJson(Map<String, dynamic> m) => MemoryEntry(
    id: (m['id'] ?? '').toString(),
    text: (m['text'] ?? '').toString(),
    kind: (m['kind'] ?? 'fact').toString(),
    createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'kind': kind,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// 记忆系统（A17）：持久化记忆条目，注入到系统提示词。
///
/// kind 约定：
/// - `fact`      手动 /remember 的通用事实
/// - `preference`自动提取的用户偏好
/// - `project`   自动提取的项目事实（技术栈/架构/结构等）
/// - `code`      /note-code 记录的代码结构笔记
class MemoryService {
  MemoryService._();

  static final MemoryService instance = MemoryService._();

  /// 测试用：覆盖存储文件位置。
  static File? debugFile;

  final List<MemoryEntry> _entries = [];
  bool _loaded = false;

  Future<File> _file() async {
    final override = debugFile;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/memory.json');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final list = jsonDecode(await f.readAsString()) as List;
        _entries.addAll(
          list.whereType<Map>().map(
            (e) => MemoryEntry.fromJson(Map<String, dynamic>.from(e)),
          ),
        );
      }
    } catch (_) {}
  }

  Future<List<MemoryEntry>> list() async {
    await _ensureLoaded();
    return List.unmodifiable(_entries);
  }

  Future<MemoryEntry> add(String text, {String kind = 'fact'}) async {
    await _ensureLoaded();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return MemoryEntry(id: 'mem_empty', text: '', kind: kind);
    }
    // 去重：同 kind+文本 视为同一条记忆，刷新时间以保持“最新优先”。
    for (final e in _entries) {
      if (e.kind == kind && e.text == trimmed) {
        final renewed = MemoryEntry(
          id: e.id,
          text: trimmed,
          kind: kind,
        );
        _entries
          ..remove(e)
          ..add(renewed);
        await _persist();
        return renewed;
      }
    }
    final entry = MemoryEntry(
      id: 'mem_${DateTime.now().microsecondsSinceEpoch}',
      text: trimmed,
      kind: kind,
    );
    _entries.add(entry);
    await _persist();
    return entry;
  }

  Future<void> remove(String id) async {
    await _ensureLoaded();
    _entries.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  /// 生成注入系统提示词的记忆片段（限制条数与字符数）。
  Future<String> injectPromptText({int limit = 8, int maxChars = 800}) async {
    await _ensureLoaded();
    if (_entries.isEmpty) return '';
    final buf = StringBuffer('## Memory\n');
    var used = 0;
    for (final e in _entries.reversed) {
      final line = '- ${e.kind}: ${e.text}';
      if (used + line.length > maxChars) break;
      buf.writeln(line);
      used += line.length;
      limit--;
      if (limit <= 0) break;
    }
    return buf.toString().trim();
  }

  /// 轻量自动提取用户偏好（保守启发式，避免误存）。
  String? maybeExtractPreference(String text) {
    final markers = const [
      '我喜欢',
      '我偏好',
      '我总是',
      '我一般',
      '我习惯',
      '我不喜欢',
      '请不要',
      '不要',
      '必须',
      'I prefer',
      'I like',
      'I always',
      'I usually',
      'please always',
      'never',
    ];
    final sentences = text
        .split(RegExp(r'[\n。！？!?]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty && s.length <= 120)
        .toList();
    for (final sentence in sentences) {
      for (final marker in markers) {
        if (sentence.toLowerCase().contains(marker.toLowerCase())) {
          return sentence;
        }
      }
    }
    return null;
  }

  /// 轻量自动提取项目事实（D：项目长期记忆）。
  ///
  /// 保守启发式：仅当句子包含项目类强信号词（>=1 个强词或 >=2 个
  /// 普通词）时提取，且明显属于用户偏好的句子（由
  /// [maybeExtractPreference] 判定）不重复提取。
  String? maybeExtractProjectFact(String text) {
    if (text.trim().isEmpty) return null;
    final strong = const [
      '项目',
      '架构',
      '技术栈',
      '代码库',
      '仓库',
      '依赖',
      '数据库',
      '框架',
      '后端',
      '前端',
      '部署',
      'project',
      'repo',
      'repository',
      'architecture',
      'tech stack',
      'codebase',
      'dependency',
      'framework',
      'database',
      'backend',
      'frontend',
      'deploy',
      'built with',
      'running on',
      'stack:',
    ];
    final weak = const [
      '使用',
      '版本',
      '环境',
      '目录',
      '模块',
      '接口',
      '构建',
      '迁移',
      '配置',
      'use',
      'uses',
      'version',
      'env',
      'module',
      'migrate',
      'config',
      'api',
      'sdk',
      'flutter',
      'dart',
      'python',
      'node',
      'rust',
      'go',
      'typescript',
      'sqlite',
      'postgres',
      'mysql',
      'redis',
      'docker',
      'linux',
      'windows',
      'macos',
    ];
    final sentences = text
        .split(RegExp(r'[\n。！？!?；;]'))
        .map((s) => s.trim())
        .where((s) => s.length >= 20 && s.length <= 160)
        .toList();
    for (final sentence in sentences) {
      final lower = sentence.toLowerCase();
      // 偏好句不重复提取
      if (maybeExtractPreference(sentence) != null) continue;
      var strongHits = 0;
      var weakHits = 0;
      for (final m in strong) {
        if (lower.contains(m)) strongHits++;
      }
      for (final m in weak) {
        if (lower.contains(m)) weakHits++;
      }
      if (strongHits >= 1 || weakHits >= 2) {
        return sentence;
      }
    }
    return null;
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode([for (final e in _entries) e.toJson()]),
      );
    } catch (_) {}
  }

  /// 测试用：重置内存状态。
  Future<void> resetForTest() async {
    _loaded = false;
    _entries.clear();
    debugFile = null;
  }
}
