import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';
import 'package:auwki_agent/services/agent_runtime.dart';
import 'package:auwki_agent/services/mcp_service.dart';
import 'package:auwki_agent/services/settings_store.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('auwki_mcp_test');
  });

  tearDown(() async {
    await McpService.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  bool pythonAvailable() {
    try {
      final r = Process.runSync('python', ['--version']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  test('A01: MCP tools are listed and callable', () async {
    if (!pythonAvailable()) return;
    final fixture = File('test/fixtures/mcp_echo_server.py').absolute.path;
    final settings = SettingsStore();
    await settings.setMcpServers([
      {
        'id': 'echo',
        'name': 'Echo',
        'command': 'python',
        'args': ['-u', fixture],
        'enabled': true,
      },
    ]);

    await McpService.instance.ensureReady(settings.mcpServers);
    final tools = McpService.instance.availableTools();
    expect(tools, hasLength(1));
    final full = McpService.instance.fullName(tools.first);
    expect(full, 'mcp_echo_echo');

    final result = await McpService.instance.callTool(full, 'hello');
    expect(result, 'echo:hello');
  });

  test('A01: ToolRuntime dispatches MCP tool calls', () async {
    if (!pythonAvailable()) return;
    final fixture = File('test/fixtures/mcp_echo_server.py').absolute.path;
    final settings = SettingsStore();
    await settings.setMcpServers([
      {
        'id': 'echo',
        'name': 'Echo',
        'command': 'python',
        'args': ['-u', fixture],
        'enabled': true,
      },
    ]);
    final runtime = ToolRuntime(settings: settings);
    final names = await runtime.extraToolNamesAsync();
    expect(names, contains('mcp_echo_echo'));

    final r = await runtime.execute(
      AgentToolCall(tool: 'mcp_echo_echo', args: 'world'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(r.output, 'echo:world');
  });
}
