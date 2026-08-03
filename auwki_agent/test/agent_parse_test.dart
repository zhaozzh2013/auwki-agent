import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  test('解析同一行多个 writefile 调用', () {
    const text =
        '[正式输出]\nwritefile("./a.txt|||x") writefile("./b.txt|||y")\n[输出结束]';
    final calls = AgentRunner.parse(text);
    expect(calls, hasLength(2));
    expect(calls[0].tool, 'writefile');
    expect(calls[0].args, './a.txt|||x');
    expect(calls[1].args, './b.txt|||y');
  });

  test('参数内未转义双引号也能解析', () {
    const text =
        '[正式输出]\nwritefile("./p/pyproject.toml|||[build-system]\nrequires = ["setuptools", "wheel"]") [输出结束]';
    final calls = AgentRunner.parse(text);
    expect(calls, hasLength(1));
    expect(calls[0].args, contains('setuptools'));
    expect(calls[0].args, contains('wheel'));
  });

  test('支持代码围栏包裹的工具块', () {
    const text =
        '[正式输出]\n```\nreadfile("./README.md")\n```\n[输出结束]';
    final calls = AgentRunner.parse(text);
    expect(calls, hasLength(1));
    expect(calls[0].tool, 'readfile');
  });

  test('无工具块时返回空', () {
    expect(AgentRunner.parse('只是一段普通回答'), isEmpty);
  });

  test('hasToolBlock 检测存在但解析失败的块', () {
    expect(AgentRunner.hasToolBlock('[正式输出] 格式坏了'), isTrue);
    expect(AgentRunner.hasToolBlock('普通文本'), isFalse);
  });

  test('未知工具被忽略', () {
    const text = '[正式输出]\nunknown_tool("./x")\n[输出结束]';
    expect(AgentRunner.parse(text), isEmpty);
  });
}
