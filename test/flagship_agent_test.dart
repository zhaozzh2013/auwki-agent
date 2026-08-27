import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

Stream<String> _s(String text) => Stream.fromIterable([text]);

void main() {
  test('flagshipAgentTaskMessage 包含任务、备注与思维链要求', () {
    final zh = AgentRunner.flagshipAgentTaskMessage(
      focus: '检查风险',
      coordinatorNote: '注意安全',
      isEnglish: false,
    );
    expect(zh, contains('检查风险'));
    expect(zh, contains('注意安全'));
    expect(zh, contains('思维链'));
  });

  test('runFlagshipAgent 支持子代理调用工具并继续思考', () async {
    final tmp = Directory.systemTemp.createTempSync('subagent_tool_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    var calls = 0;
    Stream<String> chat(
      String system,
      List<Map<String, dynamic>> messages,
    ) {
      calls++;
      if (calls == 1) {
        return _s('[正式输出]\nwritefile("sub/a.txt|||hello")\n[输出结束]');
      }
      return _s('已完成，文件已创建。');
    }

    final outcome = await AgentRunner.runFlagshipAgent(
      chat: chat,
      systemPrompt: 'test-system',
      messages: [
        <String, dynamic>{'role': 'user', 'content': 'task'},
      ],
      cwd: tmp.path,
    );

    expect(outcome.ok, isTrue);
    expect(outcome.output, contains('已完成'));
    expect(outcome.thinking, contains('正式输出'));
    expect(outcome.toolTrace, contains('writefile'));
    expect(File('${tmp.path}/sub/a.txt').existsSync(), isTrue);
    expect(calls, 2);
  });

  test('runFlagshipAgent 子代理禁止 command 工具', () async {
    final tmp = Directory.systemTemp.createTempSync('subagent_cmd_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    var calls = 0;
    Stream<String> chat(
      String system,
      List<Map<String, dynamic>> messages,
    ) {
      calls++;
      if (calls == 1) {
        return _s('[正式输出]\ncommand("whoami")\n[输出结束]');
      }
      return _s('完成。');
    }

    final outcome = await AgentRunner.runFlagshipAgent(
      chat: chat,
      systemPrompt: 'test-system',
      messages: [
        <String, dynamic>{'role': 'user', 'content': 'task'},
      ],
      cwd: tmp.path,
    );

    expect(outcome.ok, isTrue);
    expect(outcome.toolTrace, contains('拦截'));
    expect(outcome.output, isNotEmpty);
  });
  test('H：子代理一次响应多个工具并行执行且结果齐全', () async {
    final tmp = Directory.systemTemp.createTempSync('subagent_parallel');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    File('${tmp.path}/a.txt').writeAsStringSync('AAA');
    File('${tmp.path}/b.txt').writeAsStringSync('BBB');

    var calls = 0;
    Stream<String> chat(
      String system,
      List<Map<String, dynamic>> messages,
    ) {
      calls++;
      if (calls == 1) {
        return _s('[正式输出]\n'
            'readfile("a.txt")\n'
            'readfile("b.txt")\n'
            '[输出结束]');
      }
      return _s('两个文件都读完了，内容分别是 AAA 和 BBB。');
    }

    final outcome = await AgentRunner.runFlagshipAgent(
      chat: chat,
      systemPrompt: 'test-system',
      messages: [
        <String, dynamic>{'role': 'user', 'content': 'read both files'},
      ],
      cwd: tmp.path,
    );

    expect(outcome.ok, isTrue);
    // 两个工具的结果都被记录且带文件名
    expect(outcome.toolTrace, contains('readfile("a.txt")'));
    expect(outcome.toolTrace, contains('readfile("b.txt")'));
    expect(outcome.toolTrace, contains('AAA'));
    expect(outcome.toolTrace, contains('BBB'));
    expect(calls, 2);
  });
}
