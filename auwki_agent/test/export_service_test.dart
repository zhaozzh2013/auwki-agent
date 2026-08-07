import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/models/models.dart';
import 'package:auwki_agent/services/export_service.dart';

void main() {
  test('conversationToMarkdown 包含标题、消息与工具内容', () {
    I18n.locale.value = const Locale('zh', 'CN');
    final conv = Conversation(
      id: 'c1',
      title: '测试对话',
      updatedAt: DateTime(2026, 8, 7, 10, 30),
      messages: [
        Message(
          id: 'm1',
          sender: Sender.user,
          text: '你好',
          createdAt: DateTime(2026, 8, 7, 10, 30),
        ),
        Message(
          id: 'm2',
          sender: Sender.assistant,
          text: '你好！有什么可以帮你？',
          createdAt: DateTime(2026, 8, 7, 10, 31),
        ),
        Message(
          id: 'm3',
          sender: Sender.tool,
          text: '已完成',
          toolName: 'writefile',
          toolArgs: 'a.txt|||content',
          toolResult: '[完成] 已写入 a.txt',
          createdAt: DateTime(2026, 8, 7, 10, 32),
        ),
      ],
    );

    final md = ExportService.conversationToMarkdown(conv);
    expect(md, contains('# 测试对话'));
    expect(md, contains('## 你'));
    expect(md, contains('你好'));
    expect(md, contains('## AUWKI'));
    expect(md, contains('🔧 写入文件'));
    expect(md, contains('[完成] 已写入 a.txt'));
    expect(md, contains('导出时间：2026-08-07 10:30'));
  });
}
