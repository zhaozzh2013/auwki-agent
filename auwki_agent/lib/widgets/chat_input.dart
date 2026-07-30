import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/agent.dart';
import '../services/ai_providers.dart';
import '../services/prompts.dart';
import '../services/settings_store.dart';
import '../state/chat_store.dart';
import '../theme.dart';
import '../widgets/dialogs/settings_dialog.dart';
import '../widgets/thinking_slider.dart';
import '../work_mode.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    this.mode = WorkMode.work,
    this.thinking = ThinkingLevel.thinking,
    this.accent,
    this.accentSoft,
    this.conversationId,
  });

  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color? accent;
  final Color? accentSoft;
  final String? conversationId;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;
  bool _sending = false;
  final Map<String, DateTime> _lastStreamUiUpdates = {};

  Color get _accent => widget.accent ?? AppColors.primary;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final v = _controller.text.trim().isNotEmpty;
      if (v != _hasText) setState(() => _hasText = v);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    final enterToSend = AppState.settingsOf(context).enterToSend;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if (enterToSend && !shift) {
      _send();
      return KeyEventResult.handled;
    }
    if (!enterToSend && shift) {
      return KeyEventResult.handled;
    }
    if (!enterToSend) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;

    final pf = picked.files.first;
    final path = pf.path;
    if (path == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.t('attach.error.read', {'name': pf.name}))),
      );
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;

    final size = await file.length();
    if (size > 5 * 1024 * 1024) {
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.t('attach.too_large', {'name': pf.name}))),
      );
      return;
    }

    final bytes = await file.readAsBytes();
    final isBinary = _looksBinary(bytes);
    if (isBinary) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(I18n.t('attach.error.binary', {'name': pf.name})),
        ),
      );
      return;
    }

    final text = utf8.decode(bytes, allowMalformed: true);
    final attach = Attachment(
      name: pf.name,
      size: size,
      mimeType: _guessMime(path),
      content: text,
    );

    final store = AppState.chatOf(context);
    final convId = widget.conversationId;
    if (convId == null) {
      final id = store.newConversation();
      store.activate(id);
      _sendTo(store, id, attachments: [attach]);
    } else {
      _sendTo(store, convId, attachments: [attach]);
    }
  }

  bool _looksBinary(List<int> bytes) {
    final len = bytes.length < 4096 ? bytes.length : 4096;
    var suspicious = 0;
    for (var i = 0; i < len; i++) {
      final b = bytes[i];
      if (b == 0) return true;
      if (b < 9 || (b > 13 && b < 32 && b != 27)) suspicious++;
    }
    return suspicious / len > 0.1;
  }

  String _guessMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    return {
          'txt': 'text/plain',
          'md': 'text/markdown',
          'json': 'application/json',
          'csv': 'text/csv',
          'html': 'text/html',
          'xml': 'application/xml',
          'yml': 'text/yaml',
          'yaml': 'text/yaml',
          'js': 'application/javascript',
          'ts': 'application/typescript',
          'py': 'text/x-python',
          'dart': 'text/x-dart',
          'log': 'text/plain',
        }[ext] ??
        'text/plain';
  }

  Future<void> _send() async {
    if (_sending) return;
    final store = AppState.chatOf(context);
    final settings = AppState.settingsOf(context);
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final convId = widget.conversationId ?? store.newConversation();
    if (widget.conversationId == null) store.activate(convId);

    if (_handleSlashCommand(store, convId, text)) {
      _controller.clear();
      return;
    }

    final effectiveText = _expandSlashPrompt(text);

    if (settings.apiKey.isEmpty) {
      _sendTo(
        store,
        convId,
        text: effectiveText,
        assistantText: I18n.t('chat.no_key'),
      );
      return;
    }

    _controller.clear();

    final userMsg = Message(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      sender: Sender.user,
      text: effectiveText,
    );
    store.addMessage(convId, userMsg);

    final placeholderId = 'm_${DateTime.now().microsecondsSinceEpoch}_a';
    final placeholder = Message(
      id: placeholderId,
      sender: Sender.assistant,
      text: I18n.t('chat.connecting'),
    );
    store.addMessage(convId, placeholder);

    setState(() => _sending = true);

    final history = <Map<String, dynamic>>[];
    for (final m
        in store.conversations.firstWhere((c) => c.id == convId).messages) {
      if (m.id == placeholderId) continue;
      if (m.sender == Sender.system) continue;
      final content = StringBuffer();
      if (m.attachments.isNotEmpty) {
        for (final a in m.attachments) {
          content.writeln('📎 ${a.name} (${a.mimeType}, ${a.size}B):\n');
          content.writeln(a.content);
        }
      }
      content.writeln(m.text);
      history.add({
        'role': m.sender == Sender.user ? 'user' : 'assistant',
        'content': content.toString().trim(),
      });
    }

    try {
      final client = settings.client;
      final systemPrompt = Prompts.build(
        mode: widget.mode,
        thinking: widget.thinking,
        costMode: settings.costMode,
      );
      final isEnglish = I18n.locale.value.languageCode == 'en';
      final maxFlagshipRounds = switch (settings.costMode) {
        CostMode.poor => 1,
        CostMode.medium => 3,
        CostMode.max => 5,
      };
      final subAgentMaxTokens = switch (settings.costMode) {
        CostMode.poor => 700,
        CostMode.medium => 1200,
        CostMode.max => 1800,
      };
      final finalMaxTokens = switch (settings.costMode) {
        CostMode.poor => 1000,
        CostMode.medium => 2048,
        CostMode.max => 3200,
      };
      final coordinatorMaxTokens = switch (settings.costMode) {
        CostMode.poor => 350,
        CostMode.medium => 700,
        CostMode.max => 1000,
      };

      var turn = 0;
      final maxTurns = 3;
      var currentHistory = List<Map<String, dynamic>>.from(history);

      if (widget.thinking == ThinkingLevel.flagship &&
          settings.costMode != CostMode.poor) {
        var plan = await AgentRunner.planFlagshipSession(
          chat: (system, messages) => client.chatStream(
            ChatRequest(
              system: system,
              messages: messages,
              model: settings.model,
              maxTokens: coordinatorMaxTokens,
            ),
          ),
          history: currentHistory,
          isEnglish: isEnglish,
        );

        final allResults = <CollaborativeAgentResult>[];
        for (var round = 1; round <= maxFlagshipRounds; round++) {
          if (plan.complete || plan.items.isEmpty) break;
          final plannedAgents = plan.items
              .map(AgentRunner.agentFromPlanItem)
              .toList();
          final planById = {for (final item in plan.items) item.agentId: item};
          final completed = <String>{};

          store.updateMessage(
            convId,
            placeholderId,
            _multiAgentStatus(
              plannedAgents.map((a) => a.title).toList(),
              completed,
              round: round,
              synthesizing: false,
              coordinatorNote: plan.coordinatorNote,
            ),
            persist: false,
          );

          Future<CollaborativeAgentResult> runAgent(
            CollaborativeAgent agent,
          ) async {
            final focus = planById[agent.id]?.focus ?? '';
            final subSystem = AgentRunner.flagshipAgentSystemPrompt(
              baseSystemPrompt: systemPrompt,
              agentTitle: agent.title,
              focus: focus,
              coordinatorNote: plan.coordinatorNote,
              isEnglish: isEnglish,
            );
            final subMsgId =
                'm_${DateTime.now().microsecondsSinceEpoch}_r${round}_${agent.id}';
            store.addMessage(
              convId,
              Message(
                id: subMsgId,
                sender: Sender.tool,
                text: '',
                toolName: 'agent.${agent.id}',
                toolArgs: 'Round $round: $focus',
                toolRunning: true,
              ),
            );
            final subRaw = StringBuffer();
            var lastSubVisible = '';
            try {
              await for (final chunk in client.chatStream(
                ChatRequest(
                  system: subSystem,
                  messages: currentHistory,
                  model: settings.model,
                  maxTokens: subAgentMaxTokens,
                ),
              )) {
                subRaw.write(chunk);
                final visible = subRaw.toString();
                if (_shouldUpdateStreamUi(subMsgId, visible, lastSubVisible)) {
                  lastSubVisible = visible;
                  store.updateMessage(
                    convId,
                    subMsgId,
                    visible,
                    persist: false,
                  );
                }
              }
              final result = CollaborativeAgentResult(
                agent: agent,
                output: subRaw.toString(),
              );
              if (result.output != lastSubVisible) {
                store.updateMessage(
                  convId,
                  subMsgId,
                  result.output,
                  persist: false,
                );
              }
              store.finishToolMessage(convId, subMsgId, result.output, true);
              completed.add(agent.title);
              store.updateMessage(
                convId,
                placeholderId,
                _multiAgentStatus(
                  plannedAgents.map((a) => a.title).toList(),
                  completed,
                  round: round,
                  synthesizing: false,
                  coordinatorNote: plan.coordinatorNote,
                ),
                persist: false,
              );
              return result;
            } catch (e) {
              final result = CollaborativeAgentResult(
                agent: agent,
                output: '',
                error: e.toString(),
              );
              store.finishToolMessage(
                convId,
                subMsgId,
                result.error ?? '',
                false,
              );
              completed.add(agent.title);
              store.updateMessage(
                convId,
                placeholderId,
                _multiAgentStatus(
                  plannedAgents.map((a) => a.title).toList(),
                  completed,
                  round: round,
                  synthesizing: false,
                  coordinatorNote: plan.coordinatorNote,
                ),
                persist: false,
              );
              return result;
            }
          }

          final roundResults = await Future.wait(plannedAgents.map(runAgent));
          allResults.addAll(roundResults);
          store.updateMessage(
            convId,
            placeholderId,
            _multiAgentStatus(
              plannedAgents.map((a) => a.title).toList(),
              completed,
              round: round,
              synthesizing: true,
              coordinatorNote: plan.coordinatorNote,
            ),
            persist: false,
          );

          plan = await AgentRunner.planFlagshipRound(
            chat: (system, messages) => client.chatStream(
              ChatRequest(
                system: system,
                messages: messages,
                model: settings.model,
                maxTokens: coordinatorMaxTokens,
              ),
            ),
            history: currentHistory,
            previousResults: roundResults,
            round: round,
            isEnglish: isEnglish,
          );
        }

        final summary = AgentRunner.formatCollaboration(
          allResults,
          isEnglish: isEnglish,
        );
        currentHistory = [
          ...currentHistory,
          {'role': 'assistant', 'content': summary},
          {
            'role': 'user',
            'content': plan.finalInstruction.isNotEmpty
                ? plan.finalInstruction
                : (isEnglish
                      ? 'Use the multi-agent collaboration notes above to produce the final answer. If needed, continue with tool calls.'
                      : '请基于上面的多 Agent 协同结果给出最终回答；如有必要，可继续调用工具。'),
          },
        ];
      }

      while (turn < maxTurns) {
        final req = ChatRequest(
          system: systemPrompt,
          messages: currentHistory,
          model: settings.model,
          maxTokens: finalMaxTokens,
        );
        final rawAcc = StringBuffer();
        var lastVisible = '';
        await for (final chunk in client.chatStream(req)) {
          rawAcc.write(chunk);
          final visible = _stripToolBlocks(rawAcc.toString());
          if (_shouldUpdateStreamUi(placeholderId, visible, lastVisible)) {
            lastVisible = visible;
            store.updateMessage(convId, placeholderId, visible, persist: false);
          }
        }
        final finalVisible = _stripToolBlocks(rawAcc.toString());
        if (finalVisible != lastVisible) {
          store.updateMessage(
            convId,
            placeholderId,
            finalVisible,
            persist: false,
          );
        }

        final calls = AgentRunner.parse(rawAcc.toString());
        if (calls.isEmpty || widget.thinking == ThinkingLevel.fast) break;

        final results = <AgentResult>[];
        for (final call in calls) {
          final toolMsgId = 'm_${DateTime.now().microsecondsSinceEpoch}_t';
          store.addMessage(
            convId,
            Message(
              id: toolMsgId,
              sender: Sender.tool,
              text: '',
              toolName: call.tool,
              toolArgs: call.args,
              toolRunning: true,
            ),
          );
          final r = await AgentRunner.execute(call);
          results.add(r);
          store.finishToolMessage(convId, toolMsgId, r.error ?? r.output, r.ok);
        }

        currentHistory.add({'role': 'assistant', 'content': rawAcc.toString()});
        final toolMsg = results
            .map(
              (r) => '[${r.call.tool}(${r.call.args})]\n${r.error ?? r.output}',
            )
            .join('\n\n');
        currentHistory.add({
          'role': 'user',
          'content': I18n.t('chat.tool_result_prompt', {'result': toolMsg}),
        });
        turn++;
      }
    } catch (e) {
      store.updateMessage(convId, placeholderId, '${I18n.t('chat.error')} $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  bool _shouldUpdateStreamUi(String key, String next, String previous) {
    if (next == previous) return false;
    if (next.length - previous.length >= 24) return true;
    final now = DateTime.now();
    final last = _lastStreamUiUpdates[key];
    if (last != null && now.difference(last).inMilliseconds < 80) return false;
    _lastStreamUiUpdates[key] = now;
    return true;
  }

  bool _handleSlashCommand(ChatStore store, String convId, String text) {
    final normalized = text.trim().toLowerCase();
    switch (normalized) {
      case '/clear':
        store.clearMessages(convId);
        return true;
      case '/settings':
        showSettingsDialog(context);
        return true;
      case '/help':
      case '/commands':
        _sendTo(store, convId, text: text, assistantText: _commandHelpText());
        return true;
      default:
        return false;
    }
  }

  String _expandSlashPrompt(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (lower == '/review' || lower.startsWith('/review ')) {
      final target = trimmed.length > '/review'.length
          ? trimmed.substring('/review'.length).trim()
          : I18n.t('command.review.default_target');
      return I18n.t('command.review.prompt', {'target': target});
    }
    if (lower == '/goal' || lower.startsWith('/goal ')) {
      final goal = trimmed.length > '/goal'.length
          ? trimmed.substring('/goal'.length).trim()
          : I18n.t('command.goal.default_goal');
      return I18n.t('command.goal.prompt', {'goal': goal});
    }
    if (lower == '/poor' || lower.startsWith('/poor ')) {
      final request = trimmed.length > '/poor'.length
          ? trimmed.substring('/poor'.length).trim()
          : I18n.t('command.poor.default_request');
      return I18n.t('command.poor.prompt', {'request': request});
    }
    if (lower == '/new' || lower.startsWith('/new ')) {
      final request = trimmed.length > '/new'.length
          ? trimmed.substring('/new'.length).trim()
          : I18n.t('command.new.default_request');
      return I18n.t('command.new.prompt', {'request': request});
    }
    return text;
  }

  String _commandHelpText() {
    return [
      '## ${I18n.t('command.help.title')}',
      '- `/clear` - ${I18n.t('command.clear')}',
      '- `/settings` - ${I18n.t('command.settings')}',
      '- `/review [target]` - ${I18n.t('command.review')}',
      '- `/goal <objective>` - ${I18n.t('command.goal')}',
      '- `/poor [request]` - ${I18n.t('command.poor')}',
      '- `/new <project>` - ${I18n.t('command.new')}',
    ].join('\n');
  }

  String _multiAgentStatus(
    List<String> agents,
    Set<String> completed, {
    required int round,
    required bool synthesizing,
    String? coordinatorNote,
  }) {
    final buf = StringBuffer();
    buf.writeln('## ${I18n.t('multi_agent.title')}');
    buf.writeln('Round $round');
    if (coordinatorNote != null && coordinatorNote.trim().isNotEmpty) {
      buf.writeln(coordinatorNote.trim());
      buf.writeln();
    }
    buf.writeln();
    for (final agent in agents) {
      final done = completed.contains(agent);
      buf.writeln(
        '- $agent: ${done ? I18n.t('multi_agent.done') : I18n.t('multi_agent.running')}',
      );
    }
    if (synthesizing) {
      buf.writeln();
      buf.writeln(I18n.t('multi_agent.synthesizing'));
    }
    return buf.toString().trim();
  }

  String _stripToolBlocks(String text) {
    var s = text.replaceAll(
      RegExp(r'\[正式输出\][\s\S]*?\[输出结束\]', multiLine: true),
      '',
    );
    s = s.replaceAll(
      RegExp(r'change_model\s*\(\s*work\s*\)', caseSensitive: false),
      '',
    );
    return s.trim();
  }

  void _sendTo(
    ChatStore store,
    String convId, {
    String text = '',
    String assistantText = '',
    List<Attachment> attachments = const [],
  }) {
    if (text.isNotEmpty || attachments.isNotEmpty) {
      store.addMessage(
        convId,
        Message(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}',
          sender: Sender.user,
          text: text,
          attachments: attachments,
        ),
      );
    }
    if (assistantText.isNotEmpty) {
      store.addMessage(
        convId,
        Message(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}_a',
          sender: Sender.assistant,
          text: assistantText,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 9, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            onKeyEvent: _handleKey,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              maxLines: 5,
              minLines: 1,
              enabled: !_sending,
              cursorColor: _accent,
              textInputAction: AppState.settingsOf(context).enterToSend
                  ? TextInputAction.send
                  : TextInputAction.newline,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: I18n.t('chat.placeholder'),
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          if (_controller.text.trim().startsWith('/')) ...[
            const SizedBox(height: 10),
            _CommandHints(accent: _accent),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              _iconBtn(
                icon: Icons.attach_file,
                tooltip: I18n.t('chat.attach'),
                onTap: _pickFile,
              ),
              const SizedBox(width: 4),
              _sendButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 19,
        color: AppColors.textSecondary,
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon),
      ),
    );
  }

  Widget _sendButton() {
    final enabled = _hasText && !_sending;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 34,
        height: 34,
        decoration: BoxDecoration(shape: BoxShape.circle, color: _accent),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? _send : null,
            child: _sending
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  )
                : Icon(Icons.arrow_upward, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

class _CommandHints extends StatelessWidget {
  const _CommandHints({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final commands = [
      ('/clear', I18n.t('command.clear')),
      ('/settings', I18n.t('command.settings')),
      ('/goal', I18n.t('command.goal')),
      ('/review', I18n.t('command.review')),
      ('/new', I18n.t('command.new')),
      ('/poor', I18n.t('command.poor')),
      ('/help', I18n.t('command.help')),
    ];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final (cmd, label) in commands)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Text(
              '$cmd  $label',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ),
      ],
    );
  }
}
