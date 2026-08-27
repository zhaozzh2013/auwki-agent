import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_agent_path_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('writefile 相对路径基于 cwd 解析', () async {
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'writefile', args: 'sub/a.txt|||hello'),
      cwd: tmp.path,
    );
    expect(r.error, isNull, reason: r.error);
    expect(File('${tmp.path}/sub/a.txt').existsSync(), isTrue);
    expect(
      File('${tmp.path}/sub/a.txt').readAsStringSync(),
      'hello',
    );
  });

  test('writefile 拒绝越出工作目录的路径', () async {
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'writefile', args: '../evil.txt|||x'),
      cwd: tmp.path,
    );
    expect(r.output, contains('拦截'));
    expect(File('${tmp.parent.path}/evil.txt').existsSync(), isFalse);
  });

  test('writefile 拒绝写敏感路径', () async {
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'writefile', args: '.env|||SECRET=1'),
      cwd: tmp.path,
    );
    expect(r.output, contains('拦截'));
  });
}
