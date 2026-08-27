import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:auwki_agent/services/agent.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_sql_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('A11: sql tool runs read-only SELECT on SQLite', () async {
    final dbFile = File('${tmp.path}/test.db');
    final db = sqlite3.open(dbFile.path);
    db.execute('CREATE TABLE t (id INTEGER, name TEXT)');
    db.execute("INSERT INTO t VALUES (1, 'Alice')");
    db.execute("INSERT INTO t VALUES (2, 'Bob')");
    db.dispose();

    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'sql', args: 'test.db|||SELECT * FROM t'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(r.output, contains('Alice'));
    expect(r.output, contains('Bob'));
  });

  test('A11: sql tool rejects non-readonly queries', () async {
    final dbFile = File('${tmp.path}/test.db');
    final db = sqlite3.open(dbFile.path);
    db.execute('CREATE TABLE t (id INTEGER)');
    db.dispose();

    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'sql', args: 'test.db|||DELETE FROM t'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue); // 拦截信息以 output 返回
    expect(r.output, contains('只读'));
  });

  test('A11: sql tool reads CSV', () async {
    final csv = File('${tmp.path}/data.csv');
    await csv.writeAsString('id,name\n1,Alice\n2,Bob\n');
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'sql', args: 'data.csv|||SELECT *'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(r.output, contains('Alice'));
  });
}
