import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../i18n/strings.dart';

class AgentToolCall {
  AgentToolCall({required this.tool, required this.args});
  final String tool;
  final String args;

  String get display => '$tool("$args")';
}

class AgentResult {
  AgentResult({required this.call, required this.output, this.error});
  final AgentToolCall call;
  final String output;
  final String? error;

  bool get ok => error == null;
}

class CollaborativeAgent {
  const CollaborativeAgent({
    required this.id,
    required this.title,
    required this.instruction,
  });

  final String id;
  final String title;
  final String instruction;
}

class CollaborativeAgentResult {
  CollaborativeAgentResult({
    required this.agent,
    required this.output,
    this.error,
  });

  final CollaborativeAgent agent;
  final String output;
  final String? error;

  bool get ok => error == null;
}

class CollaborativeSessionResult {
  CollaborativeSessionResult({required this.results, required this.summary});

  final List<CollaborativeAgentResult> results;
  final String summary;
}

class FlagshipAgentPlan {
  FlagshipAgentPlan({
    required this.items,
    required this.coordinatorNote,
    this.complete = false,
    this.finalInstruction = '',
  });

  final List<FlagshipPlanItem> items;
  final String coordinatorNote;
  final bool complete;
  final String finalInstruction;

  static FlagshipAgentPlan fallback(bool isEnglish) => FlagshipAgentPlan(
    items: [
      FlagshipPlanItem(
        agentId: 'prometheus',
        focus: isEnglish
            ? 'Create the smallest executable plan.'
            : '给出最小可执行方案。',
      ),
      FlagshipPlanItem(
        agentId: 'metis',
        focus: isEnglish ? 'Review risks and blind spots.' : '审查风险和盲点。',
      ),
      FlagshipPlanItem(
        agentId: 'oracle',
        focus: isEnglish ? 'Evaluate architecture and tradeoffs.' : '评估架构与权衡。',
      ),
    ],
    coordinatorNote: isEnglish ? 'Fallback collaborative plan.' : '使用默认协同方案。',
    complete: false,
    finalInstruction: '',
  );
}

class FlagshipPlanItem {
  FlagshipPlanItem({
    required this.agentId,
    required this.focus,
    this.reason,
    this.title,
    this.instruction,
  });

  final String agentId;
  final String focus;
  final String? reason;
  final String? title;
  final String? instruction;
}

class AgentRunner {
  static const List<CollaborativeAgent> flagshipAgents = [
    CollaborativeAgent(
      id: 'prometheus',
      title: 'Prometheus',
      instruction:
          'Focus on planning. Break the problem into concrete execution steps, identify ordering, and propose the smallest workable plan.',
    ),
    CollaborativeAgent(
      id: 'metis',
      title: 'Metis',
      instruction:
          'Focus on review. Find risks, blind spots, missing constraints, and likely failure modes in the task or plan.',
    ),
    CollaborativeAgent(
      id: 'oracle',
      title: 'Oracle',
      instruction:
          'Focus on architecture and deep technical reasoning. Evaluate tradeoffs, system boundaries, and long-term maintainability.',
    ),
    CollaborativeAgent(
      id: 'artistry',
      title: 'Artistry',
      instruction:
          'Focus on unconventional options and better user experience. Suggest sharper or less obvious approaches when useful.',
    ),
    CollaborativeAgent(
      id: 'librarian',
      title: 'Librarian',
      instruction:
          'Focus on requirements clarity, API assumptions, and what information should be verified before acting.',
    ),
    CollaborativeAgent(
      id: 'explorer',
      title: 'Explorer',
      instruction:
          'Focus on codebase exploration and implementation hints. Infer which files, modules, and patterns are likely relevant.',
    ),
  ];

  static CollaborativeAgent? flagshipAgentById(String id) {
    for (final agent in flagshipAgents) {
      if (agent.id == id) return agent;
    }
    return null;
  }

