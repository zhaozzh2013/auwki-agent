import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/round_changes.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('round_changes_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('检测新增 / 修改 / 删除，并统计行数', () async {
    final a = File('${tmp.path}/a.txt')..writeAsStringSync('1\n2\n3\n');
    File('${tmp.path}/b.txt').writeAsStringSync('x\ny\n');

    final before = await WorkspaceSnapshot.capture(rootPath: tmp.path);

    a.writeAsStringSync('1\n3\n4\n5\n');
    File('${tmp.path}/b.txt').deleteSync();
    File('${tmp.path}/d.txt').writeAsStringSync('n1\nn2\n');

    final after = await WorkspaceSnapshot.capture(rootPath: tmp.path);
    final changes = before.diff(after);
    final byPath = {for (final c in changes) c.path: c};

    expect(byPath['a.txt']?.added, 2);
    expect(byPath['a.txt']?.removed, 1);
    expect(byPath['b.txt']?.deleted, true);
    expect(byPath['d.txt']?.added, 2);
    expect(byPath['d.txt']?.removed, 0);
  });

  test('无变化时 diff 为空', () async {
    final before = await WorkspaceSnapshot.capture(rootPath: tmp.path);
    final after = await WorkspaceSnapshot.capture(rootPath: tmp.path);
    expect(before.diff(after), isEmpty);
  });

  test('路径归一化：./ 与反斜杠', () {
    expect(WorkspaceSnapshot.normalizePath('./a.txt', base: 'C:/x'), 'a.txt');
    expect(
      WorkspaceSnapshot.normalizePath(r'C:\x\sub\a.txt', base: 'C:/x'),
      'sub/a.txt',
    );
    expect(
      WorkspaceSnapshot.normalizePath(r'C:\x\a.txt', base: r'C:\x'),
      'a.txt',
    );
  });
}
