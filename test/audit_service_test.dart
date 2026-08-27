import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/audit_service.dart';

void main() {
  late Directory tmp;
  late File auditFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_audit_test');
    auditFile = File('${tmp.path}/audit.jsonl');
    AuditService.debugFile = auditFile;
  });

  tearDown(() {
    AuditService.debugFile = null;
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('record appends and recent returns newest first', () async {
    await AuditService.instance.record(
      tool: 'webfetch',
      args: 'https://example.com',
      ok: true,
      output: 'body',
    );
    await AuditService.instance.record(
      tool: 'command',
      args: 'echo hi',
      ok: false,
      denied: true,
      conversationId: 'c1',
    );

    final records = await AuditService.instance.recent();
    expect(records, hasLength(2));
    expect(records.first.tool, 'command');
    expect(records.first.denied, isTrue);
    expect(records.last.tool, 'webfetch');
  });

  test('export writes full log and clear empties it', () async {
    await AuditService.instance.record(
      tool: 'websearch',
      args: 'flutter',
      ok: true,
    );
    final exportFile = File('${tmp.path}/export.jsonl');
    await AuditService.instance.exportTo(exportFile.path);
    expect(exportFile.existsSync(), isTrue);
    expect((await exportFile.readAsLines()), hasLength(1));

    await AuditService.instance.clear();
    expect(await AuditService.instance.recent(), isEmpty);
  });
}