  static CollaborativeAgent agentFromPlanItem(FlagshipPlanItem item) {
    final existing = flagshipAgentById(item.agentId);
    if (existing != null) return existing;
    final title = item.title?.trim().isNotEmpty == true
        ? item.title!.trim()
        : item.agentId;
    final instruction = item.instruction?.trim().isNotEmpty == true
        ? item.instruction!.trim()
        : 'Focus on the assigned task and provide concise, specific analysis.';
    return CollaborativeAgent(
      id: item.agentId,
      title: title,
      instruction: instruction,
    );
  }

  /// 解析 AI 输出中的工具调用块
  /// 格式: [正式输出]\nwebfetch("...")\n... [输出结束]
  static List<AgentToolCall> parse(String text) {
    final calls = <AgentToolCall>[];
    var cursor = 0;
    while (cursor < text.length) {
      final startIdx = text.indexOf('[正式输出]', cursor);
      if (startIdx < 0) break;
      final blockStart = startIdx + '[正式输出]'.length;
      final endIdx = text.indexOf('[输出结束]', blockStart);
      final slice = endIdx < 0
          ? text.substring(blockStart)
          : text.substring(blockStart, endIdx);
      final re = RegExp(r'^(\w+)\("((?:\\.|[^"])*)"\)\s*$', multiLine: true);
      final allowed = {
        'webfetch',
        'websearch',
        'listfiles',
        'readfile',
        'writefile',
        'replacefile',
        'command',
      };
      for (final m in re.allMatches(slice)) {
        final tool = m.group(1)!;
        if (!allowed.contains(tool)) continue;
        calls.add(AgentToolCall(tool: tool, args: _decodeToolArg(m.group(2)!)));
      }
      if (endIdx < 0) break;
      cursor = endIdx + '[输出结束]'.length;
    }
    return calls;
  }

  static String _decodeToolArg(String arg) => arg
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\');

  static Future<CollaborativeSessionResult> collaborate({
    required Stream<String> Function(
      String system,
      List<Map<String, dynamic>> messages,
    )
    chat,
    required List<Map<String, dynamic>> history,
    required bool isEnglish,
  }) async {
    final tasks = flagshipAgents.map((agent) async {
      final prompt = _agentSystemPrompt(agent, isEnglish: isEnglish);
      try {
        final buf = StringBuffer();
        await for (final chunk in chat(prompt, history)) {
          buf.write(chunk);
        }
        return CollaborativeAgentResult(agent: agent, output: buf.toString());
      } catch (e) {
        return CollaborativeAgentResult(
          agent: agent,
          output: '',
          error: e.toString(),
        );
      }
    }).toList();

    final results = await Future.wait(tasks);
    final summary = _formatCollaboration(results, isEnglish: isEnglish);
    return CollaborativeSessionResult(results: results, summary: summary);
  }

  static String formatCollaboration(
    List<CollaborativeAgentResult> results, {
    required bool isEnglish,
  }) {
    return _formatCollaboration(results, isEnglish: isEnglish);
  }

  static Future<FlagshipAgentPlan> planFlagshipSession({
    required Stream<String> Function(
      String system,
      List<Map<String, dynamic>> messages,
    )
    chat,
    required List<Map<String, dynamic>> history,
    required bool isEnglish,
  }) async {
    final system = _flagshipCoordinatorPrompt(isEnglish: isEnglish);

    final buf = StringBuffer();
    await for (final chunk in chat(system, history)) {
      buf.write(chunk);
    }
    return _parseFlagshipPlan(buf.toString(), isEnglish: isEnglish);
  }

  static Future<FlagshipAgentPlan> planFlagshipRound({
    required Stream<String> Function(
      String system,
      List<Map<String, dynamic>> messages,
    )
    chat,
    required List<Map<String, dynamic>> history,
    required List<CollaborativeAgentResult> previousResults,
    required int round,
    required bool isEnglish,
  }) async {
    final system = _flagshipCoordinatorPrompt(isEnglish: isEnglish);
    final resultSummary = _formatRoundResults(previousResults);
    final messages = [
      ...history,
      {
        'role': 'assistant',
        'content': isEnglish
            ? 'Previous flagship agent round $round results:\n$resultSummary'
            : '上一轮旗舰 Agent 第 $round 轮结果：\n$resultSummary',
      },
      {
        'role': 'user',
        'content': isEnglish
            ? 'Decide whether the task is complete. If complete, return complete=true and finalInstruction. Otherwise plan the next round with selected or newly defined agents.'
            : '判断任务是否已经足够完成。若完成，返回 complete=true 和 finalInstruction；否则规划下一轮，允许选择已有 agent 或新建临时 agent。',
      },
    ];
    final buf = StringBuffer();
    await for (final chunk in chat(system, messages)) {
      buf.write(chunk);
    }
    return _parseFlagshipPlan(buf.toString(), isEnglish: isEnglish);
  }

