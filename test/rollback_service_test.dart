import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/rollback_service.dart';
import 'package:auwki_agent/services/round_changes.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_rollback_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('A07: rollback restores modified files and removes new files', () async {
    final f = File('${tmp.path}/a.txt');
    await f.writeAsString('original');

    final before = await WorkspaceSnapshot.capture(rootPath: tmp.path);
    RollbackService.instance.capture('c1', before, baseDir: tmp.path);

    await f.writeAsString('changed');
    final newFile = File('${tmp.path}/new.txt');
    await newFile.writeAsString('new content');
    RollbackService.instance.recordCreated(
      'c1',
      tmp.path,
      {'new.txt': {'created'}},
    );

    final count = await RollbackService.instance.rollback('c1');
    expect(count, 2);
    expect(await f.readAsString(), 'original');
    expect(await newFile.exists(), isFalse);
  });

  test('A07: no snapshot returns zero', () async {
    expect(await RollbackService.instance.rollback('missing'), 0);
  });

  test('A07: 空文件快照回滚为恢复空文件而非删除', () async {
    final f = File('${tmp.path}/empty.txt');
    await f.writeAsString('');

    final before = await WorkspaceSnapshot.capture(rootPath: tmp.path);
    RollbackService.instance.capture('c_empty', before, baseDir: tmp.path);

    await f.writeAsString('not empty anymore');
    final count = await RollbackService.instance.rollback('c_empty');
    expect(count, 1);
    expect(await f.exists(), isTrue);
    expect(await f.readAsString(), '');
  });
}
