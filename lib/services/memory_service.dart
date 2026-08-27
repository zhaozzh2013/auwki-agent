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
