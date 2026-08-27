import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/agent.dart';
import '../services/agent_runtime.dart';
import '../services/ai_providers.dart';
import '../services/git_service.dart';
import '../services/memory_service.dart';
import '../services/prompts.dart';
import '../services/provider_stats.dart';
import '../services/rollback_service.dart';
import '../services/round_changes.dart';
import '../services/settings_store.dart';
import '../services/task_queue_service.dart';
import '../services/token_saver.dart';
import '../services/token_stats.dart';
import '../services/workspace_manager.dart';
import '../state/chat_store.dart';
import '../state/round_changes_store.dart';
import '../theme.dart';
import '../widgets/dialogs/settings_dialog.dart';
import '../widgets/dialogs/task_center_dialog.dart';
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
    this.workspaceDir,
    this.regenerateDraft,
    this.replyDraft,
    this.onModeChanged,
  });

  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color? accent;
  final Color? accentSoft;
  final String? conversationId;

  /// 新建对话时使用的工作空间目录；已有对话时传入对话已保存的目录。
  final String? workspaceDir;

  /// 外部请求“重新生成”时填入的用户消息文本（由 HomePage 注入）。
  final ValueNotifier<String?>? regenerateDraft;

  /// B03：消息引用/回复目标（由气泡菜单注入）。
  final ValueNotifier<ReplyTarget?>? replyDraft;

  final ValueChanged<WorkMode>? onModeChanged;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

/// B03：被引用的消息。
class ReplyTarget {
  ReplyTarget({required this.sender, required this.preview});

  final Sender sender;
  final String preview;

  String get label => sender == Sender.user
      ? I18n.t('chat.you')
      : I18n.t('chat.assistant');
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;
  bool _sending = false;
  bool _dragging = false;
  int _lastHistoryTokens = 0;
  ReplyTarget? _replyTo;
  final Map<String, DateTime> _lastStreamUiUpdates = {};
  final Set<StreamSubscription<String>> _activeSubs = {};
  final Set<String> _autoSwitchedFor = <String>{};
  Completer<void>? _activeCancel;
  Map<String, dynamic>? _resumeCheckpoint;

  Color get _accent => widget.accent ?? AppColors.primary;

  @override
  void initState() {
    super.initState();
    widget.regenerateDraft?.addListener(_onRegenerateDraft);
    widget.replyDraft?.addListener(_onReplyDraft);
    _controller.addListener(() {
      final v = _controller.text.trim().isNotEmpty;
      if (v != _hasText) setState(() => _hasText = v);
    });
    _focus.addListener(_onFocusChanged);
    TaskQueueService.instance.addListener(_onTaskQueue);
  }

