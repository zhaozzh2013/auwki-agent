import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/models/models.dart';
import 'package:auwki_agent/services/chat_database.dart';
import 'package:auwki_agent/state/chat_store.dart';

void main() {
  late Directory dataDir;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('auwki_store_test');
    ChatDatabase.instance.close();
  });

  tearDown(() {
    ChatDatabase.instance.close();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  ChatStore newStore() => ChatStore(storageDir: dataDir);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  test('SQLite 持久化：创建→重开→数据完整', () async {
    final store1 = newStore();
    await settle();
    final id = store1.newConversation();
    store1.addMessage(
      id,
      Message(id: 'm_1', sender: Sender.user, text: '第一条消息'),
    );
    store1.rename(id, '持久化测试');
    await settle();

    final store2 = newStore();
    await settle();
    expect(store2.conversations, hasLength(1));
    final c = store2.conversations.first;
    expect(c.title, '持久化测试');
    expect(c.messages, hasLength(1));
    expect(c.messages.first.text, '第一条消息');
  });

  test('删除对话后重开不存在', () async {
    final store1 = newStore();
    await settle();
    final id = store1.newConversation();
    await settle();
    store1.delete(id);
    await settle();

    final store2 = newStore();
    await settle();
    expect(store2.conversations, isEmpty);
  });

  test('restoreAll 替换全部数据', () async {
    final store = newStore();
    await settle();
    store.newConversation();
    await settle();

    store.restoreAll(
      conversations: [
        Conversation(id: 'r_1', title: '恢复1'),
        Conversation(id: 'r_2', title: '恢复2'),
      ],
      folders: [Folder(id: 'f_1', name: '文件夹')],
      activeId: 'r_1',
    );
    await settle();

    final store2 = newStore();
    await settle();
    expect(store2.conversations, hasLength(2));
    expect(store2.folders, hasLength(1));
    expect(store2.activeId, 'r_1');
  });

  test('importConversations 按 id 去重合并', () async {
    final store = newStore();
    await settle();
    store.newConversation();
    await settle();

    final added = store.importConversations([
      Conversation(id: 'new_1', title: '导入1'),
      Conversation(id: 'dup', title: '重复'),
    ]);
    expect(added, 2);
    final added2 = store.importConversations([
      Conversation(id: 'dup', title: '重复'),
      Conversation(id: 'new_2', title: '导入2'),
    ]);
    expect(added2, 1);
    expect(store.conversations.length, 4);
  });

  test('applyRetention 只删除超期对话', () async {
    final store = newStore();
    await settle();
    final old = store.newConversation();
    store.conversations
        .firstWhere((c) => c.id == old)
        .updatedAt = DateTime.now().subtract(const Duration(days: 400));
    final fresh = store.newConversation();

    final removed = store.applyRetention(const Duration(days: 365));
    expect(removed, 1);
    expect(store.conversations.any((c) => c.id == old), isFalse);
    expect(store.conversations.any((c) => c.id == fresh), isTrue);
  });

  test('applyRetention(0) 不删除任何对话', () async {
    final store = newStore();
    await settle();
    store.newConversation();
    expect(store.applyRetention(Duration.zero), 0);
    expect(store.conversations, isNotEmpty);
  });

  test('G02: 对话模型设置持久化', () async {
    final store1 = newStore();
    await settle();
    final id = store1.newConversation();
    store1.setConversationModel(id, 'gpt-4o-mini');
    await settle();

    final store2 = newStore();
    await settle();
    expect(store2.conversations.first.model, 'gpt-4o-mini');

    // 恢复为全局
    store2.setConversationModel(id, null);
    await settle();
    final store3 = newStore();
    await settle();
    expect(store3.conversations.first.model, isNull);
  });

  test('B02: 消息收藏持久化与收藏列表', () async {
    final store1 = newStore();
    await settle();
    final id = store1.newConversation();
    store1.addMessage(
      id,
      Message(id: 'm_1', sender: Sender.user, text: '重要内容'),
    );
    store1.toggleFavorite(id, 'm_1');
    await settle();

    expect(store1.favorites, hasLength(1));
    final store2 = newStore();
    await settle();
    expect(store2.favorites, hasLength(1));
    expect(store2.favorites.first.$2.text, '重要内容');

    // 取消收藏
    store2.toggleFavorite(id, 'm_1');
    await settle();
    final store3 = newStore();
    await settle();
    expect(store3.favorites, isEmpty);
  });

  test('B12: 标签设置、持久化与搜索过滤', () async {
    final store1 = newStore();
    await settle();
    final id = store1.newConversation();
    store1.addMessage(
      id,
      Message(id: 'm_1', sender: Sender.user, text: '项目需求'),
    );
    store1.setTags(id, ['工作', '项目']);
    await settle();

    expect(store1.allTags, containsAll(['工作', '项目']));

    // 按标签过滤搜索
    final tagged = store1.searchMessages('需求', tag: '工作');
    expect(tagged, hasLength(1));
    final other = store1.searchMessages('需求', tag: '不存在的标签');
    expect(other, isEmpty);

    // 按时间过滤
    final future = store1.searchMessages(
      '需求',
      since: DateTime.now().add(const Duration(days: 1)),
    );
    expect(future, isEmpty);

    // 持久化
    final store2 = newStore();
    await settle();
    expect(store2.conversations.first.tags, ['工作', '项目']);
  });

  test('B06: 对话摘要持久化', () async {
    final store1 = newStore();
    await settle();
    final id = store1.newConversation();
    store1.setSummary(id, '这是摘要');
    await settle();

    final store2 = newStore();
    await settle();
    expect(store2.conversations.first.summary, '这是摘要');
  });
}
