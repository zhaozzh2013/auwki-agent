import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/memory_service.dart';

import 'helpers.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = mockPathProvider(hermetic: true);
    MemoryService.instance.resetForTest();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('同文本记忆去重并刷新时间', () async {
    await MemoryService.instance.add('我喜欢简洁回答', kind: 'preference');
    await MemoryService.instance.add('我喜欢简洁回答', kind: 'preference');
    final list = await MemoryService.instance.list();
    expect(list, hasLength(1));
    final injected = await MemoryService.instance.injectPromptText();
    expect('喜欢简洁回答'.split('').every(injected.contains), isTrue);
    expect(injected.split('- ').length - 1, 1);
  });

  test('不同文本不合并', () async {
    await MemoryService.instance.add('A', kind: 'preference');
    await MemoryService.instance.add('B', kind: 'preference');
    expect(await MemoryService.instance.list(), hasLength(2));
  });
// ── D 项目长期记忆 ────────────────────────────────────────────────

test('maybeExtractProjectFact 命中技术栈与架构描述', () {
  final s = MemoryService.instance;
  expect(
    s.maybeExtractProjectFact('这个项目用的是 Flutter 3.47 + sqlite3，架构是 MVVM。'),
    isNotNull,
  );
  expect(
    s.maybeExtractProjectFact('the backend is built with django and postgres, deployed on linux.'),
    isNotNull,
  );
});

test('maybeExtractProjectFact 不提取偏好句与普通闲聊', () {
  final s = MemoryService.instance;
  // 偏好句交给 preference 提取，不重复
  expect(s.maybeExtractProjectFact('我喜欢简洁的回答'), isNull);
  // 无信号词的闲聊
  expect(s.maybeExtractProjectFact('今天天气不错，我们出去走走吧'), isNull);
  // 过短/过长句子
  expect(s.maybeExtractProjectFact('用 flutter'), isNull);
});

test('project kind 记忆持久化并注入提示词', () async {
  await MemoryService.instance
      .add('本仓库是 Flutter 桌面应用，架构分层清晰。', kind: 'project');
  await MemoryService.instance
      .add('chat_input.dart 负责用户消息的发送主循环。', kind: 'code');
  final list = await MemoryService.instance.list();
  expect(list.where((e) => e.kind == 'project'), hasLength(1));
  expect(list.where((e) => e.kind == 'code'), hasLength(1));
  final injected = await MemoryService.instance.injectPromptText();
  expect(injected, contains('project'));
  expect(injected, contains('code'));
});
}
