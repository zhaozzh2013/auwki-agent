import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// 一条会话快照（A15）。
class ConversationSnapshot {
  ConversationSnapshot({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.conversation,
  });

  final String id;
  final String label;
  final DateTime createdAt;
  final Conversation conversation;

  factory ConversationSnapshot.fromJson(Map<String, dynamic> m) =>
      ConversationSnapshot(
        id: (m['id'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        createdAt: DateTime.tryParse((m['createdAt'] ?? '').toString()) ??
            DateTime.now(),
        conversation: Conversation.fromJson(
          Map<String, dynamic>.from(m['conversation'] as Map? ?? const {}),
        ),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'createdAt': createdAt.toIso8601String(),
    'conversation': conversation.toJson(),
  };
}

/// 会话快照/恢复点（A15）：手动存档，可回退到任意存档点。
class SnapshotService {
  SnapshotService._();

  static final SnapshotService instance = SnapshotService._();

  /// 测试用：覆盖快照目录位置。
  static Directory? debugDir;

  Future<Directory> _dir() async {
    final override = debugDir;
    if (override != null) return override;
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/snapshots');
  }

  Future<ConversationSnapshot> save(
    Conversation conv, {
    String? label,
  }) async {
    final snap = ConversationSnapshot(
      id: 'snap_${DateTime.now().microsecondsSinceEpoch}',
      label: (label?.trim().isNotEmpty == true)
          ? label!.trim()
          : '${conv.title} ${DateTime.now().toLocal()}',
      createdAt: DateTime.now(),
      conversation: conv,
    );
    final dir = await _dir();
    await dir.create(recursive: true);
    final f = File('${dir.path}/${snap.id}.json');
    await f.writeAsString(jsonEncode(snap.toJson()));
    return snap;
  }

  Future<List<ConversationSnapshot>> list({String? conversationId}) async {
    final out = <ConversationSnapshot>[];
    try {
      final dir = await _dir();
      if (!await dir.exists()) return out;
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File || !e.path.endsWith('.json')) continue;
        try {
          final snap = ConversationSnapshot.fromJson(
            jsonDecode(await e.readAsString()) as Map<String, dynamic>,
          );
          if (conversationId == null ||
              snap.conversation.id == conversationId) {
            out.add(snap);
          }
        } catch (_) {}
      }
    } catch (_) {}
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> delete(String id) async {
    try {
      final dir = await _dir();
      final f = File('${dir.path}/$id.json');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> clearForConversation(String conversationId) async {
    final snaps = await list(conversationId: conversationId);
    for (final s in snaps) {
      await delete(s.id);
    }
  }
}