  static String _flagshipCoordinatorPrompt({required bool isEnglish}) {
    if (isEnglish) {
      return '''
You are Sisyphus, the flagship coordinator of a multi-agent collaboration.

You plan one round at a time. You may select built-in agents or create temporary task-specific agents.

Return ONLY valid JSON with this shape:
{
  "coordinatorNote": "short progress note",
  "complete": false,
  "finalInstruction": "only when complete=true: how Sisyphus should write the final answer",
  "items": [
    {
      "agentId": "prometheus-or-custom-id",
      "title": "optional custom display name",
      "instruction": "optional custom system role if agentId is new",
      "focus": "specific task for this round",
      "reason": "why this agent is needed"
    }
  ]
}

Built-in agentId values: prometheus, metis, oracle, artistry, librarian, explorer.

Rules:
- If more analysis is needed, set complete=false and choose 2 to 4 agents
- If enough information is available, set complete=true and return items=[]
- For custom agents, use lowercase kebab-case agentId, plus title and instruction
- Keep focus concise and actionable
- No markdown, no code fences, no extra text
''';
    }

    return '''
你是 Sisyphus，旗舰多 Agent 协作的主协调。

你需要一轮一轮规划。你可以选择内置 agent，也可以创建临时的任务专用 agent。

只返回合法 JSON，格式如下：
{
  "coordinatorNote": "简短进度说明",
  "complete": false,
  "finalInstruction": "仅 complete=true 时填写：Sisyphus 应如何写最终回答",
  "items": [
    {
      "agentId": "prometheus-or-custom-id",
      "title": "可选，自定义显示名",
      "instruction": "可选，若是新 agent 则填写系统角色",
      "focus": "这一轮的具体任务",
      "reason": "为什么需要这个 agent"
    }
  ]
}

内置 agentId：prometheus、metis、oracle、artistry、librarian、explorer。

规则：
- 如果还需要继续分析，complete=false，并选择 2 到 4 个 agent
- 如果信息已经足够，complete=true，并返回 items=[]
- 自定义 agent 使用小写短横线 agentId，并补充 title 和 instruction
- focus 必须简短、具体、可执行
- 不要 markdown，不要代码块，不要额外文字
''';
  }

  static String flagshipAgentSystemPrompt({
    required String baseSystemPrompt,
    required String agentTitle,
    required String focus,
    required String coordinatorNote,
    required bool isEnglish,
  }) {
    if (isEnglish) {
      return '''
$baseSystemPrompt

## Multi-Agent Coordination
- You are $agentTitle
- Coordinator note: $coordinatorNote
- Your assigned focus: $focus
- Stream your own analysis naturally as you think
- Do not claim to be the final answer
''';
    }

    return '''
$baseSystemPrompt

## 多 Agent 协同分工
- 你是 $agentTitle
- 主协调备注：$coordinatorNote
- 你的任务：$focus
- 允许自然流式输出你的分析
- 不要伪装成最终结论
''';
  }

