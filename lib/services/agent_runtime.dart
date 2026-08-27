import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../i18n/strings.dart';
import 'agent.dart';
import 'audit_service.dart';
import 'diff_preview.dart';
import 'mcp_service.dart';
import 'settings_store.dart';
import 'tool_cache.dart';

/// 自定义工具定义（A02）。
class CustomToolDef {
  CustomToolDef({
    required this.id,
    required this.name,
    required this.description,
    required this.command,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;
  final String command;
  final bool enabled;

  factory CustomToolDef.fromJson(Map<String, dynamic> m) => CustomToolDef(
    id: (m['id'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    description: (m['description'] ?? '').toString(),
    command: (m['command'] ?? '').toString(),
    enabled: m['enabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'command': command,
    'enabled': enabled,
  };
}

/// 权限规则（A08）：按工具 + 命令/路径前缀白名单/黑名单。
class PermissionRule {
  PermissionRule({
    this.tool = '*',
    this.allow = true,
    this.commandAllowPrefixes = const [],
    this.commandDenyPrefixes = const [],
    this.pathAllowPrefixes = const [],
    this.pathDenyPrefixes = const [],
  });

  final String tool;
  final bool allow;
  final List<String> commandAllowPrefixes;
  final List<String> commandDenyPrefixes;
  final List<String> pathAllowPrefixes;
  final List<String> pathDenyPrefixes;

  factory PermissionRule.fromJson(Map<String, dynamic> m) => PermissionRule(
    tool: (m['tool'] ?? '*').toString(),
    allow: m['allow'] as bool? ?? true,
    commandAllowPrefixes: _stringList(m['commandAllowPrefixes']),
    commandDenyPrefixes: _stringList(m['commandDenyPrefixes']),
    pathAllowPrefixes: _stringList(m['pathAllowPrefixes']),
    pathDenyPrefixes: _stringList(m['pathDenyPrefixes']),
  );

  Map<String, dynamic> toJson() => {
    'tool': tool,
    'allow': allow,
    'commandAllowPrefixes': commandAllowPrefixes,
    'commandDenyPrefixes': commandDenyPrefixes,
    'pathAllowPrefixes': pathAllowPrefixes,
    'pathDenyPrefixes': pathDenyPrefixes,
  };

  static List<String> _stringList(Object? v) =>
      v is List ? v.whereType<String>().toList() : const [];
}

/// 工具运行时（批次 4）：统一执行入口，串起 A02/A03/A08/A14/A18/A19。
class ToolRuntime {
  ToolRuntime({required this.settings});

  final SettingsStore settings;

  static const Set<String> builtInTools = {
    'webfetch',
    'websearch',
    'listfiles',
    'readfile',
    'writefile',
    'replacefile',
    'command',
    'screenshot',
    'sql',
    'zip',
    'unzip',
    'desktop_dump',
    'desktop_click',
    'desktop_type',
    'desktop_key',
    'desktop_open',
    'desktop_scroll',
    'desktop_wait',
    'desktop_ocr',
  };

  static const Set<String> cacheableTools = {'webfetch', 'websearch'};

  static const Set<String> fileTools = {
    'listfiles',
    'readfile',
    'writefile',
    'replacefile',
  };

  List<CustomToolDef> get _customTools => [
    for (final m in settings.customTools) CustomToolDef.fromJson(m),
  ];

  /// 是否启用该工具（A03）。
  bool isEnabled(String tool) {
    if (builtInTools.contains(tool)) return settings.toolEnabled(tool);
    for (final t in _customTools) {
      if (t.id == tool) return t.enabled;
    }
    for (final m in settings.mcpServers) {
      final id = (m['id'] ?? '').toString();
      final enabled = (m['enabled'] as bool?) ?? true;
      if (tool.startsWith('mcp_${id}_')) return enabled;
    }
    return true;
  }

  /// 已启用的自定义工具名，供工具解析器放行。
  Set<String> extraToolNames() =>
      {for (final t in _customTools) if (t.enabled) t.id};

  /// 含 MCP 工具的完整工具名（异步：需先启动 MCP 服务器）。
  Future<Set<String>> extraToolNamesAsync() async {
    await McpService.instance.ensureReady(settings.mcpServers);
    return {
      ...extraToolNames(),
      for (final t in McpService.instance.availableTools())
        McpService.instance.fullName(t),
    };
  }

  /// 生成追加到系统提示词的自定义工具说明。
  static String describeExtraTools(SettingsStore s) {
    final lines = <String>[];
    for (final m in s.customTools) {
      final id = (m['id'] ?? '').toString().trim();
      final desc = (m['description'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      lines.add('- $id: ${desc.isEmpty ? 'custom tool' : desc}');
    }
    if (lines.isEmpty) return '';
    return '## Extra Tools\n${lines.join('\n')}\n'
        'Use them with the same tool block syntax.';
  }

  /// 自定义工具 + MCP 工具的系统提示词片段。
  Future<String> describeExtraToolsAsync() async {
    final parts = <String>[
      describeExtraTools(settings),
      await McpService.instance.ensureReady(settings.mcpServers).then(
        (_) => McpService.instance.describeToolsForPrompt(),
      ),
    ].where((s) => s.isNotEmpty).toList();
    return parts.join('\n\n');
  }

  /// 权限检查（A08）：返回拒绝原因，null 表示放行。
  String? permissionDenyReason(AgentToolCall call, String? cwd) {
    for (final raw in settings.permissionRules) {
      final rule = PermissionRule.fromJson(raw);
      if (rule.tool != '*' && rule.tool != call.tool) continue;
      final isCommandScope = rule.tool == 'command' || rule.tool == '*';
      final isPathScope = fileTools.contains(call.tool) || rule.tool == '*';
      if (isCommandScope && call.tool == 'command') {
        final cmd = call.args.trim().toLowerCase();
        for (final p in rule.commandDenyPrefixes) {
          final prefix = p.trim().toLowerCase();
          if (prefix.isNotEmpty && cmd.startsWith(prefix)) {
            return 'command prefix denied: ${p.trim()}';
          }
        }
        if (!rule.allow && rule.commandAllowPrefixes.isNotEmpty) {
          final allowed = rule.commandAllowPrefixes.any(
            (p) =>
                p.trim().isNotEmpty &&
                cmd.startsWith(p.trim().toLowerCase()),
          );
          if (!allowed) return 'command not in allowlist';
        }
      }
      if (isPathScope && fileTools.contains(call.tool)) {
        final path = call.args.split('|||').first.trim().toLowerCase();
        for (final p in rule.pathDenyPrefixes) {
          final prefix = p.trim().toLowerCase();
          if (prefix.isNotEmpty && path.startsWith(prefix)) {
            return 'path prefix denied: ${p.trim()}';
          }
        }
        if (!rule.allow && rule.pathAllowPrefixes.isNotEmpty) {
          final allowed = rule.pathAllowPrefixes.any(
            (p) =>
                p.trim().isNotEmpty &&
                path.startsWith(p.trim().toLowerCase()),
          );
          if (!allowed) return 'path not in allowlist';
        }
      }
      if (!rule.allow &&
          rule.commandAllowPrefixes.isEmpty &&
          rule.pathAllowPrefixes.isEmpty) {
        return 'tool denied by rule';
      }
    }
    return null;
  }

  /// 统一执行入口。
  ///
  /// [commandConfirmed]：命令已经过用户确认（由调用方弹窗）。
  Future<AgentResult> execute(
    AgentToolCall call, {
    String? cwd,
    String? conversationId,
    bool commandConfirmed = false,
    List<String>? extraAllowedDirs,
    Future<bool> Function(AgentToolCall call, String preview)? onFileConfirm,
  }) async {
    final tool = call.tool;

    if (!isEnabled(tool)) {
      await _audit(call, conversationId, ok: false, output: '', denied: true);
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.tool_disabled', {'tool': tool}),
      );
    }

    final deny = permissionDenyReason(call, cwd);
    if (deny != null) {
      await _audit(call, conversationId, ok: false, output: '', denied: true);
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.permission_denied', {
          'tool': tool,
          'reason': deny,
        }),
      );
    }

    if (settings.dryRun) {
      final preview = _dryPreview(call);
      await _audit(
        call,
        conversationId,
        ok: true,
        output: preview,
        dryRun: true,
      );
      return AgentResult(call: call, output: preview);
    }

    CustomToolDef? custom;
    for (final t in _customTools) {
      if (t.id == tool) {
        custom = t;
        break;
      }
    }
    if (custom != null) {
      final r = await _runCustom(custom, call, cwd);
      await _audit(call, conversationId, ok: r.ok, output: r.error ?? r.output);
      return r;
    }

    await McpService.instance.ensureReady(settings.mcpServers);
    if (McpService.instance.isMcpTool(tool)) {
      try {
        final text = await McpService.instance.callTool(tool, call.args);
        final out = text.isEmpty ? '(empty)' : text;
        await _audit(call, conversationId, ok: true, output: out);
        return AgentResult(call: call, output: out);
      } catch (e) {
        await _audit(call, conversationId, ok: false, output: '$e');
        return AgentResult(call: call, output: '', error: '$e');
      }
    }

    if (!builtInTools.contains(tool)) {
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.error.unknown_tool', {'tool': tool}),
      );
    }

    if (tool == 'command' && !commandConfirmed) {
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.error.command_cancelled', {'command': call.args}),
      );
    }

    final cacheable = cacheableTools.contains(tool) && settings.toolCacheEnabled;
    if (cacheable) {
      final hit = await ToolCache.instance.get(
        tool,
        call.args,
        ttlSeconds: settings.toolCacheTtlSeconds,
      );
      if (hit != null) {
        final out = '${I18n.t('agent.cache.hit')}\n$hit';
        await _audit(call, conversationId, ok: true, output: out);
        return AgentResult(call: call, output: out);
      }
    }

    if ((tool == 'writefile' || tool == 'replacefile') &&
        onFileConfirm != null) {
      final preview = await _filePreview(call, cwd);
      final allow = await onFileConfirm(call, preview);
      if (!allow) {
        final msg = I18n.t('agent.error.file_confirm_cancelled');
        await _audit(call, conversationId, ok: false, output: msg);
        return AgentResult(call: call, output: '', error: msg);
      }
    }

    final r = await AgentRunner.execute(
      call,
      cwd: cwd,
      extraAllowedDirs: extraAllowedDirs,
    );
    if (cacheable && r.ok) {
      await ToolCache.instance.set(tool, call.args, r.output);
    }
    await _audit(call, conversationId, ok: r.ok, output: r.error ?? r.output);
    return r;
  }

  Future<String> _filePreview(AgentToolCall call, String? cwd) async {
    final parts = call.args.split('|||');
    if (parts.isEmpty) return '';
    final path = parts.first.trim();
    if (call.tool == 'writefile') {
      final content = parts.length > 1 ? parts[1] : '';
      return DiffPreview.unified(null, content, path: path);
    }
    final resolved = path.isEmpty
        ? null
        : File(
            path.contains(':') || path.startsWith('/')
                ? path
                : '${(cwd ?? Directory.current.path).replaceAll('\\', '/')}/$path',
          );
    String oldText = '';
    if (resolved != null && await resolved.exists()) {
      try {
        oldText = await resolved.readAsString();
      } catch (_) {}
    }
    final newText = parts.length > 2 ? parts[2] : '';
    return DiffPreview.unified(oldText, newText, path: path);
  }

  Future<AgentResult> _runCustom(
    CustomToolDef def,
    AgentToolCall call,
    String? cwd,
  ) async {
    final template = def.command.trim();
    if (template.isEmpty) {
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.custom.no_command', {'name': def.name}),
      );
    }
    final cmd = template
        .replaceAll('{args}', call.args)
        .replaceAll('{cwd}', cwd ?? Directory.current.path);
    final safety = AgentRunner.validateCommand(cmd);
    if (safety != null) return AgentResult(call: call, output: safety);

    try {
      final proc = await Process.start(
        Platform.isWindows ? 'powershell.exe' : '/bin/sh',
        Platform.isWindows
            ? [
                '-NoProfile',
                '-NonInteractive',
                '-Command',
                '[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; $cmd',
              ]
            : ['-c', cmd],
        workingDirectory: cwd,
      );
      final out = await proc.stdout.transform(utf8.decoder).join();
      final err = await proc.stderr.transform(utf8.decoder).join();
      final code = await proc.exitCode.timeout(const Duration(seconds: 60));
      final buf = StringBuffer();
      if (out.isNotEmpty) buf.write(out);
      if (err.isNotEmpty) {
        if (buf.isNotEmpty) buf.write('\n--- stderr ---\n');
        buf.write(err);
      }
      buf.write('\n[exit $code]');
      var text = buf.toString();
      if (text.length > 8000) {
        text = '${text.substring(0, 8000)}\n...[truncated]';
      }
      return AgentResult(call: call, output: text);
    } on TimeoutException {
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.error.command_timeout', {'command': cmd}),
      );
    } catch (e) {
      return AgentResult(call: call, output: '', error: '$e');
    }
  }

  String _dryPreview(AgentToolCall call) {
    final tool = call.tool;
    final detail = switch (tool) {
      'command' => 'command(${call.args})',
      _ when fileTools.contains(tool) =>
        '$tool(${call.args.split('|||').first.trim()})',
      _ => '$tool(${call.args})',
    };
    return I18n.t('agent.dry_run.preview', {'detail': detail});
  }

  Future<void> _audit(
    AgentToolCall call,
    String? conversationId, {
    required bool ok,
    required String output,
    bool denied = false,
    bool dryRun = false,
  }) async {
    if (!settings.auditEnabled) return;
    await AuditService.instance.record(
      conversationId: conversationId,
      tool: call.tool,
      args: call.args,
      ok: ok,
      output: output,
      dryRun: dryRun,
      denied: denied,
    );
  }
}
