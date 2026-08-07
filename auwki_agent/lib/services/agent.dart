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

/// 子代理一次完整运行的产出：思维链、最终结论与工具使用记录。
class FlagshipAgentOutcome {
  const FlagshipAgentOutcome({
    required this.thinking,
    required this.output,
    required this.toolTrace,
    this.error,
  });

  final String thinking;
  final String output;
  final String toolTrace;
  final String? error;

  bool get ok => error == null;
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
    final allowed = {
      'webfetch',
      'websearch',
      'listfiles',
      'readfile',
      'writefile',
      'replacefile',
      'command',
    };
    var cursor = 0;
    while (cursor < text.length) {
      final startIdx = text.indexOf('[正式输出]', cursor);
      if (startIdx < 0) break;
      final blockStart = startIdx + '[正式输出]'.length;
      final endIdx = text.indexOf('[输出结束]', blockStart);
      final slice = endIdx < 0
          ? text.substring(blockStart)
          : text.substring(blockStart, endIdx);
      // 宽容解析：去掉可能包裹的代码围栏，然后扫描所有 tool("...")。
      final block = slice.replaceAll('```', '');
      calls.addAll(_parseCalls(block, allowed));
      if (endIdx < 0) break;
      cursor = endIdx + '[输出结束]'.length;
    }
    return calls;
  }

  /// 文本中是否存在工具调用块（即使块解析失败也返回 true）。
  static bool hasToolBlock(String text) =>
      text.contains('[正式输出]') || text.contains('[输出结束]');

  static List<AgentToolCall> _parseCalls(
    String block,
    Set<String> allowed,
  ) {
    final calls = <AgentToolCall>[];
    // 允许同一行出现多个调用；参数开头必须是有引号的字符串。
    final head = RegExp(r'([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*"');
    var i = 0;
    while (i < block.length) {
      final match = head.firstMatch(block.substring(i));
      if (match == null) break;
      final tool = match.group(1)!;
      final argStart = i + match.end;
      final argEnd = _findArgEnd(block, argStart);
      if (argEnd < 0) break; // 参数没有闭合引号，停止避免死循环
      if (allowed.contains(tool)) {
        calls.add(
          AgentToolCall(
            tool: tool,
            args: _decodeToolArg(block.substring(argStart, argEnd)),
          ),
        );
      }
      i = argEnd + 1;
    }
    return calls;
  }

  /// 找到参数结束位置（未转义的双引号，且其后（允许空白）紧跟右括号）。
  /// 参数内未转义的双引号会被当作普通内容保留，只要它后面不是右括号。
  static int _findArgEnd(String s, int start) {
    var i = start;
    var escaped = false;
    while (i < s.length) {
      final c = s[i];
      if (escaped) {
        escaped = false;
        i++;
        continue;
      }
      if (c == r'\') {
        escaped = true;
        i++;
        continue;
      }
      if (c == '"') {
        var j = i + 1;
        while (j < s.length &&
            (s[j] == ' ' ||
                s[j] == '\t' ||
                s[j] == '\r' ||
                s[j] == '\n')) {
          j++;
        }
        if (j >= s.length || s[j] == ')') return i;
      }
      i++;
    }
    return -1;
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

  /// 主协调下发给子代理的“任务消息”，模拟用户侧对话。
  static String flagshipAgentTaskMessage({
    required String focus,
    required String coordinatorNote,
    required bool isEnglish,
  }) {
    final note = coordinatorNote.trim().isEmpty
        ? (isEnglish ? '(none)' : '（无）')
        : coordinatorNote.trim();
    if (isEnglish) {
      return '''
Coordinator task for you: $focus
Coordinator note: $note

Think step by step (chain of thought). Use tools when needed. End with a concise conclusion.
''';
    }
    return '''
主协调分配给你的任务：$focus
主协调备注：$note

请先逐步思考（思维链），必要时使用工具。最后给出一段简洁结论。
''';
  }

  /// 运行一个子代理：它可以有自己的思维链，并像主代理一样调用工具
  /// （command 除外，命令类操作统一交给主协调），工具结果会作为
  /// 用户消息回填，继续下一轮思考，直到不再调用工具或达到轮次上限。
  static Future<FlagshipAgentOutcome> runFlagshipAgent({
    required Stream<String> Function(
      String system,
      List<Map<String, dynamic>> messages,
    )
    chat,
    required String systemPrompt,
    required List<Map<String, dynamic>> messages,
    String? cwd,
    int maxTurns = 3,
    void Function(String thinking)? onThinking,
    Future<bool> Function(String command)? onCommandRequest,
  }) async {
    final thinking = StringBuffer();
    final trace = <String>[];
    var msgs = List<Map<String, dynamic>>.from(messages);
    String? finalOutput;

    for (var turn = 0; turn < maxTurns; turn++) {
      final buf = StringBuffer();
      await for (final chunk in chat(systemPrompt, msgs)) {
        buf.write(chunk);
        final current = thinking.toString() + buf.toString();
        onThinking?.call(current);
      }
      final raw = buf.toString();
      if (raw.trim().isEmpty) break;
      if (thinking.isNotEmpty) thinking.write('\n\n');
      thinking.write(raw.trim());

      final calls = parse(raw);
      if (calls.isEmpty) {
        final visible = _stripToolBlocks(raw);
        finalOutput = visible.trim();
        break;
      }

      final results = <String>[];
      for (final call in calls) {
        if (call.tool == 'command') {
          final allow = onCommandRequest == null
              ? false
              : await onCommandRequest(call.args);
          if (!allow) {
            final blocked = I18n.t(
              'agent.error.subagent_command_blocked',
              {'command': call.args},
            );
            trace.add(blocked);
            results.add(blocked);
            continue;
          }
          final r = await execute(call, cwd: cwd);
          final detail = r.error ?? r.output;
          trace.add('${r.call.display}\n$detail');
          results.add('${r.call.display}\n$detail');
          continue;
        }
        final r = await execute(call, cwd: cwd);
        final detail = r.error ?? r.output;
        trace.add('${r.call.display}\n$detail');
        results.add('${r.call.display}\n$detail');
      }

      msgs.add({'role': 'assistant', 'content': raw});
      msgs.add({
        'role': 'user',
        'content': I18n.t(
          'chat.tool_result_prompt',
          {'result': results.join('\n\n')},
        ),
      });
      if (turn == maxTurns - 1) {
        final visible = _stripToolBlocks(raw);
        finalOutput = visible.trim();
      }
    }

    final output = (finalOutput == null || finalOutput.isEmpty)
        ? _stripToolBlocks(thinking.toString())
        : finalOutput;
    return FlagshipAgentOutcome(
      thinking: thinking.toString().trim(),
      output: output,
      toolTrace: trace.join('\n'),
    );
  }

  static String _stripToolBlocks(String text) {
    var s = text.replaceAll(
      RegExp(r'\[正式输出\][\s\S]*?\[输出结束\]', multiLine: true),
      '',
    );
    return s.trim();
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
    required String agentTitle,
    required String focus,
    required String coordinatorNote,
    required bool isEnglish,
  }) {
    if (isEnglish) {
      return '''
You are $agentTitle, a specialist sub-agent inside the AUWKI flagship collaboration.

Your only job is to help the coordinator (Sisyphus) by providing focused analysis and information about your assigned focus. You do not talk to the user, and you do not decide the final answer. The user's mode, thinking level, and cost settings do not apply to you.

Coordinator note: $coordinatorNote
Your assigned focus: $focus

Rules:
- Think first, then act. It is fine to write your chain of thought in your output.
- If you need to inspect the workspace, read/write files, or search the web, use the tool block:
  [正式输出]
  listfiles("path")
  readfile("path")
  writefile("path|||content")
  replacefile("path|||old|||new")
  webfetch("https://...")
  websearch("keywords")
  [输出结束]
- You must NOT use the command tool. Commands are executed by the coordinator.
- Inside the tool block, one call per line, arguments in English double quotes; tool results will come back as a user message.
- Keep your response concise and information-dense; the coordinator will synthesize
- End with a short conclusion, not the final answer's markdown headings
''';
    }

    return '''
你是 AUWKI 旗舰协作中的子代理 $agentTitle。

你唯一的目标是为主协调（Sisyphus）提供聚焦的分析和信息，帮助它完成综合。你不直接面对用户，也不需要给出最终答案。用户的模式、思考挡位和成本设置与你无关。

主协调备注：$coordinatorNote
你的任务：$focus

规则：
- 先思考，再行动。可以在输出中写下你的思维链
- 如果需要查看工作目录、读写文件或搜索网页，使用工具调用块：
  [正式输出]
  listfiles("路径")
  readfile("路径")
  writefile("路径|||内容")
  replacefile("路径|||旧文本|||新文本")
  webfetch("https://...")
  websearch("关键词")
  [输出结束]
- 禁止使用 command 工具，命令类操作统一交给主协调执行
- 工具块内每行一个调用，参数用英文双引号；工具结果会以用户消息返回给你
- 输出简洁、信息密集，交由主协调综合
- 最后给出一段简短结论，不要输出最终答案的 Markdown 标题
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

  static Future<AgentResult> execute(
    AgentToolCall call, {
    String? cwd,
  }) async {
    try {
      final out = switch (call.tool) {
        'webfetch' => await _webfetch(call.args),
        'websearch' => await _websearch(call.args),
        'listfiles' => await _listfiles(call.args, cwd),
        'readfile' => await _readfile(call.args, cwd),
        'writefile' => await _writefile(call.args, cwd),
        'replacefile' => await _replacefile(call.args, cwd),
        'command' => await _command(call.args, cwd),
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

  static Future<String> _command(String cmd, String? cwd) async {
    final safetyIssue = _validateCommand(cmd);
    if (safetyIssue != null) return safetyIssue;

    late final Process process;
    try {
      process = await Process.start(
        _shellExecutable(),
        _shellArgs(cmd),
        workingDirectory: cwd,
      );
    } catch (e) {
      return '${I18n.t('agent.error.command_start_failed')}\n$e';
    }

    final outFuture = process.stdout
        .transform(utf8.decoder)
        .join()
        .catchError((Object _) => '');
    final errFuture = process.stderr
        .transform(utf8.decoder)
        .join()
        .catchError((Object _) => '');

    late final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        const Duration(seconds: 30),
      );
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      return I18n.t('agent.error.command_timeout', {'command': cmd});
    }
    final stdout = await outFuture;
    final stderr = await errFuture;
    final buf = StringBuffer();
    if (stdout.isNotEmpty) buf.write(stdout);
    if (stderr.isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n--- stderr ---\n');
      buf.write(stderr);
    }
    buf.write('\n[exit $exitCode]');
    final out = buf.toString();
    return out.length > 6000 ? _ellipsize(out, 6000) : out;
  }

  /// 长文本保留头尾，避免 AI 丢失关键上下文。
  static String _ellipsize(String s, int max) {
    if (s.length <= max) return s;
    final head = s.substring(0, (max * 0.6).round());
    final tail = s.substring(s.length - (max * 0.35).round());
    return '$head\n…[中间省略 ${s.length - max} 字符]…\n$tail';
  }

  /// 跨平台命令解释器：Windows 用 PowerShell，macOS/Linux 用 /bin/sh。
  static String _shellExecutable() {
    if (Platform.isWindows) return 'powershell.exe';
    return '/bin/sh';
  }

  static List<String> _shellArgs(String cmd) {
    if (Platform.isWindows) {
      return ['-NoProfile', '-NonInteractive', '-Command', cmd];
    }
    return ['-c', cmd];
  }

  static Future<String> _listfiles(String path, String? cwd) async {
    final dir = Directory(_resolvePath(path, cwd));
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

  static Future<String> _readfile(String path, String? cwd) async {
    final file = File(_resolvePath(path, cwd));
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

  static Future<String> _writefile(String arg, String? cwd) async {
    final parts = _splitToolArg(arg, 2);
    if (parts == null) return I18n.t('agent.error.write_args');
    final file = File(_resolvePath(parts[0], cwd));
    final safetyIssue = _validateWritePath(file.path, cwd);
    if (safetyIssue != null) return safetyIssue;
    if (await file.exists()) {
      return I18n.t('agent.error.file_exists', {'path': file.path});
    }

    await file.parent.create(recursive: true);
    await file.writeAsString(_unescape(parts[1]));
    return I18n.t('agent.done.write', {'path': file.path});
  }

  static Future<String> _replacefile(String arg, String? cwd) async {
    final parts = _splitToolArg(arg, 3);
    if (parts == null) return I18n.t('agent.error.replace_args');
    final file = File(_resolvePath(parts[0], cwd));
    final safetyIssue = _validateWritePath(file.path, cwd);
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

  /// 把模型给出的路径解析到工作目录下；空路径表示工作目录本身。
  static String _resolvePath(String path, String? cwd) {
    var p = path.trim().replaceAll('\\', '/');
    final home = _homeDirectory();
    if (p == '~') {
      p = home ?? (cwd ?? Directory.current.path).replaceAll('\\', '/');
    } else if (p.startsWith('~/') && home != null) {
      p = '$home/${p.substring(2)}';
    }
    if (p.isEmpty) return (cwd ?? Directory.current.path).replaceAll('\\', '/');
    final isAbsolute =
        p.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(p);
    if (isAbsolute) return p;
    final base = (cwd ?? Directory.current.path).replaceAll('\\', '/');
    return '$base/$p';
  }

  /// 跨平台用户主目录：优先 $HOME，Windows 回退到 USERPROFILE。
  static String? _homeDirectory() {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return home.trim().replaceAll('\\', '/');
    }
    if (Platform.isWindows) {
      final profile = Platform.environment['USERPROFILE'];
      if (profile != null && profile.trim().isNotEmpty) {
        return profile.trim().replaceAll('\\', '/');
      }
    }
    return null;
  }

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

  static String? _validateWritePath(String path, String? cwd) {
    final normalized = path.trim();
    if (normalized.isEmpty) return I18n.t('agent.error.empty_path');
    if (_isUnsafePath(normalized, cwd)) {
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

  static bool _isUnsafePath(String path, String? cwd) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.contains('/../') || normalized == '..') return true;
    final absolute =
        normalized.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
    if (!absolute) return false;
    final allowedPrefixes = [
      (cwd ?? Directory.current.path).replaceAll('\\', '/'),
      Directory.systemTemp.path.replaceAll('\\', '/'),
      '${_homeDirectory() ?? ''}/'.replaceAll('\\', '/'),
    ].where((p) => p.isNotEmpty).toList();
    final target = Platform.isWindows ? normalized.toLowerCase() : normalized;
    final prefixes = Platform.isWindows
        ? allowedPrefixes.map((p) => p.toLowerCase()).toList()
        : allowedPrefixes;
    bool within(String prefix) {
      if (target == prefix) return true;
      final withSlash = prefix.endsWith('/') ? prefix : '$prefix/';
      return target.startsWith(withSlash);
    }

    return !prefixes.any(within);
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
