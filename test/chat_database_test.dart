import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:auwki_agent/services/chat_database.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('chat_db_test');
    ChatDatabase.instance.close();
  });

  tearDown(() {
    ChatDatabase.instance.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('SQLite 读写：对话与元数据往返', () async {
    final db = ChatDatabase.instance;
    await db.open(
      File('${tmp.path}/chats.db'),
      File('${tmp.path}/chats.json'),
    );
    expect(db.usingSqlite, isTrue);

    db.saveConversation({
      'id': 'c_1',
      'title': '测试',
      'messages': [
        {'id': 'm_1', 'sender': 'user', 'text': '你好'},
      ],
    });
    db.saveConversation({'id': 'c_2', 'title': '另一个'});
    db.saveMeta({'activeId': 'c_1', 'folders': <dynamic>[]});

    final convs = db.allConversations();
    expect(convs.length, 2);
    expect(convs[0]['id'], 'c_1');
    final meta = db.readMeta();
    expect(meta['activeId'], 'c_1');

    // 更新与删除
    db.saveConversation({'id': 'c_2', 'title': '改名'});
    db.deleteConversation('c_1');
    expect(db.allConversations().length, 1);
    expect(db.allConversations().first['title'], '改名');
  });

  test('增量更新不产生重复行', () async {
    final db = ChatDatabase.instance;
    await db.open(
      File('${tmp.path}/chats.db'),
      File('${tmp.path}/chats.json'),
    );
    db.saveConversation({'id': 'c_1', 'title': 'v1'});
    db.saveConversation({'id': 'c_1', 'title': 'v2'});
    expect(db.allConversations().length, 1);
    expect(db.allConversations().first['title'], 'v2');
  });

  test('旧 chats.json 自动迁移到 SQLite 并保留备份', () async {
    final legacy = File('${tmp.path}/chats.json');
    await legacy.writeAsString(jsonEncode({
      'activeId': 'c_old',
      'folders': <dynamic>[],
      'conversations': [
        {
          'id': 'c_old',
          'title': '旧数据',
          'messages': [
            {'id': 'm_old', 'sender': 'user', 'text': '历史消息'},
          ],
        },
      ],
    }));

    final db = ChatDatabase.instance;
    await db.open(File('${tmp.path}/chats.db'), legacy);

    expect(db.usingSqlite, isTrue);
    final convs = db.allConversations();
    expect(convs.length, 1);
    expect(convs.first['id'], 'c_old');
    expect(db.readMeta()['activeId'], 'c_old');
    expect(
      File('${tmp.path}/chats.json.migrated.bak').existsSync(),
      isTrue,
    );
  });

  test('exportJson 输出旧格式完整结构', () async {
    final db = ChatDatabase.instance;
    await db.open(
      File('${tmp.path}/chats.db'),
      File('${tmp.path}/chats.json'),
    );
    db.saveConversation({'id': 'c_1', 'title': 't'});
    db.saveMeta({'activeId': 'c_1', 'folders': <dynamic>[]});
    final json = db.exportJson();
    expect(json['conversations'], hasLength(1));
    expect(json['activeId'], 'c_1');
    expect(json['schemaVersion'], ChatDatabase.schemaVersion);
  });

  test('损坏的对话行不影响其他对话读取', () async {
    final db = ChatDatabase.instance;
    await db.open(
      File('${tmp.path}/chats.db'),
      File('${tmp.path}/chats.json'),
    );
    db.saveConversation({'id': 'good', 'title': '正常'});
    // 用独立连接写入一条损坏 JSON 的行。
    final rawDb = sqlite3.open('${tmp.path}/chats.db');
    rawDb.execute(
      'INSERT OR REPLACE INTO conversations (id, data) VALUES (?, ?)',
      ['bad', '{corrupt json'],
    );
    rawDb.close();

    final convs = db.allConversations();
    expect(convs.length, 1);
    expect(convs.single['id'], 'good');
  });
}
