import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/workspace_manager.dart';

void main() {
  test('defaultWorkspacePath 使用 conversations/日期/哈希/workspace 结构', () {
    final path = WorkspaceManager.defaultWorkspacePath('c_test123');
    final parts = path.split('/');
    expect(parts.length, greaterThanOrEqualTo(5));
    expect(parts, contains('conversations'));
    expect(parts.last, 'workspace');
    final datePart = parts[parts.length - 3];
    expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(datePart), isTrue);
  });

  test('shortHash 稳定、定长且不同输入大概率不同', () {
    final a = WorkspaceManager.shortHash('c_1');
    final b = WorkspaceManager.shortHash('c_2');
    expect(a, isNot(b));
    expect(WorkspaceManager.shortHash('c_1'), a);
    expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(a), isTrue);
  });

  test('ensure 递归创建目录', () async {
    final tmp = Directory.systemTemp.createTempSync('workspace_mgr_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final target = '${tmp.path}/a/b/c';
    await WorkspaceManager.ensure(target);
    expect(Directory(target).existsSync(), isTrue);
  });
}