  static String chooseAgentSummary({
    required String baseSystemPrompt,
    required String userContext,
    required String coordinatorNote,
    required bool isEnglish,
  }) {
    final header = isEnglish
        ? '''
$baseSystemPrompt

## Multi-Agent Coordinator
You are Sisyphus. Given the user request, choose the minimum useful subset of specialist agents.

Return ONLY valid JSON with this shape:
{
  "coordinatorNote": "short note",
  "items": [
    {"agentId": "prometheus", "focus": "...", "reason": "..."}
  ]
}

Rules:
- agentId must be one of: prometheus, metis, oracle, artistry, librarian, explorer
- Select 2 to 4 agents if possible
- Keep focus concise and actionable
- No markdown, no code fences, no extra text
'''
        : '''
$baseSystemPrompt

## 多 Agent 主协调
你是 Sisyphus。请根据用户请求挑选最少但足够的专家子代理。

只返回合法 JSON，格式如下：
{
  "coordinatorNote": "简短说明",
  "items": [
    {"agentId": "prometheus", "focus": "...", "reason": "..."}
  ]
}

规则：
- agentId 只能是：prometheus、metis、oracle、artistry、librarian、explorer
- 尽量选择 2 到 4 个 agent
- focus 要简短、可执行
- 不要 markdown，不要代码块，不要额外文字
''';
    return '$header\n\nUser context:\n$userContext\n';
  }

  static FlagshipAgentPlan _parseFlagshipPlan(
    String text, {
    required bool isEnglish,
  }) {
    final jsonText = _extractJsonObject(text);
    if (jsonText == null) return FlagshipAgentPlan.fallback(isEnglish);
    try {
      final m = jsonDecode(jsonText) as Map<String, dynamic>;
      final itemsRaw = (m['items'] as List?) ?? const [];
      final items = <FlagshipPlanItem>[];
      for (final item in itemsRaw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final agentId = (map['agentId'] ?? '').toString().trim();
        final focus = (map['focus'] ?? '').toString().trim();
        if (agentId.isEmpty || focus.isEmpty) continue;
        items.add(
          FlagshipPlanItem(
            agentId: agentId,
            focus: focus,
            reason: map['reason']?.toString(),
            title: map['title']?.toString(),
            instruction: map['instruction']?.toString(),
          ),
        );
      }
      final complete = m['complete'] == true;
      if (items.isEmpty && !complete) {
        return FlagshipAgentPlan.fallback(isEnglish);
      }
      return FlagshipAgentPlan(
        items: items.take(4).toList(),
        coordinatorNote: (m['coordinatorNote'] ?? '').toString().trim(),
        complete: complete,
        finalInstruction: (m['finalInstruction'] ?? '').toString().trim(),
      );
    } catch (_) {
      return FlagshipAgentPlan.fallback(isEnglish);
    }
  }

  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  static String _agentSystemPrompt(
    CollaborativeAgent agent, {
    required bool isEnglish,
  }) {
    if (isEnglish) {
      return '''
You are ${agent.title}, a specialist sub-agent inside AUWKI.

${agent.instruction}

Rules:
- Do not pretend to call tools
- Work only from the conversation context you are given
- Be concise but specific
- Output only your own analysis, not a final combined answer
''';
    }

    return '''
你是 AUWKI 内部的专家子代理 ${agent.title}。

${agent.instruction}

规则：
- 不要伪造工具调用
- 只基于给定的对话上下文进行分析
- 输出简洁但具体
- 只给出你自己的分析，不要给最终综合结论
''';
  }

  static String _formatCollaboration(
    List<CollaborativeAgentResult> results, {
    required bool isEnglish,
  }) {
    final buf = StringBuffer();
    for (final result in results) {
      buf.writeln('## ${result.agent.title}');
      if (result.ok) {
        buf.writeln(result.output.trim());
      } else {
        buf.writeln(result.error?.trim() ?? 'error');
      }
      buf.writeln();
    }
    if (isEnglish) {
      buf.writeln('## Sisyphus');
      buf.writeln(
        'Synthesize the analyses above into one final answer. You may still use tools if external verification is required.',
      );
    } else {
      buf.writeln('## Sisyphus');
      buf.writeln('请把以上分析综合成一个最终回答；如果需要外部验证，仍可继续使用工具。');
    }
    return buf.toString().trim();
  }

  static String _formatRoundResults(List<CollaborativeAgentResult> results) {
    final buf = StringBuffer();
    for (final result in results) {
      buf.writeln('## ${result.agent.title}');
      buf.writeln(result.ok ? result.output.trim() : result.error?.trim());
      buf.writeln();
    }
    return buf.toString().trim();
  }

