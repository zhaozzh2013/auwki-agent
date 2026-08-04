import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/git_service.dart';

Future<bool> _gitAvailable() async {
  try {
    final r = await Process.run('git', ['--version']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

Future<void> _git(List<String> args) async {
  final r = await Process.run('git', args);
  if (r.exitCode != 0) {
    throw StateError('git ${args.join(' ')} failed: ${r.stderr}');
  }
}

void main() {
  final gitAvailable = _gitAvailable();
  late Directory tmp;
  late Directory oldCwd;

  setUp(() async {
    if (!await gitAvailable) return;
    tmp = Directory.systemTemp.createTempSync('git_service_test');
    oldCwd = Directory.current;
    Directory.current = tmp;
    await _git(['init', '-q']);
    await _git(['config', 'user.email', 'test@auwki.local']);
    await _git(['config', 'user.name', 'test']);
    GitService.resetRepoRootCache();
  });

  tearDown(() async {
    if (!await gitAvailable) return;
    Directory.current = oldCwd;
    GitService.resetRepoRootCache();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('status / stage / commit / discard / revert 全流程', () async {
    if (!await gitAvailable) return;

    File('a.txt').writeAsStringSync('1\n2\n3\n');
    await _git(['add', '-A']);
    await _git(['commit', '-m', 'init']);

    File('a.txt').writeAsStringSync('1\n2\n3\n4\n');
    File('new.txt').writeAsStringSync('n1\nn2\n');

    final st = await GitService.status();
    expect(st.branch, isNotNull);
    final paths = st.files.map((f) => f.path).toSet();
    expect(paths, contains('a.txt'));
    expect(paths, contains('new.txt'));
    expect(st.files.firstWhere((f) => f.path == 'new.txt').untracked, isTrue);

    await GitService.stageAll();
    final st2 = await GitService.status();
    expect(st2.files.every((f) => f.staged || f.untracked), isTrue);

    await GitService.commit('test commit');
    final log = await GitService.log(count: 5);
    expect(log.first.message, 'test commit');

    File('a.txt').writeAsStringSync('1\n2\n3\n4\n5\n');
    await GitService.discard(['a.txt']);
    final st3 = await GitService.status();
    expect(
      st3.files.where((f) => f.path == 'a.txt'),
      isEmpty,
    );

    await GitService.revertCommit(log.first.hash);
    final log2 = await GitService.log(count: 5);
    expect(log2.length, log.length + 1);
  });

  test('initRepo 在非仓库目录创建仓库', () async {
    if (!await gitAvailable) return;
    final target = Directory.systemTemp.createTempSync('git_init_target');
    addTearDown(() {
      if (target.existsSync()) target.deleteSync(recursive: true);
    });

    final before = await GitService.repoRoot(path: target.path);
    expect(before, isNull);

    await GitService.initRepo(target.path);
    final after = await GitService.repoRoot(path: target.path);
    expect(after, isNotNull);
    final st = await GitService.status(path: target.path);
    expect(st.branch, isNotNull);
  });
}
