import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// 对话数据的 SQLite 存储（F01）。
///
/// 设计：每个对话一行，messages 以 JSON 列存储——复用现有模型序列化，
/// 同时获得增量写入（只更新变更的行）与大对话下的读写性能。
/// 若 SQLite 原生库不可用（缺少 sqlite3.dll 等），自动回退到
/// 旧的 chats.json 整文件模式，保证功能不降级（_legacyMode）。
///
/// 首次从 SQLite 打开且库为空时，自动迁移旧的 chats.json
/// （旧文件改名保留为 chats.json.migrated.bak）。
class ChatDatabase {
  ChatDatabase._();

  static final ChatDatabase instance = ChatDatabase._();

  /// 当前存储结构版本（E06 迁移框架）。
  static const int schemaVersion = 2;

  Database? _db;
  final List<Database> _connections = [];
  File? _legacyFile;
  bool _legacyMode = false;
  bool _opened = false;

  /// 最近一次打开失败的原因（诊断用）。
  String? lastOpenError;

  Map<String, dynamic> _legacyJson = {};
  bool _legacyLoaded = false;

  /// 是否已打开（SQLite 或回退模式）。
  bool get isOpen => _opened;

  /// 是否使用 SQLite 存储。
  bool get usingSqlite => _db != null;

  /// 是否处于 JSON 文件回退模式。
  bool get usingLegacy => _legacyMode;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('ChatDatabase 未打开');
    }
    return db;
  }

  Future<void> open(File dbFile, File legacyFile) async {
    _legacyFile = legacyFile;
    _opened = true;
    lastOpenError = null;
    try {
      await dbFile.parent.create(recursive: true);
      final db = sqlite3.open(dbFile.path);
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA busy_timeout = 3000');
      db.execute('''
        CREATE TABLE IF NOT EXISTS conversations (
          id   TEXT PRIMARY KEY,
          data TEXT NOT NULL
        )
      ''');
      db.execute('''
        CREATE TABLE IF NOT EXISTS meta (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
      _db = db;
      _connections.add(db);
      _legacyMode = false;

      // 迁移旧 chats.json（仅当库为空且旧文件存在）。
      final count =
          db.select('SELECT COUNT(*) AS c FROM conversations').first['c']
              as int;
      if (count == 0 && await legacyFile.exists()) {
        await _migrateFromLegacy(db, legacyFile);
      }
    } catch (e) {
      // SQLite 不可用（缺原生库/文件损坏等）→ 回退 JSON 文件模式。
      lastOpenError = '$e';
      close();
      _legacyMode = true;
      await _loadLegacy();
    }
  }

  Future<void> _migrateFromLegacy(Database db, File legacyFile) async {
    try {
      final raw = await legacyFile.readAsString();
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final conversations = ((json['conversations'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      for (final c in conversations) {
        final id = (c['id'] ?? '').toString();
        if (id.isEmpty) continue;
        db.execute(
          'INSERT OR REPLACE INTO conversations (id, data) VALUES (?, ?)',
          [id, jsonEncode(c)],
        );
      }
      db.execute(
        'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
        ['folders', jsonEncode(json['folders'] ?? [])],
      );
      db.execute(
        'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
        ['activeId', jsonEncode(json['activeId'])],
      );
      db.execute(
        'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
        ['schemaVersion', '$schemaVersion'],
      );
      // 迁移成功后旧文件改名保留，便于排查。
      final bak = File('${legacyFile.path}.migrated.bak');
      if (!await bak.exists()) {
        await legacyFile.rename(bak.path);
      }
    } catch (_) {
      // 迁移失败不阻塞：下次打开时仍视为空库。
    }
  }

  Future<void> _loadLegacy() async {
    if (_legacyLoaded) return;
    _legacyLoaded = true;
    try {
      final f = _legacyFile;
      if (f != null && await f.exists()) {
        _legacyJson =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {
      _legacyJson = {};
    }
  }

  // ─────────────────────────── 读 ───────────────────────────

  List<Map<String, dynamic>> allConversations() {
    if (_db != null) {
      final rows = _database.select('SELECT data FROM conversations');
      final out = <Map<String, dynamic>>[];
      for (final r in rows) {
        try {
          final v = jsonDecode(r['data'] as String);
          if (v is Map) out.add(Map<String, dynamic>.from(v));
        } catch (_) {
          // 单条损坏不拖垮整个会话列表。
        }
      }
      return out;
    }
    return [
      for (final m in ((_legacyJson['conversations'] as List?) ?? const []))
        if (m is Map) Map<String, dynamic>.from(m),
    ];
  }

  Map<String, dynamic> readMeta() {
    if (_db != null) {
      final out = <String, dynamic>{};
      for (final r in _database.select('SELECT key, value FROM meta')) {
        final v = r['value'] as String;
        try {
          out[r['key'] as String] = jsonDecode(v);
        } catch (_) {
          out[r['key'] as String] = v;
        }
      }
      return out;
    }
    return {
      'folders': _legacyJson['folders'] ?? const [],
      'activeId': _legacyJson['activeId'],
      'schemaVersion': _legacyJson['schemaVersion'] ?? schemaVersion,
    };
  }

  // ─────────────────────────── 写（SQLite 模式） ───────────────────────────

  void saveConversation(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    if (id.isEmpty || _db == null) return;
    _database.execute(
      'INSERT OR REPLACE INTO conversations (id, data) VALUES (?, ?)',
      [id, jsonEncode(json)],
    );
  }

  void deleteConversation(String id) {
    if (_db == null) return;
    _database.execute('DELETE FROM conversations WHERE id = ?', [id]);
  }

  void saveMeta(Map<String, dynamic> values) {
    if (_db == null) return;
    for (final e in values.entries) {
      _database.execute(
        'INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)',
        [e.key, jsonEncode(e.value)],
      );
    }
  }

  void transaction(void Function() body) {
    final db = _database;
    db.execute('BEGIN');
    try {
      body();
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ─────────────────────────── 写（回退模式） ───────────────────────────

  /// 回退模式：整体替换内存数据并落盘。
  Future<void> saveAllLegacy({
    required String? activeId,
    required List<Map<String, dynamic>> folders,
    required List<Map<String, dynamic>> conversations,
  }) async {
    _legacyJson['activeId'] = activeId;
    _legacyJson['folders'] = folders;
    _legacyJson['conversations'] = conversations;
    _legacyJson['schemaVersion'] = schemaVersion;
    try {
      final f = _legacyFile;
      if (f != null) {
        await f.create(recursive: true);
        await f.writeAsString(jsonEncode(_legacyJson));
      }
    } catch (_) {
      // 落盘失败不抛：与旧行为一致（持久化失败不阻塞对话）。
    }
  }

  /// 导出为旧格式的完整 JSON（备份 / 导出共用）。
  Map<String, dynamic> exportJson() {
    if (_db != null) {
      return {
        'activeId': readMeta()['activeId'],
        'folders': readMeta()['folders'] ?? const [],
        'conversations': allConversations(),
        'schemaVersion': schemaVersion,
      };
    }
    return Map<String, dynamic>.from(_legacyJson);
  }

  void close() {
    for (final c in _connections) {
      try {
        c.close();
      } catch (_) {}
    }
    _connections.clear();
    _db = null;
    _opened = false;
    _legacyLoaded = false;
    _legacyJson = {};
    _legacyFile = null;
  }
}
