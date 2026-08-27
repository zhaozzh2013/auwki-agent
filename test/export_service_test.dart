import 'dart:convert';

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

  test('conversationToJsonl 每条消息一行 JSON', () {
    final conv = Conversation(
      id: 'c1',
      title: '测试',
      messages: [
        Message(id: 'm1', sender: Sender.user, text: '你好'),
        Message(id: 'm2', sender: Sender.assistant, text: '回复'),
      ],
    );
    final jsonl = ExportService.conversationToJsonl(conv);
    final lines = jsonl.split('\n');
    expect(lines, hasLength(2));
    final first = jsonDecode(lines[0]) as Map<String, dynamic>;
    expect(first['sender'], 'user');
    expect(first['text'], '你好');
  });

  test('conversationToHtml 输出自包含页面', () {
    final conv = Conversation(
      id: 'c1',
      title: '测试对话',
      updatedAt: DateTime(2026, 8, 7, 10, 30),
      messages: [
        Message(id: 'm1', sender: Sender.user, text: '你好'),
        Message(
          id: 'm2',
          sender: Sender.assistant,
          text: '**加粗** 与 `代码`',
        ),
      ],
    );
    final html = ExportService.conversationToHtml(conv);
    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('<title>测试对话</title>'));
    expect(html, contains('<strong>加粗</strong>'));
    expect(html, contains('<code>代码</code>'));
    expect(html, contains('<style>'));
    // HTML 转义
    final evil = ExportService.conversationToHtml(
      Conversation(
        id: 'c2',
        title: '<script>alert(1)</script>',
        messages: const [],
      ),
    );
    expect(evil, contains('&lt;script&gt;'));
  });
}
