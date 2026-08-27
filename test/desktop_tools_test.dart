import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';
import 'package:auwki_agent/services/desktop_control.dart';

void main() {
  test('解析桌面工具调用', () {
    final calls = AgentRunner.parse(
      '[正式输出]\n'
      'desktop_dump("")\n'
      'desktop_click("100,200")\n'
      'desktop_type("hello")\n'
      'desktop_key("^s")\n'
      '[输出结束]',
    );
    expect(
      calls.map((c) => c.tool).toList(),
      ['desktop_dump', 'desktop_click', 'desktop_type', 'desktop_key'],
    );
  });

  test('解析无参桌面工具调用 desktop_dump()', () {
    final calls = AgentRunner.parse(
      '[正式输出]\n'
      'desktop_dump()\n'
      'desktop_wait("500")\n'
      '[输出结束]',
    );
    expect(
      calls.map((c) => c.tool).toList(),
      ['desktop_dump', 'desktop_wait'],
    );
    expect(calls.first.args, '');
    expect(calls.last.args, '500');
  });

  test('解析 desktop_ocr 调用', () {
    final calls = AgentRunner.parse(
      '[正式输出]\n'
      'desktop_ocr("")\n'
      '[输出结束]',
    );
    expect(calls.single.tool, 'desktop_ocr');
    expect(calls.single.args, '');
  });

  test('isDesktopTool 识别桌面工具', () {
    expect(AgentRunner.isDesktopTool('desktop_click'), isTrue);
    expect(AgentRunner.isDesktopTool('desktop_wait'), isTrue);
    expect(AgentRunner.isDesktopTool('readfile'), isFalse);
  });

  test('desktop_wait 可执行', () async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'desktop_wait', args: '1'),
    );
    expect(r.output, contains('[ok] waited 1ms'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('desktop_dump 输出屏幕文本地图', () async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
    AgentResult? r;
    for (var i = 0; i < 2; i++) {
      r = await AgentRunner.execute(
        AgentToolCall(tool: 'desktop_dump', args: ''),
      );
      if (r.output.contains('SCREEN')) break;
    }
    if (!r!.output.contains('SCREEN')) {
      markTestSkipped('当前环境 UIA 扫描不可用：${r.output}');
      return;
    }
    expect(r.output, contains('SCREEN'));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('跨平台适配器支持状态', () {
    expect(
      DesktopControl.supported,
      Platform.isWindows || Platform.isMacOS || Platform.isLinux,
    );
  });
}
