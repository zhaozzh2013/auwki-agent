import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  test('A20: zip and unzip roundtrip', () async {
    // Windows 的 tar 即 bsdtar；Linux/macOS 需要 bsdtar 才能处理 zip，
    // 缺失时跳过（agent 会回退为仅 tar.gz 支持）。
    if (!Platform.isWindows) {
      final p = await Process.run('sh', ['-c', 'command -v bsdtar']);
      if (p.exitCode != 0) {
        markTestSkipped('bsdtar 不可用，跳过集成用例');
        return;
      }
    }
    final tmp = Directory.systemTemp.createTempSync('auwki_zip_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final src = File('${tmp.path}/hello.txt');
    await src.writeAsString('hello zip');
    final archive = '${tmp.path}/out.zip';
    final dest = '${tmp.path}/out';

    final z = await AgentRunner.execute(
      AgentToolCall(tool: 'zip', args: 'hello.txt|||out.zip'),
      cwd: tmp.path,
    );
    expect(z.ok, isTrue, reason: z.error);
    expect(File(archive).existsSync(), isTrue);

    final u = await AgentRunner.execute(
      AgentToolCall(tool: 'unzip', args: 'out.zip|||out'),
      cwd: tmp.path,
    );
    expect(u.ok, isTrue, reason: u.error);
    expect(File('$dest/hello.txt').existsSync(), isTrue);
    expect(
      await File('$dest/hello.txt').readAsString(),
      'hello zip',
    );
  });
}
