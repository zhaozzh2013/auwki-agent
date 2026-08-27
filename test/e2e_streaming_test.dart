import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/app_state.dart';
import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/main.dart';
import 'package:auwki_agent/models/models.dart';
import 'package:auwki_agent/pages/home_page.dart';
import 'package:auwki_agent/services/chat_database.dart';

import 'helpers.dart';

class _RealHttpOverrides extends HttpOverrides {}

/// 端到端验证核心聊天链路：
/// 发送 → 流式输出 → 工具调用解析 → 权限确认 → 工具执行 → 结果回灌 → 最终回答。
void main() {
  late Directory dataDir;
  late HttpServer server;
  late int port;
  var requestCount = 0;
  late String mode; // 'command' | 'writefile'

  Future<void> startServer() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((req) async {
      if (req.method != 'POST' || !req.uri.path.endsWith('/chat/completions')) {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      await req.drain<void>();
      requestCount++;
      req.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      req.response.write('data: ${jsonEncode({
            'choices': [
              {
                'delta': {
                  'content': requestCount == 1
                      ? '[正式输出]\n${mode == 'command' ? 'command("echo hi")' : 'writefile("hello.txt|||hi")'}\n[输出结束]'
                      : '[最后输出]\n完成验证\n[输出结束]',
                },
              },
            ],
          })}\n\n');
      req.response.write('data: [DONE]\n\n');
      await req.response.close();
    });
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Future<void> settleReal() async {
      // 让真实异步 I/O（HTTP/进程）在 FakeAsync 测试中得以完成。
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }

    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await settleReal();
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Timed out (requests=$requestCount) waiting for $finder');
  }

  setUp(() {
    HttpOverrides.global = _RealHttpOverrides();
    dataDir = mockPathProvider(hermetic: true);
    ChatDatabase.instance.close();
    requestCount = 0;
  });

  tearDown(() async {
    HttpOverrides.global = null;
    ChatDatabase.instance.close();
    server.close(force: true);
    // 异步 HttpClient 计时器可能短暂占用文件，重试删除避免偶发失败。
    for (var i = 0; i < 5; i++) {
      try {
        if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
        break;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  Future<void> seedSettings() async {
    final support = Directory('${dataDir.path}/support');
    support.createSync(recursive: true);
    File('${support.path}/settings.json').writeAsStringSync(jsonEncode({
      'provider': 'openai',
      'model': 'gpt-4o-mini',
      'apiKey': 'sk-test',
      'baseUrl': 'http://127.0.0.1:$port/v1',
      'onboardingSeen': true,
      'showRoundChanges': false,
    }));
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(const AuwkiAgentApp());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(HomePage), findsOneWidget);
  }

  testWidgets('E2E: command tool call runs after confirmation and finalizes',
      (tester) async {
    mode = 'command';
    await tester.runAsync(startServer);
    await seedSettings();
    await pumpApp(tester);

    // Ctrl+N 直接创建并激活会话（保持输入组件不销毁，确认弹窗才能弹出）。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '运行一个测试命令',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.arrow_upward).first);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    // 命令批量确认弹窗 → 允许。
    await pumpUntilFound(
      tester,
      find.text(I18n.t('dialog.command.batch.allow')),
    );
    await tester.tap(find.text(I18n.t('dialog.command.batch.allow')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );

    // 最终回答出现。
    await pumpUntilFound(tester, find.textContaining('完成验证'));
    expect(requestCount, greaterThanOrEqualTo(2));
    // 卸载组件树，清理 App 内的周期定时器。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // 推进假时钟，触发 HttpClient 空闲连接定时器，避免残留定时器断言。
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('E2E: writefile change requires diff confirm and writes file',
      (tester) async {
    mode = 'writefile';
    await tester.runAsync(startServer);
    await seedSettings();
    await pumpApp(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '创建文件',
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    // A06 文件改动确认弹窗 → 应用。
    await pumpUntilFound(tester, find.text(I18n.t('file_confirm.apply')));
    await tester.tap(find.text(I18n.t('file_confirm.apply')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );

    // 最终回答出现。
    await pumpUntilFound(tester, find.textContaining('完成验证'));
    // 工具消息结果应包含“已写入”。
    final store = AppState.chatOf(tester.element(find.byType(HomePage)));
    final toolMsgs = store.active!.messages
        .where((m) => m.sender == Sender.tool && m.toolName == 'writefile')
        .toList();
    expect(toolMsgs, isNotEmpty);
    expect(toolMsgs.last.toolResult, contains('已写入'));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
  });
}
