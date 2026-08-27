import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  late Directory tmp;
  late Directory extra;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_extra_ws_test');
    extra = Directory.systemTemp.createTempSync('auwki_extra_ws_extra');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    if (extra.existsSync()) extra.deleteSync(recursive: true);
  });

  test('A12: extraAllowedDirs permits writes outside cwd', () async {
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'writefile', args: 'x.txt|||hello'),
      cwd: tmp.path,
      extraAllowedDirs: [extra.path],
    );
    // 相对路径基于 cwd，仍然只落在 cwd 内；改用绝对路径验证附加目录。
    expect(r.ok, isTrue, reason: r.error);

    final r2 = await AgentRunner.execute(
      AgentToolCall(
        tool: 'writefile',
        args: '${extra.path.replaceAll('\\', '/')}/y.txt|||hi',
      ),
      cwd: tmp.path,
      extraAllowedDirs: [extra.path],
    );
    expect(r2.ok, isTrue, reason: r2.error);
    expect(File('${extra.path}/y.txt').existsSync(), isTrue);
  });

  test('A12: without extra dirs the absolute write is blocked', () async {
    final target = Platform.isWindows
        ? '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}/System32/auwki_blocked/z.txt'
        : '/etc/auwki_blocked/z.txt';
    final r = await AgentRunner.execute(
      AgentToolCall(
        tool: 'writefile',
        args: '$target|||hi',
      ),
      cwd: tmp.path,
    );
    expect(r.output, contains('拦截'));
    expect(File(target).existsSync(), isFalse);
  });
}