  void _onTaskQueue() {
    if (_sending) return;
    final convId = widget.conversationId;
    if (convId == null) return;
    final checkpoint = TaskQueueService.instance.consumeResume(convId);
    if (checkpoint == null || checkpoint.isEmpty) return;
    _resumeCheckpoint = checkpoint;
    final modeName = (checkpoint['mode'] ?? '').toString();
    if (modeName.isNotEmpty) {
      widget.onModeChanged?.call(
        WorkMode.values.firstWhere(
          (m) => m.name == modeName,
          orElse: () => widget.mode,
        ),
      );
    }
    _controller.text = I18n.t('task.resume_prompt');
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  void _onReplyDraft() {
    final target = widget.replyDraft?.value;
    if (target == null) return;
    setState(() => _replyTo = target);
    _focus.requestFocus();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onRegenerateDraft() {
    final draft = widget.regenerateDraft?.value;
    if (draft == null || draft.trim().isEmpty) return;
    widget.regenerateDraft?.value = null;
    _controller.text = draft;
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    widget.regenerateDraft?.removeListener(_onRegenerateDraft);
    widget.replyDraft?.removeListener(_onReplyDraft);
    _focus.removeListener(_onFocusChanged);
    TaskQueueService.instance.removeListener(_onTaskQueue);
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
    // Enter 发送模式：Enter 发送、Shift+Enter 换行；
    // Enter 换行模式：Shift+Enter 发送、Enter 换行。
    final shouldSend = enterToSend != shift;
    if (shouldSend) {
      _send();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final pf = picked.files.first;
    final path = pf.path;
    if (path == null) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.t('attach.error.read', {'name': pf.name}))),
      );
      return;
    }
    await _attachFile(path);
  }

  /// B04：系统文件拖拽到输入区直接附加发送（desktop_drop 原生支持）。
  Future<void> _handleDroppedFiles(List<XFile> files) async {
    for (final f in files) {
      final path = f.path;
      if (path.isEmpty) continue;
      if (!File(path).existsSync()) continue;
      await _attachFile(path);
    }
  }

  Future<void> _attachFile(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = File(path);
    if (!await file.exists()) return;

    final size = await file.length();
    if (size > 5 * 1024 * 1024) {
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.t('attach.too_large', {'name': path}))),
      );
      return;
    }

    final bytes = await file.readAsBytes();
    final isBinary = _looksBinary(bytes);
    if (isBinary) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(I18n.t('attach.error.binary', {'name': path})),
        ),
      );
      return;
    }

    final name = path.split(Platform.pathSeparator).last;
    final text = utf8.decode(bytes, allowMalformed: true);
    final attach = Attachment(
      name: name,
      size: size,
      mimeType: _guessMime(path),
      content: text,
    );

    if (!mounted) return;
    final store = AppState.chatOf(context);
    final convId = widget.conversationId;
    if (convId == null) {
      final id = store.newConversation(workspaceDir: widget.workspaceDir);
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
    final roundChanges = AppState.roundChangesOf(context);
    final toolRuntime = ToolRuntime(settings: settings);
    var text = _controller.text.trim();
    if (text.isEmpty) return;

    // B03：引用回复——把被引用消息作为引用块前缀发送。
    final reply = _replyTo;
    if (reply != null) {
      text = '> ${reply.label}：${reply.preview}\n\n$text';
      _replyTo = null;
      widget.replyDraft?.value = null;
    }

    final convId =
        widget.conversationId ??
        store.newConversation(workspaceDir: widget.workspaceDir);
    if (widget.conversationId == null) store.activate(convId);

    if (_handleSlashCommand(store, convId, text)) {
      _controller.clear();
      return;
    }

    // 关键：新会话会立刻重建本组件并 dispose 控制器。
    // 必须在任何 await 之前清空，否则稍后 clear() 会触发
    // “TextEditingController used after being disposed”崩溃。
    _controller.clear();

    // A04：登记任务；取消时保存检查点供 A05 续跑。
    final task = await TaskQueueService.instance.start(convId, text);
    Map<String, dynamic>? checkpoint;

    // A12：附加工作区目录（可读写，路径校验生效）。
    List<String> extraDirs = const [];
    for (final c in store.conversations) {
      if (c.id == convId) {
        extraDirs = c.additionalWorkspaces;
        break;
      }
    }

    final effectiveText = _expandSlashPrompt(text);
    // A17：轻量自动提取用户偏好。
    if (settings.memoryEnabled) {
      final pref = MemoryService.instance.maybeExtractPreference(effectiveText);
      if (pref != null) {
        unawaited(MemoryService.instance.add(pref, kind: 'preference'));
      }
    }

    // 解析对话工作目录（新建对话时从 store 中取回最终路径），并确保目录存在。
    String? workspace;
    for (final c in store.conversations) {
      if (c.id == convId) {
        workspace = c.workspaceDir;
        break;
      }
    }
    if (workspace != null && workspace.trim().isNotEmpty) {
      try {
        await WorkspaceManager.ensure(workspace);
      } catch (_) {
        // 目录创建失败不阻塞对话，工具调用会自己报错。
      }
    }

    // 多供应商路由：任一角色的路由 Key 已填即可发送，无需全局 Key。
    final hasAnyKey =
        settings.apiKey.trim().isNotEmpty ||
        settings.providerRoutes.any(
          (r) => (r['apiKey'] ?? '').toString().trim().isNotEmpty,
        );
    if (!hasAnyKey) {
      _sendTo(
        store,
        convId,
        text: effectiveText,
        assistantText: I18n.t('chat.no_key'),
      );
      return;
    }

    final userMsg = Message(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      sender: Sender.user,
      text: effectiveText,
    );
    store.addMessage(convId, userMsg);

    var placeholderId = 'm_${DateTime.now().microsecondsSinceEpoch}_a';
    final placeholder = Message(
      id: placeholderId,
      sender: Sender.assistant,
      text: I18n.t('chat.connecting'),
    );
    store.addMessage(convId, placeholder);

    // 记录本轮开始前的工作目录快照，输出结束后用于生成“本轮更改”摘要。
    // 该功能可在设置中关闭；关闭时不做快照，避免额外开销。
    WorkspaceSnapshot? beforeSnapshot;
    final fileActions = <String, Set<String>>{};
    if (settings.showRoundChanges) {
      try {
        beforeSnapshot = await WorkspaceSnapshot.capture(rootPath: workspace);
      } catch (_) {
        beforeSnapshot = null;
      }
    }
    // A07：保留本轮开始前的文本快照，供 /rollback 一键回滚。
    if (beforeSnapshot != null) {
      RollbackService.instance.capture(
        convId,
        beforeSnapshot,
        baseDir: workspace,
      );
    }

    if (mounted) setState(() => _sending = true);
    final cancel = Completer<void>();
    _activeCancel = cancel;

    // G09：记录本次请求耗时与结果。
    final reqWatch = Stopwatch()..start();
    var reqFailed = false;
    String? convModel;
    for (final c in store.conversations) {
      if (c.id == convId) {
        convModel = c.model;
        break;
      }
    }
    // 多供应商路由：按思考档位动态选择供应商/模型/Key；
    // 未配置时回退到全局供应商。
    final route = settings.resolveRoute(widget.thinking);
    final client = route != null
        ? AiClient(
            config: route.provider.withBaseUrl(route.provider.baseUrl),
            apiKeys: [route.apiKey],
          )
        : settings.client;
    final effectiveModel = route?.model ?? _effectiveModel(convModel, settings);

    try {
      final history = _buildHistory(
        store,
        convId,
        placeholderId,
        settings.costMode,
      );
      // G07：上下文用量指示（估算）。
      var histTokens = 0;
      for (final m in history) {
        histTokens += estimateTokens((m['content'] as String?) ?? '');
      }
      if (mounted) setState(() => _lastHistoryTokens = histTokens);
      var systemPrompt = Prompts.build(
        mode: widget.mode,
        thinking: widget.thinking,
        costMode: settings.costMode,
        preset: settings.preset,
        workspaceDir: workspace,
        lean: settings.costMode != CostMode.max,
      );
      final extraTools = await toolRuntime.describeExtraToolsAsync();
      if (extraTools.isNotEmpty) {
        systemPrompt = '$systemPrompt\n\n$extraTools';
      }
      // A17：记忆注入。
      if (settings.memoryEnabled) {
        final memory = await MemoryService.instance.injectPromptText(
          maxChars: TokenSaver.maxMemoryChars(settings.costMode),
        );
        if (memory.isNotEmpty) {
          systemPrompt = '$systemPrompt\n\n$memory';
        }
      }
      if (extraDirs.isNotEmpty) {
        systemPrompt =
            '$systemPrompt\n\n## Additional Workspaces\n${extraDirs.join('\n')}';
      }
      systemPrompt = '$systemPrompt\n\n## Extra Built-in Tools\n'
          '- screenshot(""): capture the screen to a PNG file (vision models get the image attached to the next turn)\n'
          '- sql("path|||SELECT ..."): read-only query a SQLite database or CSV file\n'
          '- zip("src|||dst.zip"): compress file/directory\n'
          '- unzip("archive.zip|||dest"): extract archive\n'
          '- desktop_dump(""): dump the foreground window as a numbered text map (use desktop_dump("all") for the whole screen)\n'
          '- desktop_ocr(""): OCR the screen into text with coordinates (for images/canvas the map misses)\n'
          '- desktop_click("x,y"): click at screen coordinates\n'
          '- desktop_type("text"): type into the focused field\n'
          '- desktop_key("^s"): send a key combo\n'
          '- desktop_open("app, URL or file"): open it\n'
          '- desktop_scroll("x,y,delta"): scroll at coordinates\n'
          '- desktop_wait("500"): wait milliseconds\n'
          'Desktop actions are confirmed with you first.\n'
          'For file content with quotes/newlines/large size, use writefile("path|||base64:<base64>") to avoid escaping issues.';
      if (isVisionModel(effectiveModel)) {
        systemPrompt =
            '$systemPrompt\n\n## Vision\nYou can see images: call screenshot("") to look at the screen; the image is attached to your next request automatically.';
      } else {
        systemPrompt =
            '$systemPrompt\n\n## Text-only Desktop\nUse desktop_dump("") to read the screen map; if it is sparse (images/canvas), use desktop_ocr("") for text with coordinates.';
      }
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
      final maxTurns = TokenSaver.maxTurns(settings.costMode);
      // 视觉模型：最近一次截图按 base64 附加到下一轮请求。
      String? screenBase64;
      final extraToolNames = await toolRuntime.extraToolNamesAsync();
      var currentHistory = List<Map<String, dynamic>>.from(history);
      // A05：续跑时用检查点里的对话历史与轮次继续，而不是从头再来。
      if (_resumeCheckpoint != null) {
        final cp = _resumeCheckpoint;
        _resumeCheckpoint = null;
        final cpHistory = cp?['history'];
        if (cpHistory is List) {
          currentHistory = [
            for (final m in cpHistory)
              if (m is Map) Map<String, dynamic>.from(m),
          ];
          final cpTurn = (cp?['turn'] as num?)?.toInt() ?? 0;
          turn = cpTurn < 0 ? 0 : (cpTurn > maxTurns ? maxTurns : cpTurn);
        }
      }

      if (widget.thinking == ThinkingLevel.flagship &&
          settings.costMode != CostMode.poor) {
        FlagshipAgentPlan plan;
        try {
          plan = await AgentRunner.planFlagshipSession(
            chat: (system, messages) => _cancellable(
              client.chatStream(
                ChatRequest(
                  system: system,
                  messages: messages,
                  model: effectiveModel,
                  maxTokens: coordinatorMaxTokens,
                  temperature: _requestTemperature(effectiveModel, settings),
                ),
              ),
              cancel,
            ),
            history: currentHistory,
            isEnglish: isEnglish,
            customAgents: settings.customAgents,
          );
        } on TimeoutException {
          // 主协调规划超时：退回默认协作方案，避免卡死在“规划中”。
          plan = FlagshipAgentPlan.fallback(isEnglish);
        }
        if (cancel.isCompleted) return;
        // 主协调开场白：告诉用户接下来会协调多个子代理。
        store.updateMessage(
          convId,
          placeholderId,
          I18n.t('multi_agent.announcement'),
          persist: false,
        );

        final allResults = <CollaborativeAgentResult>[];
        for (var round = 1; round <= maxFlagshipRounds; round++) {
          if (cancel.isCompleted) break;
          if (plan.complete || plan.items.isEmpty) break;
          final plannedAgents = plan.items
              .map(
                (item) => AgentRunner.agentFromPlanItemWithCustom(
                  item,
                  settings.customAgents,
                ),
              )
              .toList();
          final planById = {for (final item in plan.items) item.agentId: item};

          Future<CollaborativeAgentResult> runAgent(
            CollaborativeAgent agent,
          ) async {
            final focus = planById[agent.id]?.focus ?? '';
            final subSystem = AgentRunner.flagshipAgentSystemPrompt(
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
            var lastSubVisible = '';
            try {
              // 子代理拥有自己的思维链，并且可以调用工具（command 除外）；
              // 主协调把任务像用户消息一样下发给它。
              final outcome = await AgentRunner.runFlagshipAgent(
                chat: (system, messages) => _cancellable(
                  client.chatStream(
                    ChatRequest(
                      system: system,
                      messages: messages,
                      model: effectiveModel,
                      maxTokens: subAgentMaxTokens,
                      temperature: _requestTemperature(effectiveModel, settings),
                    ),
                  ),
                  cancel,
                ),
                systemPrompt: subSystem,
                messages: [
                  ...currentHistory,
                  {
                    'role': 'user',
                    'content': AgentRunner.flagshipAgentTaskMessage(
                      focus: focus,
                      coordinatorNote: plan.coordinatorNote,
                      isEnglish: isEnglish,
                    ),
                  },
                ],
                cwd: workspace,
                onCommandRequest: (command) async {
                  if (!mounted) return false;
                  final allow = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AppColors.surface,
                      title: Text(
                        I18n.t('dialog.subagent_command.title'),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            I18n.t('dialog.subagent_command.body'),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.bg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              command,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(
                            I18n.t('dialog.command.deny'),
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          child: Text(I18n.t('dialog.command.allow')),
                        ),
                      ],
                    ),
                  );
                  return allow == true;
                },
                onThinking: (text) {
                  if (!_shouldUpdateStreamUi(subMsgId, text, lastSubVisible)) {
                    return;
                  }
                  lastSubVisible = text;
                  store.updateMessage(
                    convId,
                    subMsgId,
                    text,
                    persist: false,
                  );
                },
              );
              final body = <String>[
                if (outcome.output.trim().isNotEmpty) outcome.output.trim(),
                if (outcome.toolTrace.trim().isNotEmpty)
                  '\n[工具使用]\n${outcome.toolTrace.trim()}',
              ].join('\n');
              if (outcome.thinking != lastSubVisible) {
                store.updateMessage(
                  convId,
                  subMsgId,
                  outcome.thinking,
                  persist: false,
                );
              }
              store.finishToolMessage(convId, subMsgId, body, outcome.ok);
              return CollaborativeAgentResult(
                agent: agent,
                output: body,
                error: outcome.error,
              );
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
              return result;
            }
          }

          final roundResults = await Future.wait(plannedAgents.map(runAgent));
          allResults.addAll(roundResults);
          if (cancel.isCompleted) break;

          // 所有子代理都失败或没有产出：不再空转第二轮，直接进入综合。
          final allFailed = roundResults.every(
            (r) => _toolOutputFailed(r.error, r.output),
          );
          if (allFailed) {
            plan = FlagshipAgentPlan(
              items: const [],
              coordinatorNote: '',
              complete: true,
              finalInstruction: '',
            );
            break;
          }

          try {
            plan = await AgentRunner.planFlagshipRound(
              chat: (system, messages) => _cancellable(
                client.chatStream(
                  ChatRequest(
                    system: system,
                    messages: messages,
                    model: effectiveModel,
                    maxTokens: coordinatorMaxTokens,
                  ),
                ),
                cancel,
              ),
              history: currentHistory,
              previousResults: roundResults,
              round: round,
              isEnglish: isEnglish,
              customAgents: settings.customAgents,
            );
          } on TimeoutException {
            // 主协调综合超时：视为本轮信息已足够，直接进入最终综合。
            plan = FlagshipAgentPlan(
              items: const [],
              coordinatorNote: '',
              complete: true,
              finalInstruction: '',
            );
          } catch (_) {
            // 主协调规划异常（如流错误）：同样按“信息已足够”收尾，避免卡死。
            plan = FlagshipAgentPlan(
              items: const [],
              coordinatorNote: '',
              complete: true,
              finalInstruction: '',
            );
          }
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
        // “我将开始综合”提示 + 最终答案各自独立成条，
        // 让工具气泡按时间顺序排列，不被堆到正式输出底部。
        store.addMessage(
          convId,
          Message(
            id: 'm_${DateTime.now().microsecondsSinceEpoch}_synth_note',
            sender: Sender.assistant,
            text: I18n.t('multi_agent.synthesize_start'),
          ),
        );
        placeholderId = 'm_${DateTime.now().microsecondsSinceEpoch}_synth';
        store.addMessage(
          convId,
          Message(
            id: placeholderId,
            sender: Sender.assistant,
            text: I18n.t('chat.connecting'),
          ),
        );
      }

      var answered = false;
      // 工具轮次用完后仍保留一轮最终收尾，避免“执行完直接结束”。
      while (turn < maxTurns + 1) {
        checkpoint = {
          'history': List<Map<String, dynamic>>.from(currentHistory),
          'turn': turn,
          'workspace': workspace,
          'mode': widget.mode.name,
          'thinking': widget.thinking.name,
        };
        if (cancel.isCompleted) break;
        final req = ChatRequest(
          system: systemPrompt,
          messages: currentHistory,
          model: _modelFor(widget.thinking, effectiveModel, settings),
          maxTokens: finalMaxTokens,
          temperature: _requestTemperature(effectiveModel, settings),
        );
        final rawAcc = StringBuffer();
        var lastVisible = '';
        await _collectStream(
          cancel,
          _chatWithRetry(cancel, () => client.chatStream(req)),
          (chunk) {
            rawAcc.write(chunk);
            final visible = _stripToolBlocks(rawAcc.toString());
            if (_shouldUpdateStreamUi(placeholderId, visible, lastVisible)) {
              lastVisible = visible;
              store.updateMessage(
                convId,
                placeholderId,
                visible,
                persist: false,
              );
            }
          },
        );
        if (cancel.isCompleted) break;
        _maybeAutoSwitchToWork(rawAcc.toString(), placeholderId);
        final finalVisible = _stripToolBlocks(rawAcc.toString());
        if (finalVisible != lastVisible) {
          store.updateMessage(
            convId,
            placeholderId,
            finalVisible,
            persist: false,
          );
        }

        final rawText = rawAcc.toString();
        if (rawText.trim().isEmpty) {
          store.updateMessage(
            convId,
            placeholderId,
            I18n.t('chat.stream_empty'),
            persist: false,
          );
          answered = true;
          break;
        }
        final isFinal = rawText.contains('[最后输出]');
        final calls = isFinal
            ? const <AgentToolCall>[]
            : AgentRunner.parse(
                rawText,
                extraTools: extraToolNames,
              );
        if (settings.debugMode) {
          final summary = StringBuffer()
            ..writeln(I18n.t('debug.round', {'n': '$turn'}))
            ..writeln('raw长度: ${rawText.length}')
            ..writeln('isFinal: $isFinal')
            ..writeln('解析工具数: ${calls.length}')
            ..writeln('hasToolBlock: ${AgentRunner.hasToolBlock(rawText)}');
          store.addMessage(
            convId,
            Message(
              id: 'm_${DateTime.now().microsecondsSinceEpoch}_dbg',
              sender: Sender.tool,
              text: summary.toString().trim(),
              toolName: 'debug',
              toolArgs: summary.toString().trim(),
              toolResult: rawText,
              toolOk: true,
            ),
          );
        }
        final thinking = widget.thinking;
        if (calls.isEmpty &&
            !isFinal &&
            thinking != ThinkingLevel.fast &&
            AgentRunner.hasToolBlock(rawText)) {
          // 有工具块但一个调用都没解析出来：显示错误并让模型重试一次，
          // 避免“模型以为写了文件、实际什么都没发生”的静默失败。
          final errMsgId =
              'm_${DateTime.now().microsecondsSinceEpoch}_parse_err';
          store.addMessage(
            convId,
            Message(
              id: errMsgId,
              sender: Sender.tool,
              text: '',
              toolName: 'parse',
              toolArgs: rawAcc.toString(),
              toolRunning: true,
            ),
          );
          final parseRaw = rawAcc.toString();
          final parseSnippet = parseRaw.length > 300
              ? parseRaw.substring(0, 300)
              : parseRaw;
          store.finishToolMessage(
            convId,
            errMsgId,
            I18n.t('agent.error.tool_block_parse_failed', {
              'snippet': parseSnippet,
            }),
            false,
          );
          currentHistory.add({
            'role': 'assistant',
            'content': rawAcc.toString(),
          });
          currentHistory.add({
            'role': 'user',
            'content': I18n.t('chat.tool_block_retry_prompt'),
          });
          turn++;
          if (turn < maxTurns) {
            placeholderId = 'm_${DateTime.now().microsecondsSinceEpoch}_a';
            store.addMessage(
              convId,
              Message(
                id: placeholderId,
                sender: Sender.assistant,
                text: I18n.t('chat.connecting'),
              ),
            );
          }
          continue;
        }
        // FAST 档位按提示词禁止使用任何工具：即使模型输出了工具块也不执行。
        if (thinking == ThinkingLevel.fast) {
          answered = true;
          break;
        }
        if (calls.isEmpty) {
          answered = true;
          break;
        }

        // 完全相同参数的重复调用只执行一次，避免重复副作用并节省 token。
        final seen = <String>{};
        final unique = <AgentToolCall>[];
        final results = <AgentResult>[];
        for (final call in calls) {
          final key = '${call.tool}\u0000${call.args}';
          if (seen.add(key)) {
            unique.add(call);
          } else {
            results.add(
              AgentResult(
                call: call,
                output: I18n.t('chat.tool_duplicate_skipped'),
              ),
            );
          }
        }
        final commands = unique.where((c) => c.tool == 'command').toList();
        final allowCommands = commands.isEmpty
            ? null
            : await _confirmBatchCommands(commands);
        final desktopActions = unique
            .where((c) => AgentRunner.isDesktopTool(c.tool))
            .toList();
        final allowDesktop = desktopActions.isEmpty
            ? null
            : await _confirmDesktopActions(desktopActions);
        for (final call in unique) {
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
          final AgentResult r;
          if (call.tool == 'command' && allowCommands == false) {
            r = AgentResult(
              call: call,
              output: '',
              error: I18n.t(
                'agent.error.command_cancelled',
                {'command': call.args},
              ),
            );
          } else if (call.tool == 'command' && allowCommands == true) {
            r = await toolRuntime.execute(
              call,
              cwd: workspace,
              conversationId: convId,
              commandConfirmed: true,
              extraAllowedDirs: extraDirs,
              onFileConfirm: (c, preview) => _confirmFileChange(c, preview),
            );
          } else if (AgentRunner.isDesktopTool(call.tool)) {
            if (allowDesktop == false) {
              r = AgentResult(
                call: call,
                output: '',
                error: I18n.t(
                  'agent.error.desktop_cancelled',
                  {'action': call.args},
                ),
              );
            } else {
              r = await toolRuntime.execute(
                call,
                cwd: workspace,
                conversationId: convId,
                commandConfirmed: true,
                extraAllowedDirs: extraDirs,
                onFileConfirm: (c, preview) => _confirmFileChange(c, preview),
              );
            }
          } else {
            r = await _executeCall(
              call,
              cwd: workspace,
              runtime: toolRuntime,
              conversationId: convId,
              extraAllowedDirs: extraDirs,
            );
          }
          results.add(r);
          // 视觉模型：截图成功后读取图片，下一轮请求自动附加。
          if (r.ok &&
              call.tool == 'screenshot' &&
              isVisionModel(effectiveModel)) {
            final shotPath = r.output.trim();
            try {
              final f = File(shotPath);
              if (await f.exists() && await f.length() <= 8 * 1024 * 1024) {
                screenBase64 = base64Encode(await f.readAsBytes());
              }
            } catch (_) {}
          }
          TaskQueueService.instance.updateProgress(
            task.id,
            '${call.tool}(${_clipArg(call.args)})',
          );
          if (r.ok &&
              (call.tool == 'writefile' || call.tool == 'replacefile')) {
            final parts = call.args.split('|||');
            if (parts.isNotEmpty) {
              final key = WorkspaceSnapshot.normalizePath(
                parts.first.trim(),
                base: workspace,
              );
              fileActions
                  .putIfAbsent(key, () => <String>{})
                  .add(call.tool == 'writefile' ? 'created' : 'modified');
            }
          }
          store.finishToolMessage(convId, toolMsgId, r.error ?? r.output, r.ok);
        }

        currentHistory.add({'role': 'assistant', 'content': rawAcc.toString()});
        // 全部失败时附加明确指令，避免模型继续空转重试浪费 token。
        final allFailed = results.isNotEmpty &&
            results.every((r) => _toolOutputFailed(r.error, r.output));
        final toolMsg = results
                .map(
                  (r) => '[${r.call.tool}(${r.call.args})]\n'
                      '${TokenSaver.compactToolResult(r.error ?? r.output, settings.costMode)}',
                )
                .join('\n\n') +
            (allFailed ? '\n\n${I18n.t('chat.tool_all_failed_hint')}' : '');
        final toolPrompt = I18n.t(
          'chat.tool_result_prompt',
          {'result': toolMsg},
        );
        final toolContent = (screenBase64 != null &&
                isVisionModel(effectiveModel))
            ? <Map<String, dynamic>>[
                {'type': 'text', 'text': toolPrompt},
                {
                  'type': 'image',
                  'media_type': 'image/png',
                  'data': screenBase64!,
                },
              ]
            : toolPrompt;
        currentHistory.add({
          'role': 'user',
          'content': toolContent,
        });
        turn++;
        if (turn < maxTurns + 1) {
          // 下一轮回答另起一条助手消息，工具气泡保持在两轮之间的正确位置。
          placeholderId = 'm_${DateTime.now().microsecondsSinceEpoch}_a';
          store.addMessage(
            convId,
            Message(
              id: placeholderId,
              sender: Sender.assistant,
              text: I18n.t('chat.connecting'),
            ),
          );
        }
      }

      if (settings.debugMode && !cancel.isCompleted) {
        store.addMessage(
          convId,
          Message(
            id: 'm_${DateTime.now().microsecondsSinceEpoch}_dbg_end',
            sender: Sender.tool,
            text: '${I18n.t('tool.debug')}: answered=$answered',
            toolName: 'debug',
            toolArgs: 'answered=$answered',
            toolResult: 'answered=$answered',
            toolOk: true,
          ),
        );
      }

      // 兜底：工具轮次全部用完后仍没有最终回答，强制收尾一轮。
      if (!answered && !cancel.isCompleted) {
        final finalReq = ChatRequest(
          system: systemPrompt,
          messages: [
            ...currentHistory,
            {
              'role': 'user',
              'content': I18n.t('chat.finalize_prompt'),
            },
          ],
          model: _modelFor(widget.thinking, effectiveModel, settings),
          maxTokens: finalMaxTokens,
          temperature: _requestTemperature(effectiveModel, settings),
        );
        store.updateMessage(
          convId,
          placeholderId,
          I18n.t('chat.connecting'),
          persist: false,
        );
        try {
          final raw = StringBuffer();
          await _collectStream(
            cancel,
            _chatWithRetry(cancel, () => client.chatStream(finalReq)),
            (chunk) {
              raw.write(chunk);
              store.updateMessage(
                convId,
                placeholderId,
                _stripToolBlocks(raw.toString()),
                persist: false,
              );
            },
          );
        } catch (e) {
          store.updateMessage(
            convId,
            placeholderId,
            '${I18n.t('chat.error')} $e',
          );
        }
      }

      if (!cancel.isCompleted && settings.showRoundChanges) {
        await _appendRoundSummary(
          store,
          convId,
          beforeSnapshot,
          fileActions,
          roundChanges,
          workspace,
        );
      }
      if (!cancel.isCompleted) {
        // A07：记录本轮由 AI 创建的新文件，供 /rollback 一并删除。
        RollbackService.instance.recordCreated(convId, workspace, fileActions);
        // D06：可选自动暂存/提交。
        if (settings.autoStage && workspace != null) {
          try {
            await GitService.stageAll(path: workspace);
            if (settings.autoCommit) {
              await GitService.commit(task.title, path: workspace);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      reqFailed = true;
      store.updateMessage(convId, placeholderId, '${I18n.t('chat.error')} $e');
    } finally {
      // G09：记录本次请求的延迟与成败（供应商状态统计）。
      ProviderStatsService.instance.record(
        providerId: settings.providerId,
        model: effectiveModel,
        ok: !cancel.isCompleted && !reqFailed,
        latencyMs: reqWatch.elapsedMilliseconds,
      );
      if (mounted) setState(() => _sending = false);
      if (identical(_activeCancel, cancel)) _activeCancel = null;
      if (reqFailed) {
        TaskQueueService.instance.markFailed(task.id, I18n.t('chat.error'));
      } else if (cancel.isCompleted) {
        TaskQueueService.instance.cancelTask(task.id, checkpoint: checkpoint);
      } else {
        TaskQueueService.instance.markFinished(task.id);
      }
      if (cancel.isCompleted) {
        String current = '';
        var isAnnouncement = false;
        for (final c in store.conversations) {
          if (c.id == convId) {
            for (final m in c.messages) {
              if (m.id == placeholderId) {
                current = m.text;
                isAnnouncement =
                    current == I18n.t('multi_agent.announcement');
                break;
              }
            }
            break;
          }
        }
        final marker = I18n.t('chat.cancelled');
        if (isAnnouncement) {
          // 取消发生在子代理阶段：公告气泡保持干净，
          // 取消标记另起一条助手消息，避免贴到公告上。
          store.addMessage(
            convId,
            Message(
              id: 'm_${DateTime.now().microsecondsSinceEpoch}_cancelled',
              sender: Sender.assistant,
              text: marker,
            ),
          );
        } else {
          store.updateMessage(
            convId,
            placeholderId,
            current.isEmpty ? marker : '$current\n\n$marker',
          );
        }
      }
    }
  }

  /// 单次请求的历史字符预算：超长时从最早的对话开始丢弃，
  /// 避免长对话把上下文塞满、浪费 token。
  /// 单个附件内容嵌入上下文的字符上限。
  static const int _maxAttachmentChars = 6000;

  /// 构建发送给 AI 的对话历史。对话被删除时抛出异常，
  /// 由 _send 的 try/finally 统一收尾（不会卡死发送状态）。
  List<Map<String, dynamic>> _buildHistory(
    ChatStore store,
    String convId,
    String placeholderId,
    CostMode costMode,
  ) {
    Conversation? conv;
    for (final c in store.conversations) {
      if (c.id == convId) {
        conv = c;
        break;
      }
    }
    if (conv == null) {
      throw StateError('conversation $convId not found');
    }
    final history = <Map<String, dynamic>>[];
    for (final m in conv.messages) {
      if (m.id == placeholderId) continue;
      if (m.sender == Sender.system) continue;
      if (m.sender == Sender.tool) continue;
      final content = StringBuffer();
      if (m.attachments.isNotEmpty) {
        for (final a in m.attachments) {
          content.writeln('📎 ${a.name} (${a.mimeType}, ${a.size}B):\n');
          final body = a.content.length > _maxAttachmentChars
              ? '${a.content.substring(0, _maxAttachmentChars)}\n${I18n.t('agent.truncated')}'
              : a.content;
          content.writeln(body);
        }
      }
      content.writeln(m.text);
      history.add({
        'role': m.sender == Sender.user ? 'user' : 'assistant',
        'content': content.toString().trim(),
      });
    }
    return _trimHistoryForBudget(history, conv.summary, costMode);
  }

  /// 超过 token 预算时，先压缩超长消息，再从最早的对话开始裁剪，
  /// 并用对话摘要（或省略说明）替代被丢弃的旧消息。
  List<Map<String, dynamic>> _trimHistoryForBudget(
    List<Map<String, dynamic>> history,
    String? summary,
    CostMode costMode,
  ) {
    final summaryText = (summary?.trim().isNotEmpty == true)
        ? I18n.t('chat.history_summary', {'summary': summary!.trim()})
        : I18n.t('chat.history_omitted');
    return TokenSaver.trimHistory(history, costMode, summaryNote: summaryText);
  }

  static String _fmtTokens(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }

  /// 判断工具输出是否代表“失败”。
  /// 工具层把多数错误以文本形式返回（error 为 null），
  /// 需要识别已知错误前缀和退出码，否则“全部失败”检测会失效。
  bool _toolOutputFailed(String? error, String output) {
    if (error != null) return true;
    final out = output.trim();
    if (out.isEmpty) return true;
    final lower = out.toLowerCase();
    for (final p in const [
      '[错误', '[已拦截', '[解析失败', '[认证失败',
      '[error', '[blocked', '[parse failed', '[auth failed',
    ]) {
      if (lower.startsWith(p)) return true;
    }
    final exit = RegExp(r'\[exit (-?\d+)\]').firstMatch(lower);
    if (exit != null && exit.group(1) != '0') return true;
    return false;
  }

  String _clipArg(String s) =>
      s.length > 80 ? '${s.substring(0, 80)}...' : s;

  Widget _mdButton(String prefix, String suffix, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () => _insertMarkdown(prefix, suffix),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final selected = text.substring(start, end);
    final replacement = '$prefix$selected$suffix';
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(
        offset: start + prefix.length + selected.length + suffix.length,
      ),
    );
    _focus.requestFocus();
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

  /// 输出结束后，把本轮实际发生的文件变化追加到本轮最后一条消息末尾。
  Future<void> _appendRoundSummary(
    ChatStore store,
    String convId,
    WorkspaceSnapshot? before,
    Map<String, Set<String>> fileActions,
    RoundChangesStore roundChanges,
    String? workspace,
  ) async {
    try {
      final lines = <String>[];
      if (before != null) {
        final after = await WorkspaceSnapshot.capture(rootPath: workspace);
        final changes = before.diff(after);
        for (final change in changes) {
          change.actions.addAll(
            fileActions[
                WorkspaceSnapshot.normalizePath(change.path, base: workspace)] ??
                const <String>{},
          );
          if (change.deleted) {
            lines.add('${change.path} -');
            continue;
          }
          final counts = (change.added != null && change.removed != null)
              ? ' +${change.added} -${change.removed}'
              : '';
          final action = change.actions.contains('created')
              ? (change.actions.contains('modified')
                    ? I18n.t('round_summary.created_modified')
                    : I18n.t('round_summary.created'))
              : I18n.t('round_summary.modified');
          lines.add('${change.path}$counts [ $action ]');
        }
      }

      // 快照失败但工具调用成功过：用工具记录兜底展示。
      if (lines.isEmpty && fileActions.isNotEmpty) {
        for (final entry in fileActions.entries) {
          final actions = entry.value;
          final action = actions.contains('created')
              ? (actions.contains('modified')
                    ? I18n.t('round_summary.created_modified')
                    : I18n.t('round_summary.created'))
              : I18n.t('round_summary.modified');
          lines.add('${entry.key} [ $action ]');
        }
      }

      // 没有任何变更时也输出一行，确保每轮都有总结。
      if (lines.isEmpty) {
        lines.add(I18n.t('round_summary.none'));
      }

      // “本轮更改”以独立气泡追加在本轮输出末尾。
      store.addMessage(
        convId,
        Message(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}_summary',
          sender: Sender.tool,
          text: lines.join('\n'),
          toolName: 'round_summary',
          toolArgs: '',
          toolOk: true,
        ),
      );
      roundChanges.add(
        RoundChangeRecord(
          time: DateTime.now(),
          conversationId: convId,
          lines: lines,
        ),
      );
    } catch (e) {
      // 快照或统计失败时保持主流程不受影响，控制台留一条诊断信息。
      debugPrint('round changes summary failed: $e');
    }
  }

  bool _hasChangeModelMarker(String text) {
    return RegExp(
      r'change_model\s*\(\s*work\s*\)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  /// 当前对话生效的模型（G02）：对话指定优先，否则用全局设置。
  String _effectiveModel(String? convModel, SettingsStore s) {
    final m = convModel;
    if (m != null && m.isNotEmpty) {
      if (s.provider.models.any((x) => x.id == m)) return m;
    }
    return s.model;
  }

  /// 请求温度（G10）：模型单独配置优先，否则用场景预设温度。
  double _requestTemperature(String model, SettingsStore s) {
    return s.temperatureFor(model) ?? s.presetTemperature;
  }

  /// 模型自动路由：Fast 档优先使用轻量模型（mini/flash/haiku 等）。
  String _modelFor(ThinkingLevel level, String baseModel, SettingsStore s) {
    if (level == ThinkingLevel.fast) {
      for (final m in s.provider.models) {
        if (_isCheapModel(m.id)) return m.id;
      }
    }
    return baseModel;
  }

  bool _isCheapModel(String id) {
    final lower = id.toLowerCase();
    return lower.contains('mini') ||
        lower.contains('flash') ||
        lower.contains('haiku') ||
        lower.contains('highspeed') ||
        lower.contains('lite');
  }

  /// PLAN 模式下，若模型输出以 `change_model(work)` 开头，自动切到 WORK。
  /// 必须在去除协议标记之前用原始流文本判断（标记存库前会被剥离）。
  void _maybeAutoSwitchToWork(String raw, String msgId) {
    if (widget.mode != WorkMode.plan) return;
    if (_autoSwitchedFor.contains(msgId)) return;
    if (!_hasChangeModelMarker(raw)) return;
    _autoSwitchedFor.add(msgId);
    widget.onModeChanged?.call(WorkMode.work);
  }

  void _stop() {
    if (!_sending) return;
    final cancel = _activeCancel;
    if (cancel != null && !cancel.isCompleted) cancel.complete();
    for (final sub in List<StreamSubscription<String>>.of(_activeSubs)) {
      sub.cancel();
    }
    setState(() => _sending = false);
  }

  Future<void> _collectStream(
    Completer<void> cancel,
    Stream<String> stream,
    void Function(String chunk) onChunk,
  ) async {
    final done = Completer<void>();
    late final StreamSubscription<String> sub;
    Timer? watchdog;

    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 300), () {
        sub.cancel();
        if (!done.isCompleted) {
          done.completeError(
            TimeoutException(
              'Stream idle timeout',
              const Duration(seconds: 300),
            ),
          );
        }
      });
    }

    sub = stream.listen(
      (chunk) {
        onChunk(chunk);
        armWatchdog();
      },
      onDone: () {
        watchdog?.cancel();
        if (!done.isCompleted) done.complete();
      },
      onError: (Object e, StackTrace st) {
        watchdog?.cancel();
        if (!done.isCompleted) done.completeError(e, st);
      },
    );
    _activeSubs.add(sub);
    armWatchdog();
    cancel.future.then((_) {
      watchdog?.cancel();
      sub.cancel();
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future;
    } finally {
      watchdog?.cancel();
      _activeSubs.remove(sub);
    }
  }

  /// 包装流：取消时提前结束，供 AgentRunner 内部消费的流使用。
  Stream<String> _cancellable(
    Stream<String> source,
    Completer<void> cancel,
  ) {
    if (cancel.isCompleted) return Stream<String>.empty();
    final controller = StreamController<String>();
    late final StreamSubscription<String> sub;
    Timer? watchdog;

    void armWatchdog() {
      watchdog?.cancel();
      watchdog = Timer(const Duration(seconds: 300), () {
        sub.cancel();
        if (!controller.isClosed) {
          controller.addError(
            TimeoutException(
              'Stream idle timeout',
              const Duration(seconds: 300),
            ),
          );
          controller.close();
        }
      });
    }

    sub = source.listen(
      (chunk) {
        controller.add(chunk);
        armWatchdog();
      },
      onDone: () {
        watchdog?.cancel();
        _activeSubs.remove(sub);
        controller.close();
      },
      onError: (Object e, StackTrace st) {
        watchdog?.cancel();
        _activeSubs.remove(sub);
        controller.addError(e, st);
        if (!controller.isClosed) controller.close();
      },
    );
    _activeSubs.add(sub);
    armWatchdog();
    cancel.future.then((_) {
      watchdog?.cancel();
      sub.cancel();
      _activeSubs.remove(sub);
      if (!controller.isClosed) controller.close();
    });
    controller.onCancel = () {
      watchdog?.cancel();
      sub.cancel();
      _activeSubs.remove(sub);
    };
    return controller.stream;
  }

  /// 请求自动重试：网络类瞬时错误最多重试 3 次（1s / 2s 退避）。
  Stream<String> _chatWithRetry(
    Completer<void> cancel,
    Stream<String> Function() request,
  ) async* {
    var attempts = 0;
    while (true) {
      attempts++;
      try {
        yield* _cancellable(request(), cancel);
        return;
      } catch (e) {
        if (attempts >= 3 || cancel.isCompleted) rethrow;
        final msg = e.toString();
        final transient =
            msg.contains('SocketException') ||
            msg.contains('ClientException') ||
            msg.contains('TimeoutException') ||
            msg.contains('Connection reset') ||
            msg.contains('连接');
        if (!transient) rethrow;
        await Future<void>.delayed(Duration(seconds: attempts * 2));
      }
    }
  }

  Future<AgentResult> _executeCall(
    AgentToolCall call, {
    String? cwd,
    ToolRuntime? runtime,
    String? conversationId,
    List<String>? extraAllowedDirs,
  }) async {
    if (call.tool != 'command') {
      return (runtime ?? ToolRuntime(settings: AppState.settingsOf(context)))
          .execute(
            call,
            cwd: cwd,
            conversationId: conversationId,
            extraAllowedDirs: extraAllowedDirs,
            onFileConfirm: (c, preview) => _confirmFileChange(c, preview),
          );
    }
    if (!mounted) {
      // 组件已卸载时无法弹确认框，按“拒绝执行”处理，而不是静默放行。
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.error.command_cancelled', {'command': call.args}),
      );
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('dialog.command.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                I18n.t('dialog.command.body'),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  call.args,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('dialog.command.deny'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _accent),
            child: Text(I18n.t('dialog.command.allow')),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return AgentResult(
        call: call,
        output: '',
        error: I18n.t('agent.error.command_cancelled', {'command': call.args}),
      );
    }
    return (runtime ?? ToolRuntime(settings: AppState.settingsOf(context)))
        .execute(
          call,
          cwd: cwd,
          conversationId: conversationId,
          commandConfirmed: true,
          extraAllowedDirs: extraAllowedDirs,
        );
  }

  /// A06：文件改动前展示 diff 预览，用户确认后才真正写盘。
  Future<bool> _confirmFileChange(
    AgentToolCall call,
    String preview,
  ) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('file_confirm.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${call.tool}(${call.args})',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SelectableText(
                    preview,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('dialog.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(I18n.t('file_confirm.apply')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 批量命令统一确认：一次弹窗列出所有命令，避免逐个弹窗卡住流程。
  Future<bool> _confirmBatchCommands(List<AgentToolCall> commands) async {
    if (!mounted) return false;
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('dialog.command.batch.title', {
            'count': '${commands.length}',
          }),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  I18n.t('dialog.command.batch.body'),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                for (final c in commands)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        c.args,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('dialog.command.deny'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text(I18n.t('dialog.command.batch.allow')),
          ),
        ],
      ),
    );
    return allow == true;
  }

  /// 批量桌面操作统一确认：一次弹窗列出所有动作，避免逐个弹窗。
  Future<bool> _confirmDesktopActions(List<AgentToolCall> actions) async {
    if (!mounted) return false;
    final allow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('dialog.desktop.batch.title', {
            'count': '${actions.length}',
          }),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  I18n.t('dialog.desktop.batch.body'),
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                for (final c in actions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        '${c.tool}("${_clipArg(c.args)}")',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('dialog.command.deny'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text(I18n.t('dialog.desktop.batch.allow')),
          ),
        ],
      ),
    );
    return allow == true;
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
      case '/remember':
      case '/forget':
      case '/memory':
        _runMemoryCommand(store, convId, normalized, text);
        return true;
      case '/tasks':
        showTaskCenterDialog(context, store);
        return true;
      case '/rollback':
        _runRollback(store, convId, text);
        return true;
      default:
        return false;
    }
  }

  /// A07：一键回滚本轮被 AI 改动的文件。
  void _runRollback(ChatStore store, String convId, String raw) {
    unawaited(() async {
      if (!RollbackService.instance.hasSnapshot(convId)) {
        _sendTo(
          store,
          convId,
          text: raw,
          assistantText: I18n.t('rollback.no_snapshot'),
        );
        return;
      }
      final count = await RollbackService.instance.rollback(convId);
      _sendTo(
        store,
        convId,
        text: raw,
        assistantText: I18n.t('rollback.done', {'count': '$count'}),
      );
    }());
  }

  void _runMemoryCommand(
    ChatStore store,
    String convId,
    String normalized,
    String raw,
  ) {
    if (normalized == '/memory') {
      unawaited(() async {
        final entries = await MemoryService.instance.list();
        final body = entries.isEmpty
            ? I18n.t('memory.empty')
            : entries.reversed
                  .map((e) => '${e.id}: ${e.text}')
                  .join('\n');
        _sendTo(
          store,
          convId,
          text: raw,
          assistantText: '## ${I18n.t('memory.title')}\n$body',
        );
      }());
      return;
    }
    if (normalized == '/remember' || normalized.startsWith('/remember ')) {
      final content = raw.length > '/remember'.length
          ? raw.substring('/remember'.length).trim()
          : '';
      unawaited(() async {
        if (content.isEmpty) {
          _sendTo(
            store,
            convId,
            text: raw,
            assistantText: I18n.t('memory.remember_empty'),
          );
          return;
        }
        await MemoryService.instance.add(content, kind: 'preference');
        _sendTo(
          store,
          convId,
          text: raw,
          assistantText: I18n.t('memory.remembered', {'text': content}),
        );
      }());
      return;
    }
    if (normalized == '/forget' || normalized.startsWith('/forget ')) {
      final id = raw.length > '/forget'.length
          ? raw.substring('/forget'.length).trim()
          : '';
      unawaited(() async {
        if (id.isEmpty) {
          _sendTo(
            store,
            convId,
            text: raw,
            assistantText: I18n.t('memory.forget_empty'),
          );
          return;
        }
        await MemoryService.instance.remove(id);
        _sendTo(
          store,
          convId,
          text: raw,
          assistantText: I18n.t('memory.forgotten', {'id': id}),
        );
      }());
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
      '- `/remember <内容>` - ${I18n.t('memory.title')}',
      '- `/forget <id>` - ${I18n.t('memory.forget_empty')}',
      '- `/memory` - ${I18n.t('memory.empty')}',
      '- `/rollback` - ${I18n.t('rollback.no_snapshot')}',
    ].join('\n');
  }

  String _stripToolBlocks(String text) {
    var s = text.replaceAll(
      RegExp(r'\[正式输出\][\s\S]*?\[输出结束\]', multiLine: true),
      '',
    );
    s = s.replaceAll('[最后输出]', '').replaceAll('[输出结束]', '');
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
    final focused = _focus.hasFocus;
    // B04：支持把系统文件拖到输入区直接附加发送。
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        _handleDroppedFiles(details.files);
      },
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: focused
              ? _accent.withValues(alpha: 0.55)
              : (_dragging
                    ? _accent.withValues(alpha: 0.9)
                    : AppColors.border),
        ),
        boxShadow: focused || _dragging
            ? [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: AppColors.cardShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 9, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_replyTo != null) ...[
            _ReplyBar(
              target: _replyTo!,
              accent: _accent,
              onCancel: () {
                setState(() => _replyTo = null);
                widget.replyDraft?.value = null;
              },
            ),
            const SizedBox(height: 8),
          ],
          // C11：Markdown 快捷插入 + 字数统计。
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _mdButton('**', '**', 'B'),
              _mdButton('*', '*', 'I'),
              _mdButton('`', '`', '</>'),
              _mdButton('> ', '', '>'),
              _mdButton('- ', '', '•'),
              const SizedBox(width: 6),
              Text(
                '${_controller.text.characters.length}',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
              if (_lastHistoryTokens > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Tooltip(
                    message: I18n.t('chat.context_usage'),
                    child: Text(
                      '≈ ${_fmtTokens(_lastHistoryTokens)}',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
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
    if (_sending) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFE5484D),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _stop,
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 20),
          ),
        ),
      );
    }
    final enabled = _hasText;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _accent,
              Color.lerp(_accent, Colors.black, 0.25)!,
            ],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? _send : null,
            child: const Icon(Icons.arrow_upward, color: Colors.white, size: 19),
          ),
        ),
      ),
    );
  }
}

class _ReplyBar extends StatelessWidget {
  const _ReplyBar({
    required this.target,
    required this.accent,
    required this.onCancel,
  });

  final ReplyTarget target;
  final Color accent;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply, size: 13, color: accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${target.label}：${target.preview.replaceAll('\n', ' ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: I18n.t('chat.reply_cancel'),
            onPressed: onCancel,
            icon: Icon(
              Icons.close,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
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
