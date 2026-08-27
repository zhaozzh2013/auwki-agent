import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// MCP 服务器配置（A01）。
class McpServerConfig {
  McpServerConfig({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.enabled = true,
  });

  final String id;
  final String name;
  final String command;
  final List<String> args;
  final bool enabled;

  factory McpServerConfig.fromJson(Map<String, dynamic> m) => McpServerConfig(
    id: (m['id'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    command: (m['command'] ?? '').toString(),
    args: (m['args'] as List?)?.whereType<String>().toList() ?? const [],
    enabled: m['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'command': command,
    'args': args,
    'enabled': enabled,
  };
}

/// 一个 MCP 工具。
class McpToolInfo {
  McpToolInfo({required this.serverId, required this.name, this.description});

  final String serverId;
  final String name;
  final String? description;
}

/// MCP 客户端（A01）：stdio + JSON-RPC 2.0（换行分隔）。
class _McpClient {
  _McpClient(this.config);

  final McpServerConfig config;
  Process? _process;
  int _nextId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  String? error;

  bool get running => _process != null;

  Future<void> start() async {
    final cmd = config.command.trim();
    if (cmd.isEmpty) {
      error = 'empty command';
      return;
    }
    try {
      final proc = await Process.start(cmd, config.args);
      _process = proc;
      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine, onError: (_) {});
      proc.stderr.transform(utf8.decoder).listen((s) {});
      proc.exitCode.then((_) {
        final p = _process;
        if (identical(p, proc)) _process = null;
        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(StateError('MCP server exited'));
          }
        }
        _pending.clear();
      });
    } catch (e) {
      error = '$e';
      _process = null;
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final msg = jsonDecode(line) as Map<String, dynamic>;
      final id = msg['id'];
      if (id is int && _pending.containsKey(id)) {
        final completer = _pending.remove(id)!;
        if (msg.containsKey('error')) {
          completer.completeError(
            StateError((msg['error'] as Map?)?['message']?.toString() ?? 'rpc error'),
          );
        } else {
          completer.complete(msg);
        }
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final proc = _process;
    if (proc == null) throw StateError('MCP server not running: ${error ?? config.id}');
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    proc.stdin.writeln(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      }),
    );
    return completer.future.timeout(const Duration(seconds: 10));
  }

  Future<void> initialize() async {
    await _request('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'AUWKI Agent', 'version': '2.0.0'},
    });
    _notify('notifications/initialized');
  }

  void _notify(String method, [Map<String, dynamic> params = const {}]) {
    final proc = _process;
    if (proc == null) return;
    proc.stdin.writeln(
      jsonEncode({'jsonrpc': '2.0', 'method': method, 'params': params}),
    );
  }

  Future<List<McpToolInfo>> listTools() async {
    final res = await _request('tools/list', {});
    final tools = (res['result'] as Map?)?['tools'] as List? ?? const [];
    return [
      for (final t in tools)
        if (t is Map)
          McpToolInfo(
            serverId: config.id,
            name: (t['name'] ?? '').toString(),
            description: t['description']?.toString(),
          ),
    ];
  }

  Future<String> callTool(String name, String rawArgs) async {
    Map<String, dynamic> arguments;
    try {
      final decoded = jsonDecode(rawArgs);
      arguments = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : {'text': rawArgs};
    } catch (_) {
      arguments = {'text': rawArgs};
    }
    final res = await _request('tools/call', {'name': name, 'arguments': arguments});
    final content = (res['result'] as Map?)?['content'] as List? ?? const [];
    final buf = StringBuffer();
    for (final c in content) {
      if (c is Map && (c['type'] ?? '') == 'text') {
        buf.writeln((c['text'] ?? '').toString());
      }
    }
    final isError = (res['result'] as Map?)?['isError'] == true;
    final text = buf.toString().trim();
    if (isError) throw StateError(text.isEmpty ? 'MCP tool error' : text);
    return text;
  }

  Future<void> close() async {
    final proc = _process;
    _process = null;
    try {
      proc?.kill();
    } catch (_) {}
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('MCP closed'));
    }
    _pending.clear();
  }
}

/// MCP 服务（A01）：管理多个服务器，暴露 `mcp_<server>_<tool>` 工具。
class McpService extends ChangeNotifier {
  McpService._();

  static final McpService instance = McpService._();

  final Map<String, _McpClient> _clients = {};
  final Map<String, List<McpToolInfo>> _toolsByServer = {};
  List<McpServerConfig> _configs = const [];
  bool _started = false;

  /// 配置变更时重建；未变更时复用已启动的客户端。
  Future<void> ensureReady(List<Map<String, dynamic>> rawServers) async {
    final next = [
      for (final m in rawServers) McpServerConfig.fromJson(m),
    ];
    final same =
        _configs.length == next.length &&
        _configs.every(
          (a) =>
              next.any(
                (b) =>
                    a.id == b.id &&
                    a.command == b.command &&
                    a.enabled == b.enabled &&
                    listEquals(a.args, b.args),
              ),
        );
    if (same && _started) return;
    await stopAll();
    _configs = next;
    _started = true;
    for (final cfg in _configs) {
      if (!cfg.enabled) continue;
      final client = _McpClient(cfg);
      _clients[cfg.id] = client;
      try {
        await client.start();
        await client.initialize();
        _toolsByServer[cfg.id] = await client.listTools();
      } catch (e) {
        client.error = '$e';
        _toolsByServer[cfg.id] = const [];
      }
    }
    notifyListeners();
  }

  List<McpToolInfo> availableTools() => [
    for (final list in _toolsByServer.values) ...list,
  ];

  String fullName(McpToolInfo t) => 'mcp_${t.serverId}_${t.name}';

  bool isMcpTool(String full) {
    for (final t in availableTools()) {
      if (fullName(t) == full) return true;
    }
    return false;
  }

  Future<String> callTool(String full, String rawArgs) async {
    for (final entry in _toolsByServer.entries) {
      for (final t in entry.value) {
        if (fullName(t) == full) {
          final client = _clients[entry.key];
          if (client == null) throw StateError('MCP client missing');
          return client.callTool(t.name, rawArgs);
        }
      }
    }
    throw StateError('MCP tool not found: $full');
  }

  String describeToolsForPrompt() {
    final lines = <String>[];
    for (final t in availableTools()) {
      lines.add(
        '- ${fullName(t)}: ${t.description?.trim().isNotEmpty == true ? t.description : 'MCP tool'}',
      );
    }
    if (lines.isEmpty) return '';
    return '## MCP Tools\n${lines.join('\n')}';
  }

  Future<void> stopAll() async {
    for (final c in _clients.values) {
      await c.close();
    }
    _clients.clear();
    _toolsByServer.clear();
    _started = false;
  }

  /// 测试用：关闭并清空状态。
  Future<void> resetForTest() async {
    await stopAll();
    _configs = const [];
  }
}