  static Future<AgentResult> execute(AgentToolCall call) async {
    try {
      final out = switch (call.tool) {
        'webfetch' => await _webfetch(call.args),
        'websearch' => await _websearch(call.args),
        'listfiles' => await _listfiles(call.args),
        'readfile' => await _readfile(call.args),
        'writefile' => await _writefile(call.args),
        'replacefile' => await _replacefile(call.args),
        'command' => await _command(call.args),
        _ => throw Exception(
          I18n.t('agent.error.unknown_tool', {'tool': call.tool}),
        ),
      };
      return AgentResult(call: call, output: out);
    } catch (e) {
      return AgentResult(call: call, output: '', error: e.toString());
    }
  }

  static Future<String> _webfetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      return I18n.t('agent.error.invalid_url', {'url': url});
    }
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode ~/ 100 != 2) {
      return I18n.t('agent.error.http_status', {
        'code': '${resp.statusCode}',
        'body': url,
      });
    }
    final body = resp.body;
    return body.length > 8000
        ? '${body.substring(0, 8000)}\n${I18n.t('agent.truncated')}'
        : body;
  }

  static const List<String> _searxInstances = [
    'https://search.disroot.org',
    'https://searx.be',
    'https://search.bus-hit.me',
    'https://priv.au',
    'https://searx.work',
    'https://searx.tiekoetter.com',
    'https://search.privacyguides.net',
    'https://search.ononoki.org',
    'https://searx.lavatech.top',
  ];

  static Future<String> _websearch(String query) async {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'Accept': 'application/json',
    };

    for (final inst in _searxInstances) {
      try {
        final uri = Uri.parse(
          '$inst/search?q=${Uri.encodeQueryComponent(query)}&format=json',
        );
        final resp = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) continue;
        final body = resp.body;
        final json = jsonDecode(body) as Map<String, dynamic>;
        final results = (json['results'] as List?) ?? [];
        if (results.isEmpty) continue;
        return results
            .take(8)
            .map((r) {
              final m = r as Map<String, dynamic>;
              final title = (m['title'] ?? '').toString().trim();
              final url = (m['url'] ?? '').toString().trim();
              final content = (m['content'] ?? '').toString().trim();
              return '- $title\n  $url\n  $content';
            })
            .join('\n');
      } catch (_) {
        continue;
      }
    }
    return I18n.t('agent.error.searx_unavailable');
  }

  static Future<String> _command(String cmd) async {
    final safetyIssue = _validateCommand(cmd);
    if (safetyIssue != null) return safetyIssue;

    final res = await Process.run('bash', [
      '-c',
      cmd,
    ]).timeout(const Duration(seconds: 30));
    final buf = StringBuffer();
    if (res.stdout.toString().isNotEmpty) buf.write(res.stdout);
    if (res.stderr.toString().isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n--- stderr ---\n');
      buf.write(res.stderr);
    }
    buf.write('\n[exit ${res.exitCode}]');
    final out = buf.toString();
    return out.length > 6000
        ? '${out.substring(0, 6000)}\n${I18n.t('agent.truncated')}'
        : out;
  }

  static Future<String> _listfiles(String path) async {
    final dir = Directory(path.trim().isEmpty ? '.' : path.trim());
    if (!await dir.exists()) {
      return I18n.t('agent.error.dir_missing', {'path': dir.path});
    }

    final entries = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      final suffix = type == FileSystemEntityType.directory ? '/' : '';
      entries.add('${entity.path}$suffix');
      if (entries.length >= 300) break;
    }
    entries.sort();
    final truncated = entries.length >= 300
        ? '\n${I18n.t('agent.truncated_300')}'
        : '';
    return entries.isEmpty
        ? I18n.t('agent.empty_dir', {'path': dir.path})
        : '${entries.join('\n')}$truncated';
  }

  static Future<String> _readfile(String path) async {
    final file = File(path.trim());
    if (!await file.exists()) {
      return I18n.t('agent.error.file_missing', {'path': file.path});
    }
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      return I18n.t('agent.error.not_file', {'path': file.path});
    }
    if (stat.size > 1024 * 1024) {
      return I18n.t('agent.error.file_too_large', {'path': file.path});
    }

    final text = await file.readAsString();
    final numbered = text
        .split('\n')
        .asMap()
        .entries
        .map((e) => '${e.key + 1}: ${e.value}')
        .join('\n');
    return numbered.length > 12000
        ? '${numbered.substring(0, 12000)}\n${I18n.t('agent.truncated')}'
        : numbered;
  }

  static Future<String> _writefile(String arg) async {
    final parts = _splitToolArg(arg, 2);
    if (parts == null) return I18n.t('agent.error.write_args');
    final file = File(parts[0].trim());
    final safetyIssue = _validateWritePath(file.path);
    if (safetyIssue != null) return safetyIssue;
    if (await file.exists()) {
      return I18n.t('agent.error.file_exists', {'path': file.path});
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(_unescape(parts[1]));
    return I18n.t('agent.done.write', {'path': file.path});
  }

  static Future<String> _replacefile(String arg) async {
    final parts = _splitToolArg(arg, 3);
    if (parts == null) return I18n.t('agent.error.replace_args');
    final file = File(parts[0].trim());
    final safetyIssue = _validateWritePath(file.path);
    if (safetyIssue != null) return safetyIssue;

    if (!await file.exists()) {
      return I18n.t('agent.error.file_missing', {'path': file.path});
    }

    final oldText = _unescape(parts[1]);
    final newText = _unescape(parts[2]);
    final text = await file.readAsString();
    if (!text.contains(oldText)) {
      return I18n.t('agent.error.replace_missing', {'path': file.path});
    }
    final next = text.replaceFirst(oldText, newText);
    await file.writeAsString(next);
    return I18n.t('agent.done.replace', {'path': file.path});
  }

  static List<String>? _splitToolArg(String arg, int count) {
    final parts = arg.split('|||');
    if (parts.length != count) return null;
    return parts;
  }

  static String _unescape(String s) => s
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\t', '\t')
      .replaceAll(r'\"', '"')
      .replaceAll(r'\\', '\\');

  static String? _validateCommand(String cmd) {
    final normalized = cmd.trim().toLowerCase();
    final blocked = <RegExp>[
      RegExp(r'(^|\s)rm\s+-[^\n;|&]*r[^\n;|&]*f\b'),
      RegExp(r'(^|\s)rm\s+-[^\n;|&]*f[^\n;|&]*r\b'),
      RegExp(r'(^|\s)(mkfs|dd|shutdown|reboot|poweroff)\b'),
      RegExp(r'(^|\s)chmod\s+777\b'),
      RegExp(r'>\s*/dev/(sd[a-z]|nvme\d+n\d+|mapper/)'),
    ];
    for (final pattern in blocked) {
      if (pattern.hasMatch(normalized)) {
        return I18n.t('agent.error.command_blocked', {'command': cmd});
      }
    }
    return null;
  }

  static String? _validateWritePath(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return I18n.t('agent.error.empty_path');
    if (_isUnsafePath(normalized)) {
      return I18n.t('agent.error.path_blocked', {'path': path});
    }
    final lower = normalized.toLowerCase();
    final blockedNames = <RegExp>[
      RegExp(r'(^|/)\.env(\.|$|/)'),
      RegExp(r'(^|/)(id_rsa|id_ed25519|credentials|secret|secrets)(\.|$|/)'),
      RegExp(r'(^|/)\.git/'),
    ];
    for (final pattern in blockedNames) {
      if (pattern.hasMatch(lower)) {
        return I18n.t('agent.error.path_blocked', {'path': path});
      }
    }
    return null;
  }

  static bool _isUnsafePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.contains('/../') || normalized == '..') return true;
    final absolute = normalized.startsWith('/');
    if (!absolute) return false;
    final allowedPrefixes = [
      Directory.current.path.replaceAll('\\', '/'),
      '/tmp/',
      '${Platform.environment['HOME'] ?? ''}/'.replaceAll('\\', '/'),
    ].where((p) => p.isNotEmpty).toList();
    return !allowedPrefixes.any(normalized.startsWith);
  }
}

class AgentTurn {
  AgentTurn({
    required this.thinking,
    required this.toolCall,
    required this.result,
  });
  final String thinking;
  final AgentToolCall toolCall;
  final AgentResult result;
}
