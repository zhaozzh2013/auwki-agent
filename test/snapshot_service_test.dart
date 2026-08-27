import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/models/models.dart';
import 'package:auwki_agent/services/chat_database.dart';
import 'package:auwki_agent/services/snapshot_service.dart';
import 'package:auwki_agent/state/chat_store.dart';

void main() {
  late Directory dataDir;
  late Directory snapDir;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('auwki_snapshot_store');
    snapDir = Directory.systemTemp.createTempSync('auwki_snapshot_files');
    SnapshotService.debugDir = snapDir;
    ChatDatabase.instance.close();
  });

  tearDown(() {
    ChatDatabase.instance.close();
    SnapshotService.debugDir = null;
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
    if (snapDir.existsSync()) snapDir.deleteSync(recursive: true);
  });

  ChatStore newStore() => ChatStore(storageDir: dataDir);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  test('A15: save/list/delete conversation snapshots', () async {
    final conv = Conversation(
      id: 'c1',
      title: '测试对话',
      messages: [
        Message(id: 'm1', sender: Sender.user, text: '你好'),
      ],
    );
    final snap = await SnapshotService.instance.save(conv);
    final list = await SnapshotService.instance.list(conversationId: 'c1');
    expect(list, hasLength(1));
    expect(list.first.id, snap.id);

    await SnapshotService.instance.delete(snap.id);
    expect(
      await SnapshotService.instance.list(conversationId: 'c1'),
      isEmpty,
    );
  });

  test('A15: restore replaces conversation messages', () async {
    final store = newStore();
    await settle();
    final id = store.newConversation();
    store.addMessage(
      id,
      Message(id: 'm1', sender: Sender.user, text: '第一轮'),
    );
    await settle();
    final conv = store.conversations.first;
    await SnapshotService.instance.save(conv);

    store.addMessage(
      id,
      Message(id: 'm2', sender: Sender.assistant, text: '第二轮回复'),
    );
    await settle();
    expect(store.conversations.first.messages, hasLength(2));

    final snaps = await SnapshotService.instance.list(conversationId: id);
    expect(snaps, hasLength(1));
    store.restoreConversationSnapshot(snaps.first.conversation.toJson());
    expect(store.conversations.first.messages, hasLength(1));
    expect(store.conversations.first.messages.first.text, '第一轮');
  });
}
