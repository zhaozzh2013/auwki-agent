import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/git_service.dart';

void main() {
  late Directory repo;

  setUp(() async {
    repo = Directory.systemTemp.createTempSync('auwki_git_enh');
    await Process.run('git', ['init'], workingDirectory: repo.path);
    await Process.run(
      'git',
      ['config', 'user.email', 'test@example.com'],
      workingDirectory: repo.path,
    );
    await Process.run(
      'git',
      ['config', 'user.name', 'Test'],
      workingDirectory: repo.path,
    );
    final f = File('${repo.path}/a.txt');
    await f.writeAsString('one');
    await GitService.stage(['a.txt'], path: repo.path);
    await GitService.commit('first commit', path: repo.path);
  });

  tearDown(() {
    if (repo.existsSync()) repo.deleteSync(recursive: true);
  });

  test('D01: create/switch/delete branches', () async {
    await GitService.createBranch('feature', path: repo.path);
    expect(await GitService.branches(path: repo.path), contains('feature'));

    await GitService.switchBranch('feature', path: repo.path);
    expect((await GitService.status(path: repo.path)).branch, 'feature');

    await GitService.switchBranch('master', path: repo.path);
    await GitService.deleteBranch('feature', path: repo.path);
    expect(await GitService.branches(path: repo.path), isNot(contains('feature')));
  });

  test('D02: fileDiff shows working changes', () async {
    final f = File('${repo.path}/a.txt');
    await f.writeAsString('one\ntwo');
    final diff = await GitService.fileDiff('a.txt', path: repo.path);
    expect(diff, contains('+two'));
  });

  test('D04: graph renders commit lines', () async {
    final g = await GitService.graph(count: 5, path: repo.path);
    expect(g, contains('first commit'));
  });

  test('D05: author and daily stats', () async {
    final authors = await GitService.authorStats(path: repo.path);
    expect(authors.values.fold<int>(0, (a, b) => a + b), greaterThanOrEqualTo(1));
    final daily = await GitService.dailyStats(path: repo.path);
    expect(daily, isNotEmpty);
  });

  test('D08: file history and per-version diff', () async {
    final f = File('${repo.path}/a.txt');
    await f.writeAsString('one\ntwo');
    await GitService.stage(['a.txt'], path: repo.path);
    await GitService.commit('second commit', path: repo.path);

    final log = await GitService.fileLog('a.txt', path: repo.path);
    expect(log, contains('second commit'));

    final hashes = log.split('\n').map((l) => l.split(' ').first).toList();
    expect(hashes.length, greaterThanOrEqualTo(2));
    final diff = await GitService.fileDiffBetween(
      'a.txt',
      hashes[1],
      hashes[0],
      path: repo.path,
    );
    expect(diff, contains('one'));
  });

  test('D09: gitignore read/write', () async {
    await GitService.writeGitignore('build/\n*.log\n', path: repo.path);
    expect(await GitService.readGitignore(path: repo.path), contains('build/'));
  });

  test('D07: fetch against local bare remote', () async {
    final bare = Directory.systemTemp.createTempSync('auwki_git_bare');
    addTearDown(() {
      if (bare.existsSync()) bare.deleteSync(recursive: true);
    });
    await Process.run('git', ['init', '--bare', bare.path]);
    await Process.run(
      'git',
      ['remote', 'add', 'origin', bare.path],
      workingDirectory: repo.path,
    );
    await Process.run(
      'git',
      ['push', '-u', 'origin', 'master'],
      workingDirectory: repo.path,
    );
    final out = await GitService.fetch(path: repo.path);
    expect(out, isA<String>());
  });
}
