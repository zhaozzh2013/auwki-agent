import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class _CacheEntry {
  _CacheEntry({required this.at, required this.result});

  final DateTime at;
  final String result;
}

/// 工具结果缓存（A18）：相同 websearch/webfetch 短时缓存，避免重复请求。
class ToolCache {
  ToolCache._();

  static final ToolCache instance = ToolCache._();

  /// 测试用：覆盖缓存文件位置。
  static File? debugFile;

  final Map<String, _CacheEntry> _entries = {};
  bool _loaded = false;

  Future<File> _file() async {
    final override = debugFile;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/tool_cache.json');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        m.forEach((k, v) {
          if (v is Map) {
            _entries[k] = _CacheEntry(
              at:
                  DateTime.tryParse((v['at'] ?? '').toString()) ??
                  DateTime.now(),
              result: (v['result'] ?? '').toString(),
            );
          }
        });
      }
    } catch (_) {}
  }

  String _key(String tool, String args) => '$tool\u0000$args';

  Future<String?> get(String tool, String args, {int ttlSeconds = 600}) async {
    await _ensureLoaded();
    if (ttlSeconds <= 0) return null;
    final e = _entries[_key(tool, args)];
    if (e == null) return null;
    if (DateTime.now().difference(e.at).inSeconds > ttlSeconds) {
      _entries.remove(_key(tool, args));
      await _persist();
      return null;
    }
    return e.result;
  }

  Future<void> set(String tool, String args, String result) async {
    await _ensureLoaded();
    _entries[_key(tool, args)] = _CacheEntry(
      at: DateTime.now(),
      result: result,
    );
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  /// 测试用：重置内存状态并清空缓存。
  Future<void> resetForTest() async {
    _loaded = false;
    _entries.clear();
    debugFile = null;
  }

  Future<void> _persist() async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        jsonEncode({
          for (final e in _entries.entries)
            e.key: {
              'at': e.value.at.toIso8601String(),
              'result': e.value.result,
            },
        }),
      );
    } catch (_) {}
  }
}
