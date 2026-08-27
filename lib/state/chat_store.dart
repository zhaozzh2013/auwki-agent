import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/chat_database.dart';
import '../services/workspace_manager.dart';

class ChatStore extends ChangeNotifier {
  ChatStore({this._storageDir}) {
    _load();
  }

  /// 显式指定的数据目录（测试/自定义数据位置用）；
  /// 为 null 时使用 path_provider 的默认应用数据目录。
  final Directory? _storageDir;

  final List<Conversation> _conversations = [];
  final List<Folder> _folders = [];
  String? _activeId;
  bool _loaded = false;
  Future<void>? _saving;
  bool _saveQueued = false;

  /// 增量持久化（SQLite 模式）：只写变更的行。
  final Set<String> _dirtyIds = {};
  final Set<String> _deletedIds = {};
  bool _metaDirty = false;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  List<Folder> get folders => List.unmodifiable(_folders);
  String? get activeId => _activeId;

  Conversation? get active => _activeId == null ? null : _byId(_activeId!);

  List<Conversation> get pinned =>
      _conversations.where((c) => c.pinned && c.folderId == null).toList();

  List<Conversation> get topLevel =>
      _conversations.where((c) => !c.pinned && c.folderId == null).toList();

  List<Conversation> inFolder(String folderId) =>
      _conversations.where((c) => c.folderId == folderId).toList();

  Conversation? _byId(String id) =>
      _conversations.where((c) => c.id == id).cast<Conversation?>().firstOrNull;

  Folder? folderById(String id) =>
      _folders.where((f) => f.id == id).cast<Folder?>().firstOrNull;

  Future<Directory> _dir() async {
    final d = _storageDir;
    if (d != null) return d;
    return getApplicationSupportDirectory();
  }

  Future<void> _load() async {
    try {
      final dir = await _dir();
      final dbFile = File('${dir.path}/chats.db');
      final legacyFile = File('${dir.path}/chats.json');
      await ChatDatabase.instance.open(dbFile, legacyFile);

      final conversations = ChatDatabase.instance.allConversations();
      final meta = ChatDatabase.instance.readMeta();
      final folders = ((meta['folders'] as List?) ?? const [])
          .whereType<Map>()
          .map((x) => Folder.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      final parsed = conversations
          .map((x) => Conversation.fromJson(Map<String, dynamic>.from(x)))
          .toList();
      final activeId = meta['activeId']?.toString();
      if (folders.isNotEmpty || parsed.isNotEmpty) {
        _folders
          ..clear()
          ..addAll(folders);
        _conversations
          ..clear()
          ..addAll(parsed);
        _activeId = parsed.any((c) => c.id == activeId) ? activeId : null;
      }
    } catch (_) {
      _folders.clear();
      _conversations.clear();
      _activeId = null;
    }
    _loaded = true;
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!_loaded) return;
    if (_saving != null) {
      _saveQueued = true;
      return;
    }
    // 注意：_save 的 SQLite 分支没有 await，函数体会同步执行完。
    // 不能在 _save 内部清理 _saving（赋值语句会把它覆盖回非 null），
    // 必须用 whenComplete 在微任务中清理。
    _saving = _save().whenComplete(() {
      _saving = null;
      if (_saveQueued) {
        _saveQueued = false;
        _scheduleSave();
      }
    });
  }

  Future<void> _save() async {
    try {
      final db = ChatDatabase.instance;
      if (db.usingSqlite) {
        db.transaction(() {
          for (final id in _dirtyIds) {
            final c = _byId(id);
            if (c != null) db.saveConversation(c.toJson());
          }
          for (final id in _deletedIds) {
            db.deleteConversation(id);
          }
          if (_metaDirty) {
            db.saveMeta({
              'activeId': _activeId,
              'folders': _folders.map((f) => f.toJson()).toList(),
            });
          }
        });
        _dirtyIds.clear();
        _deletedIds.clear();
        _metaDirty = false;
      } else {
        await db.saveAllLegacy(
          activeId: _activeId,
          folders: _folders.map((f) => f.toJson()).toList(),
          conversations: _conversations.map((c) => c.toJson()).toList(),
        );
        _dirtyIds.clear();
        _deletedIds.clear();
        _metaDirty = false;
      }
    } catch (e) {
      // 持久化失败不影响对话流程；记录日志便于排查。
      debugPrint('ChatStore save failed: $e');
    }
  }

