import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';
import 'package:auwki_agent/services/agent_runtime.dart';
import 'package:auwki_agent/services/audit_service.dart';
import 'package:auwki_agent/services/settings_store.dart';
import 'package:auwki_agent/services/tool_cache.dart';

void main() {
  late Directory tmp;
  late SettingsStore settings;
  late ToolRuntime runtime;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_tool_runtime_test');
    settings = SettingsStore();
    runtime = ToolRuntime(settings: settings);
  });

  tearDown(() async {
    AuditService.debugFile = null;
    await ToolCache.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('A03: disabled tool is rejected and not executed', () async {
    await settings.setToolEnabled('command', false);
    expect(runtime.isEnabled('command'), isFalse);
    final r = await runtime.execute(
      AgentToolCall(tool: 'command', args: 'echo hi'),
      cwd: tmp.path,
    );
    expect(r.ok, isFalse);
    expect(r.error, isNotNull);
  });

  test('A08: permission rule denies command prefix', () async {
    await settings.setPermissionRules([
      {
        'tool': 'command',
        'allow': true,
        'commandDenyPrefixes': ['rm'],
      },
    ]);
    final r = await runtime.execute(
      AgentToolCall(tool: 'command', args: 'rm -rf x'),
      cwd: tmp.path,
      commandConfirmed: true,
    );
    expect(r.ok, isFalse);
    expect(r.error, contains('rm'));
  });

  test('A19: dry-run previews without side effects', () async {
    await settings.setDryRun(true);
    final r = await runtime.execute(
      AgentToolCall(tool: 'writefile', args: 'x.txt|||hello'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue);
    expect(r.output, isNotEmpty);
    expect(File('${tmp.path}/x.txt').existsSync(), isFalse);
  });

  test('A18: websearch cache hit skips network', () async {
    final cacheFile = File('${tmp.path}/cache.json');
    ToolCache.debugFile = cacheFile;
    await ToolCache.instance.set('websearch', 'flutter', 'cached-result');

    final r = await runtime.execute(
      AgentToolCall(tool: 'websearch', args: 'flutter'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue);
    expect(r.output, contains('cached-result'));
  });

  test('A02: custom tool executes command template', () async {
    await settings.setCustomTools([
      {
        'id': 'echo',
        'name': 'Echo',
        'description': 'echo args',
        'command': 'echo {args}',
        'enabled': true,
      },
    ]);
    expect(runtime.extraToolNames(), contains('echo'));

    final parsed = AgentRunner.parse(
      '[正式输出]\necho("hello world")\n[输出结束]',
      extraTools: {'echo'},
    );
    expect(parsed, hasLength(1));
    expect(parsed.first.tool, 'echo');

    final r = await runtime.execute(parsed.first, cwd: tmp.path);
    expect(r.ok, isTrue, reason: r.error);
    expect(r.output, contains('hello'));
    expect(r.output, contains('world'));
    expect(r.output, contains('[exit 0]'));
  });

  test('A14: audit records tool calls', () async {
    final auditFile = File('${tmp.path}/audit.jsonl');
    AuditService.debugFile = auditFile;
    await settings.setDryRun(true);
    await runtime.execute(
      AgentToolCall(tool: 'listfiles', args: '.'),
      cwd: tmp.path,
      conversationId: 'conv-test',
    );
    final records = await AuditService.instance.recent();
    expect(records, hasLength(1));
    expect(records.first.tool, 'listfiles');
    expect(records.first.dryRun, isTrue);
    expect(records.first.conversationId, 'conv-test');
  });
}
