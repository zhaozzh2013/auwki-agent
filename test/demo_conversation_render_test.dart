import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/app_state.dart';
import 'package:auwki_agent/main.dart';
import 'package:auwki_agent/services/chat_database.dart';
import 'package:auwki_agent/services/demo_conversation.dart';

import 'helpers.dart';

/// 回归测试：打开功能演示对话必须正常渲染。
///
/// 曾修复：代码块复制按钮的 Stack+Positioned 在 markdown 无界高度约束下
/// 布局失败（release 下尺寸变 Infinity → TransformLayer invalid matrix、
/// 文字堆叠）。此测试打开 demo 对话并断言无任何布局异常。
void main() {
  late Directory dataDir;

  setUp(() {
    dataDir = mockPathProvider(hermetic: true);
    ChatDatabase.instance.close();
  });

  tearDown(() {
    ChatDatabase.instance.close();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  testWidgets('打开功能演示对话：无布局异常、消息正常渲染', (tester) async {
    final support = Directory('${dataDir.path}/support');
    support.createSync(recursive: true);
    File('${support.path}/settings.json').writeAsStringSync(jsonEncode({
      'provider': 'openai',
      'model': 'gpt-4o-mini',
      'apiKey': '',
      'onboardingSeen': true,
    }));

    await tester.pumpWidget(const AuwkiAgentApp());
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 走 _createDemoConversation 相同的逻辑打开功能演示对话
    final ctx = tester.element(find.byType(MaterialApp));
    final store = AppState.chatOf(ctx);
    for (final c in store.conversations.toList()) {
      if (c.id == DemoConversation.id) store.delete(c.id);
    }
    store.importConversations([DemoConversation.build()]);
    store.activate(DemoConversation.id);
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    // 无布局/渲染异常（Stack bounded、RenderBox not laid out 等）
    expect(tester.takeException(), isNull,
        reason: '打开演示对话不应产生布局异常');
    // 消息确实渲染出来了（代码块复制按钮可见）
    expect(find.byIcon(Icons.copy), findsWidgets,
        reason: '代码块复制按钮应正常渲染');
  });
}