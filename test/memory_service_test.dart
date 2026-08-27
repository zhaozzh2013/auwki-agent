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
}
