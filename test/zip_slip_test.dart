import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  test('isUnsafeZipEntry 识别 zip-slip/绝对路径/盘符', () {
    expect(AgentRunner.isUnsafeZipEntry('a/b.txt'), isFalse);
    expect(AgentRunner.isUnsafeZipEntry('folder/'), isFalse);
    expect(AgentRunner.isUnsafeZipEntry('../evil.txt'), isTrue);
    expect(AgentRunner.isUnsafeZipEntry('a/../../evil.txt'), isTrue);
    expect(AgentRunner.isUnsafeZipEntry('/etc/passwd'), isTrue);
    expect(AgentRunner.isUnsafeZipEntry(r'C:\windows\evil.txt'), isTrue);
    expect(AgentRunner.isUnsafeZipEntry(r'a\..\evil.txt'), isTrue);
  });

  test('解压含 ../ 条目的 zip 被拒绝且不越界写文件', () async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    final tmp = Directory.systemTemp.createTempSync('auwki_zip_slip');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final archive = '${tmp.path}/evil.zip';
    final py = r'''
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('../../evil.txt', 'pwned')
''';
    final made = await Process.run('python', ['-c', py, archive]);
    if (made.exitCode != 0) {
      markTestSkipped('python 不可用，跳过集成用例');
      return;
    }
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'unzip', args: 'evil.zip|||out'),
      cwd: tmp.path,
    );
    expect('${r.error}${r.output}', contains('unsafe'));
    expect(File('${tmp.path}/evil.txt').existsSync(), isFalse);
  });
}
