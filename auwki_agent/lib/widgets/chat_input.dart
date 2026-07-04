import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/agent.dart';
import '../services/ai_providers.dart';
import '../services/prompts.dart';
import '../state/chat_store.dart';
import '../theme.dart';
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
  bool _deepThink = true;
  bool _smartSearch = false;
  bool _sending = false;

  Color get _accent => widget.accent ?? AppColors.primary;
  Color get _accentSoft => widget.accentSoft ?? AppColors.primarySoft;

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
      messenger.showSnackBar(SnackBar(
        content: Text(I18n.t('attach.error.read', {'name': pf.name})),
      ));
      return;
    }

    final file = File(path);
    if (!await file.exists()) return;

    final size = await file.length();
    if (size > 5 * 1024 * 1024) {
      messenger.showSnackBar(SnackBar(
        content: Text(I18n.t('attach.too_large', {'name': pf.name})),
      ));
      return;
    }

    final bytes = await file.readAsBytes();
    final isBinary = _looksBinary(bytes);
    if (isBinary) {
      messenger.showSnackBar(SnackBar(
        content: Text(I18n.t('attach.error.binary', {'name': pf.name})),
      ));
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

    if (settings.apiKey.isEmpty) {
      _sendTo(store, convId,
          text: text, assistantText: I18n.t('chat.no_key'));
      return;
    }

    _controller.clear();

    final userMsg = Message(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}',
      sender: Sender.user,
      text: text,
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
    for (final m in store.conversations.firstWhere((c) => c.id == convId).messages) {
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
      );

      var turn = 0;
      final maxTurns = 3;
      var currentHistory = List<Map<String, dynamic>>.from(history);

      while (turn < maxTurns) {
        final req = ChatRequest(
          system: systemPrompt,
          messages: currentHistory,
          model: settings.model,
          maxTokens: 2048,
        );
        final rawAcc = StringBuffer();
        final visibleAcc = StringBuffer();
        await for (final chunk in client.chatStream(req)) {
          rawAcc.write(chunk);
          visibleAcc
            ..clear()
            ..write(_stripToolBlocks(rawAcc.toString()));
          store.updateMessage(convId, placeholderId, visibleAcc.toString());
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

        currentHistory.add({
          'role': 'assistant',
          'content': rawAcc.toString(),
        });
        final toolMsg = results
            .map((r) =>
                '[${r.call.tool}(${r.call.args})]\n${r.error ?? r.output}')
            .join('\n\n');
        currentHistory.add({
          'role': 'user',
          'content':
              '[执行结果]\n$toolMsg\n\n请基于以上结果继续回答，可继续使用 [正式输出] 块调用工具，或直接给出最终回答。',
        });
        turn++;
      }
    } catch (e) {
      store.updateMessage(convId, placeholderId,
          '${I18n.t('chat.error')} $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _stripToolBlocks(String text) {
    return text.replaceAll(
      RegExp(r'\[正式输出\][\s\S]*?\[输出结束\]', multiLine: true),
      '',
    );
  }

  void _sendTo(ChatStore store, String convId,
      {String text = '',
      String assistantText = '',
      List<Attachment> attachments = const []}) {
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
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focus,
            maxLines: 6,
            minLines: 2,
            enabled: !_sending,
            cursorColor: _accent,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: I18n.t('chat.placeholder'),
              hintStyle:
                  TextStyle(color: AppColors.textTertiary, fontSize: 15),
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _toolChip(
                icon: Icons.bolt,
                label: I18n.t('chat.tool.deep'),
                active: _deepThink,
                onTap: () => setState(() => _deepThink = !_deepThink),
              ),
              const SizedBox(width: 8),
              _toolChip(
                icon: Icons.travel_explore,
                label: I18n.t('chat.tool.search'),
                active: _smartSearch,
                onTap: () => setState(() => _smartSearch = !_smartSearch),
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
    );
  }

  Widget _toolChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? _accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? _accent.withValues(alpha: 0.4) : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: active ? _accent : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? _accent : AppColors.textSecondary,
                fontSize: 13,
              ),
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
      width: 34,
      height: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
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
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _accent,
        ),
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
                      valueColor: AlwaysStoppedAnimation(Colors.white.withValues(alpha: 0.9)),
                    ),
                  )
                : Icon(Icons.arrow_upward,
                    color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}