  void _markDirty(String id) {
    _dirtyIds.add(id);
    _deletedIds.remove(id);
  }

  void _markDeleted(String id) {
    _deletedIds.add(id);
    _dirtyIds.remove(id);
  }

  void _markMetaDirty() {
    _metaDirty = true;
  }

  String newConversation({String? workspaceDir}) {
    final id = 'c_${DateTime.now().microsecondsSinceEpoch}';
    final c = Conversation(
      id: id,
      title: I18n.t('chat.empty'),
      workspaceDir: workspaceDir ?? WorkspaceManager.defaultWorkspacePath(id),
    );
    _conversations.insert(0, c);
    _activeId = c.id;
    _markDirty(id);
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
    return c.id;
  }

  void activate(String? id) {
    if (_activeId == id) return;
    _activeId = id;
    if (id != null) {
      final c = _byId(id);
      if (c != null) c.unread = false;
    }
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  void rename(String id, String title) {
    final c = _byId(id);
    if (c == null) return;
    c.title = title.trim().isEmpty ? c.title : title.trim();
    _markDirty(id);
    notifyListeners();
    _scheduleSave();
  }

  void togglePin(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.pinned = !c.pinned;
    _markDirty(id);
    notifyListeners();
    _scheduleSave();
  }

  void toggleUnread(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.unread = !c.unread;
    _markDirty(id);
    notifyListeners();
    _scheduleSave();
  }

  void delete(String id) {
    _conversations.removeWhere((c) => c.id == id);
    _markDeleted(id);
    if (_activeId == id) {
      _activeId = null;
      _markMetaDirty();
    }
    notifyListeners();
    _scheduleSave();
  }

  void clearMessages(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.messages.clear();
    c.updatedAt = DateTime.now();
    _markDirty(id);
    notifyListeners();
    _scheduleSave();
  }

  void toggleFolder(String id) {
    final f = folderById(id);
    if (f == null) return;
    f.expanded = !f.expanded;
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  void addFolder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = 'fld_${DateTime.now().microsecondsSinceEpoch}';
    _folders.add(Folder(id: id, name: trimmed));
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  void renameFolder(String id, String newName) {
    final f = folderById(id);
    if (f == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    f.name = trimmed;
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  void deleteFolder(String id) {
    for (final c in _conversations) {
      if (c.folderId == id) {
        c.folderId = null;
        _markDirty(c.id);
      }
    }
    _folders.removeWhere((f) => f.id == id);
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  void moveToFolder(String convId, String? folderId) {
    final c = _byId(convId);
    if (c == null) return;
    c.folderId = folderId;
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// G02：设置对话使用的模型（null = 跟随全局）。
  void setConversationModel(String convId, String? modelId) {
    final c = _byId(convId);
    if (c == null) return;
    if (c.model == modelId) return;
    c.model = modelId;
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  void reorder(List<String> orderedTopLevelIds) {
    final byId = {for (final c in _conversations) c.id: c};
    final newList = <Conversation>[];
    for (final id in orderedTopLevelIds) {
      final c = byId[id];
      if (c != null && !c.pinned && c.folderId == null) newList.add(c);
    }
    for (final c in _conversations) {
      if (c.pinned || c.folderId != null) newList.add(c);
    }
    _conversations
      ..clear()
      ..addAll(newList);
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  void reorderTopLevel(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final topList = topLevel;
    if (oldIndex < 0 ||
        oldIndex >= topList.length ||
        newIndex < 0 ||
        newIndex >= topList.length) {
      return;
    }
    final moving = topList.removeAt(oldIndex);
    topList.insert(newIndex, moving);
    // rebuild full list: pinned first, then topLevel (in new order), then folders
    final folders = <Conversation>[];
    final newList = <Conversation>[];
    for (final c in _conversations) {
      if (c.pinned) newList.add(c);
    }
    newList.addAll(topList);
    for (final c in _conversations) {
      if (c.folderId != null) folders.add(c);
    }
    newList.addAll(folders);
    _conversations
      ..clear()
      ..addAll(newList);
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  void addMessage(String convId, Message msg) {
    final c = _byId(convId);
    if (c == null) return;
    // 会话自动命名：第一条用户消息作为标题。
    if (c.messages.isEmpty &&
        msg.sender == Sender.user &&
        c.title == I18n.t('chat.empty')) {
      final firstLine = msg.text.trim().split('\n').first.trim();
      c.title = firstLine.length <= 20
          ? firstLine
          : '${firstLine.substring(0, 20)}…';
    }
    c.messages.add(msg);
    c.updatedAt = DateTime.now();
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// 编辑一条用户消息，并丢弃其后所有消息（保证上下文一致）。
  void editUserMessage(String convId, String msgId, String newText) {
    final c = _byId(convId);
    if (c == null) return;
    final i = c.messages.indexWhere(
      (m) => m.id == msgId && m.sender == Sender.user,
    );
    if (i < 0) return;
    final text = newText.trim();
    if (text.isEmpty || text == c.messages[i].text) return;
    c.messages[i] = Message(
      id: c.messages[i].id,
      sender: Sender.user,
      text: text,
      attachments: c.messages[i].attachments,
      createdAt: c.messages[i].createdAt,
    );
    c.messages.removeRange(i + 1, c.messages.length);
    c.updatedAt = DateTime.now();
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// 从指定用户消息开始重新生成：删除该消息及其后的所有内容。
  void regenerateFrom(String convId, String msgId) {
    final c = _byId(convId);
    if (c == null) return;
    final i = c.messages.indexWhere(
      (m) => m.id == msgId && m.sender == Sender.user,
    );
    if (i < 0) return;
    c.messages.removeRange(i, c.messages.length);
    c.updatedAt = DateTime.now();
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// 全文搜索：匹配消息正文、工具参数与工具结果。
  /// [since] 限定最早时间；[tag] 限定对话标签（B07 增强）。
  List<(Conversation, Message)> searchMessages(
    String query, {
    DateTime? since,
    String? tag,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final out = <(Conversation, Message)>[];
    for (final c in _conversations) {
      if (tag != null && !c.tags.contains(tag)) continue;
      for (final m in c.messages) {
        if (since != null && m.createdAt.isBefore(since)) continue;
        final hay = '${m.text}\n${m.toolArgs ?? ''}\n${m.toolResult ?? ''}'
            .toLowerCase();
        if (hay.contains(q)) out.add((c, m));
      }
    }
    return out;
  }

  void updateMessage(
    String convId,
    String msgId,
    String text, {
    bool persist = true,
  }) {
    final c = _byId(convId);
    if (c == null) return;
    final i = c.messages.indexWhere((m) => m.id == msgId);
    if (i < 0) return;
    c.messages[i] = Message(
      id: c.messages[i].id,
      sender: c.messages[i].sender,
      text: text,
      attachments: c.messages[i].attachments,
      toolName: c.messages[i].toolName,
      toolArgs: c.messages[i].toolArgs,
      toolResult: c.messages[i].toolResult,
      toolOk: c.messages[i].toolOk,
      toolRunning: c.messages[i].toolRunning,
      createdAt: c.messages[i].createdAt,
    );
    notifyListeners();
    if (persist) {
      _markDirty(convId);
      _scheduleSave();
    }
  }

  void finishToolMessage(String convId, String msgId, String result, bool ok) {
    final c = _byId(convId);
    if (c == null) return;
    final i = c.messages.indexWhere((m) => m.id == msgId);
    if (i < 0) return;
    final orig = c.messages[i];
    c.messages[i] = Message(
      id: orig.id,
      sender: orig.sender,
      text: orig.text,
      attachments: orig.attachments,
      toolName: orig.toolName,
      toolArgs: orig.toolArgs,
      toolResult: result,
      toolOk: ok,
      toolRunning: false,
      createdAt: orig.createdAt,
    );
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// B02：切换消息收藏状态。
  void toggleFavorite(String convId, String msgId) {
    final c = _byId(convId);
    if (c == null) return;
    final i = c.messages.indexWhere((m) => m.id == msgId);
    if (i < 0) return;
    c.messages[i].favorite = !c.messages[i].favorite;
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// B02：全部收藏消息（跨对话），供收藏夹展示。
  List<(Conversation, Message)> get favorites => [
        for (final c in _conversations)
          for (final m in c.messages)
            if (m.favorite) (c, m),
      ];

  /// B06：保存 AI 生成的对话摘要。
  void setSummary(String convId, String summary) {
    final c = _byId(convId);
    if (c == null) return;
    c.summary = summary.trim().isEmpty ? null : summary.trim();
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// B12：设置对话标签（覆盖）。
  void setTags(String convId, List<String> tags) {
    final c = _byId(convId);
    if (c == null) return;
    c.tags = [
      for (final t in tags)
        if (t.trim().isNotEmpty) t.trim(),
    ];
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// B12：全部标签（跨对话去重）。
  List<String> get allTags {
    final set = <String>{};
    for (final c in _conversations) {
      set.addAll(c.tags);
    }
    return set.toList()..sort();
  }

  /// 清空并恢复为指定数据（F08 恢复向导）。
  void restoreAll({
    required List<Conversation> conversations,
    required List<Folder> folders,
    String? activeId,
  }) {
    final prevIds = {for (final c in _conversations) c.id};
    final newIds = {for (final c in conversations) c.id};
    for (final id in prevIds.difference(newIds)) {
      _markDeleted(id);
    }
    _conversations
      ..clear()
      ..addAll(conversations);
    _folders
      ..clear()
      ..addAll(folders);
    _activeId = newIds.contains(activeId) ? activeId : null;
    _dirtyIds.addAll(newIds);
    _markMetaDirty();
    notifyListeners();
    _scheduleSave();
  }

  /// 导入历史对话（F02）：按 id 去重合并，返回新增数量。
  int importConversations(List<Conversation> incoming) {
    final existing = {for (final c in _conversations) c.id};
    var added = 0;
    for (final c in incoming) {
      if (existing.contains(c.id)) continue;
      _conversations.add(c);
      existing.add(c.id);
      _markDirty(c.id);
      added++;
    }
    if (added > 0) {
      notifyListeners();
      _scheduleSave();
    }
    return added;
  }

  /// A15：把单个会话恢复为快照中的状态（消息/标题/标签/模型等整体替换）。
  void restoreConversationSnapshot(Map<String, dynamic> json) {
    final conv = Conversation.fromJson(json);
    final existing = _byId(conv.id);
    if (existing == null) return;
    existing
      ..title = conv.title
      ..folderId = conv.folderId
      ..workspaceDir = conv.workspaceDir
      ..additionalWorkspaces = List<String>.from(conv.additionalWorkspaces)
      ..pinned = conv.pinned
      ..unread = conv.unread
      ..tags = List<String>.from(conv.tags)
      ..summary = conv.summary
      ..model = conv.model
      ..messages = List<Message>.from(conv.messages)
      ..updatedAt = conv.updatedAt;
    _markDirty(conv.id);
    notifyListeners();
    _scheduleSave();
  }

  /// A12：设置会话的附加工作区目录列表。
  void setAdditionalWorkspaces(String convId, List<String> dirs) {
    final c = _byId(convId);
    if (c == null) return;
    c.additionalWorkspaces = [
      for (final d in dirs)
        if (d.trim().isNotEmpty) d.trim(),
    ];
    _markDirty(convId);
    notifyListeners();
    _scheduleSave();
  }

  /// 数据保留（F10）：删除超过保留期的对话，返回删除数量。
  int applyRetention(Duration maxAge) {
    if (maxAge <= Duration.zero) return 0;
    final cutoff = DateTime.now().subtract(maxAge);
    final doomed = _conversations
        .where((c) => c.updatedAt.isBefore(cutoff))
        .toList();
    for (final c in doomed) {
      _conversations.remove(c);
      _markDeleted(c.id);
      if (_activeId == c.id) {
        _activeId = null;
        _markMetaDirty();
      }
    }
    if (doomed.isNotEmpty) {
      notifyListeners();
      _scheduleSave();
    }
    return doomed.length;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
