import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../models/models.dart';

class ChatStore extends ChangeNotifier {
  ChatStore() {
    _load();
  }

  final List<Conversation> _conversations = [];
  final List<Folder> _folders = [];
  String? _activeId;
  bool _loaded = false;
  Future<void>? _saving;
  bool _saveQueued = false;

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

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/chats.json');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final folders = ((json['folders'] as List?) ?? const [])
            .whereType<Map>()
            .map((x) => Folder.fromJson(Map<String, dynamic>.from(x)))
            .toList();
        final conversations = ((json['conversations'] as List?) ?? const [])
            .whereType<Map>()
            .map((x) => Conversation.fromJson(Map<String, dynamic>.from(x)))
            .toList();
        final activeId = json['activeId']?.toString();
        if (folders.isNotEmpty || conversations.isNotEmpty) {
          _folders
            ..clear()
            ..addAll(folders);
          _conversations
            ..clear()
            ..addAll(conversations);
          _activeId = conversations.any((c) => c.id == activeId)
              ? activeId
              : null;
        }
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
    _saving = _save();
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.create(recursive: true);
      await f.writeAsString(
        jsonEncode({
          'activeId': _activeId,
          'folders': _folders.map((f) => f.toJson()).toList(),
          'conversations': _conversations.map((c) => c.toJson()).toList(),
        }),
      );
    } catch (_) {
      // Ignore persistence failures for now to avoid breaking chat flow.
    } finally {
      _saving = null;
      if (_saveQueued) {
        _saveQueued = false;
        _scheduleSave();
      }
    }
  }

  String newConversation() {
    final c = Conversation(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      title: I18n.t('chat.empty'),
    );
    _conversations.insert(0, c);
    _activeId = c.id;
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
    notifyListeners();
    _scheduleSave();
  }

  void rename(String id, String title) {
    final c = _byId(id);
    if (c == null) return;
    c.title = title.trim().isEmpty ? c.title : title.trim();
    notifyListeners();
    _scheduleSave();
  }

  void togglePin(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.pinned = !c.pinned;
    notifyListeners();
    _scheduleSave();
  }

  void toggleUnread(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.unread = !c.unread;
    notifyListeners();
    _scheduleSave();
  }

  void delete(String id) {
    _conversations.removeWhere((c) => c.id == id);
    if (_activeId == id) _activeId = null;
    notifyListeners();
    _scheduleSave();
  }

  void clearMessages(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.messages.clear();
    c.updatedAt = DateTime.now();
    notifyListeners();
    _scheduleSave();
  }

  void toggleFolder(String id) {
    final f = folderById(id);
    if (f == null) return;
    f.expanded = !f.expanded;
    notifyListeners();
    _scheduleSave();
  }

  void addFolder(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final id = 'fld_${DateTime.now().microsecondsSinceEpoch}';
    _folders.add(Folder(id: id, name: trimmed));
    notifyListeners();
    _scheduleSave();
  }

  void renameFolder(String id, String newName) {
    final f = folderById(id);
    if (f == null) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    f.name = trimmed;
    notifyListeners();
    _scheduleSave();
  }

  void deleteFolder(String id) {
    for (final c in _conversations) {
      if (c.folderId == id) c.folderId = null;
    }
    _folders.removeWhere((f) => f.id == id);
    notifyListeners();
    _scheduleSave();
  }

  void moveToFolder(String convId, String? folderId) {
    final c = _byId(convId);
    if (c == null) return;
    c.folderId = folderId;
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
    notifyListeners();
    _scheduleSave();
  }

  void addMessage(String convId, Message msg) {
    final c = _byId(convId);
    if (c == null) return;
    c.messages.add(msg);
    c.updatedAt = DateTime.now();
    notifyListeners();
    _scheduleSave();
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
    if (persist) _scheduleSave();
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
    notifyListeners();
    _scheduleSave();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
