import 'dart:async';
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
import '../services/round_changes.dart';
import '../services/settings_store.dart';
import '../state/chat_store.dart';
import '../state/round_changes_store.dart';
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
    this.onModeChanged,
  });

  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color? accent;
  final Color? accentSoft;
  final String? conversationId;
  final ValueChanged<WorkMode>? onModeChanged;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _hasText = false;
  bool _sending = false;
  final Map<String, DateTime> _lastStreamUiUpdates = {};
  final Set<StreamSubscription<String>> _activeSubs = {};
  final Set<String> _autoSwitchedFor = <String>{};
  Completer<void>? _activeCancel;

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

    if (!mounted) return;
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
    final roundChanges = AppState.roundChangesOf(context);
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
        beforeSnapshot = await WorkspaceSnapshot.capture();
      } catch (_) {
        beforeSnapshot = null;
      }
    }

    setState(() => _sending = true);
    final cancel = Completer<void>();
    _activeCancel = cancel;

    final history = <Map<String, dynamic>>[];
    for (final m
        in store.conversations.firstWhere((c) => c.id == convId).messages) {
      if (m.id == placeholderId) continue;
      if (m.sender == Sender.system) continue;
      if (m.sender == Sender.tool) continue;
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
        FlagshipAgentPlan plan;
        try {
          plan = await AgentRunner.planFlagshipSession(
            chat: (system, messages) => _cancellable(
              client.chatStream(
                ChatRequest(
                  system: system,
                  messages: messages,
                  model: settings.model,
                  maxTokens: coordinatorMaxTokens,
                ),
              ),
              cancel,
            ),
            history: currentHistory,
            isEnglish: isEnglish,
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
              .map(AgentRunner.agentFromPlanItem)
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
            final subRaw = StringBuffer();
            var lastSubVisible = '';
            try {
              await _collectStream(
                cancel,
                client.chatStream(
                  ChatRequest(
                    system: subSystem,
                    messages: currentHistory,
                    model: settings.model,
                    maxTokens: subAgentMaxTokens,
                  ),
                ),
                (chunk) {
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
                },
              );
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
              return result;
            }
          }

          final roundResults = await Future.wait(plannedAgents.map(runAgent));
          allResults.addAll(roundResults);
          if (cancel.isCompleted) break;

          try {
            plan = await AgentRunner.planFlagshipRound(
              chat: (system, messages) => _cancellable(
                client.chatStream(
                  ChatRequest(
                    system: system,
                    messages: messages,
                    model: settings.model,
                    maxTokens: coordinatorMaxTokens,
                  ),
                ),
                cancel,
              ),
              history: currentHistory,
              previousResults: roundResults,
              round: round,
              isEnglish: isEnglish,
            );
          } on TimeoutException {
            // 主协调综合超时：视为本轮信息已足够，直接进入最终综合。
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

      while (turn < maxTurns) {
        if (cancel.isCompleted) break;
        final req = ChatRequest(
          system: systemPrompt,
          messages: currentHistory,
          model: settings.model,
          maxTokens: finalMaxTokens,
        );
        final rawAcc = StringBuffer();
        var lastVisible = '';
        await _collectStream(
          cancel,
          client.chatStream(req),
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

        final calls = AgentRunner.parse(rawAcc.toString());
        final thinking = widget.thinking;
        if (calls.isEmpty &&
            thinking != ThinkingLevel.fast &&
            AgentRunner.hasToolBlock(rawAcc.toString())) {
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
          store.finishToolMessage(
            convId,
            errMsgId,
            I18n.t('agent.error.tool_block_parse_failed'),
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
        if (calls.isEmpty || thinking == ThinkingLevel.fast) break;

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
          final r = await _executeCall(call);
          results.add(r);
          if (r.ok &&
              (call.tool == 'writefile' || call.tool == 'replacefile')) {
            final parts = call.args.split('|||');
            if (parts.isNotEmpty) {
              final key = WorkspaceSnapshot.normalizePath(parts.first.trim());
              fileActions
                  .putIfAbsent(key, () => <String>{})
                  .add(call.tool == 'writefile' ? 'created' : 'modified');
            }
          }
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
        if (turn < maxTurns) {
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

      if (!cancel.isCompleted && settings.showRoundChanges) {
        await _appendRoundSummary(
          store,
          convId,
          beforeSnapshot,
          fileActions,
          roundChanges,
        );
      }
    } catch (e) {
      store.updateMessage(convId, placeholderId, '${I18n.t('chat.error')} $e');
    } finally {
      if (mounted) setState(() => _sending = false);
      if (identical(_activeCancel, cancel)) _activeCancel = null;
      if (cancel.isCompleted) {
        String current = '';
        for (final c in store.conversations) {
          if (c.id == convId) {
            for (final m in c.messages) {
              if (m.id == placeholderId) {
                current = m.text;
                break;
              }
            }
            break;
          }
        }
        final marker = I18n.t('chat.cancelled');
        store.updateMessage(
          convId,
          placeholderId,
          current.isEmpty ? marker : '$current\n\n$marker',
        );
      }
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

  /// 输出结束后，把本轮实际发生的文件变化追加到本轮最后一条消息末尾。
  Future<void> _appendRoundSummary(
    ChatStore store,
    String convId,
    WorkspaceSnapshot? before,
    Map<String, Set<String>> fileActions,
    RoundChangesStore roundChanges,
  ) async {
    try {
      final lines = <String>[];
      if (before != null) {
        final after = await WorkspaceSnapshot.capture();
        final changes = before.diff(after);
        for (final change in changes) {
          change.actions.addAll(
            fileActions[WorkspaceSnapshot.normalizePath(change.path)] ??
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
      watchdog = Timer(const Duration(seconds: 120), () {
        sub.cancel();
        if (!done.isCompleted) {
          done.completeError(
            TimeoutException(
              'Stream idle timeout',
              const Duration(seconds: 120),
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
      watchdog = Timer(const Duration(seconds: 120), () {
        sub.cancel();
        if (!controller.isClosed) {
          controller.addError(
            TimeoutException(
              'Stream idle timeout',
              const Duration(seconds: 120),
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
      _activeSubs.remove(sub);
    };
    return controller.stream;
  }

  Future<AgentResult> _executeCall(AgentToolCall call) async {
    if (call.tool != 'command') return AgentRunner.execute(call);
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
    return AgentRunner.execute(call);
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
        decoration: BoxDecoration(shape: BoxShape.circle, color: _accent),
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
