import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  if (!Platform.isWindows) {
    return;
  }

  test('A20: zip and unzip roundtrip', () async {
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
