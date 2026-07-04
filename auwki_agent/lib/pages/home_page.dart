import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../state/chat_store.dart';
import '../theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/chat_input.dart';
import '../widgets/sidebar.dart';
import '../widgets/thinking_slider.dart';
import '../work_mode.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  WorkMode _mode = WorkMode.work;
  ThinkingLevel _thinking = ThinkingLevel.thinking;
  _ActiveIdListenable? _activeListenable;

  String? _greeting;
  String? _greetingForConvId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = AppState.chatOf(context);
    if (_activeListenable == null) {
      _activeListenable = _ActiveIdListenable(store);
    } else {
      _activeListenable!.attach(store);
    }
  }

  @override
  void dispose() {
    _activeListenable?.dispose();
    super.dispose();
  }

  Color get _accent =>
      _mode == WorkMode.plan ? AppColors.planAccent : AppColors.primary;
  Color get _accentSoft =>
      _mode == WorkMode.plan ? AppColors.planAccentSoft : AppColors.primarySoft;

  String _resolveGreeting(String? convId) {
    if (convId == null) {
      if (_greeting == null) {
        _greeting = _randomGreeting();
        _greetingForConvId = null;
      }
      return _greeting!;
    }
    if (_greetingForConvId != convId) {
      _greeting = _randomGreeting();
      _greetingForConvId = convId;
    }
    return _greeting!;
  }

  String _randomGreeting() {
    final list = [
      I18n.t('home.greeting.1'),
      I18n.t('home.greeting.2'),
      I18n.t('home.greeting.3'),
    ];
    return list[Random().nextInt(list.length)];
  }

  @override
  Widget build(BuildContext context) {
    final store = AppState.chatOf(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sidebar(accent: _accent),
          Expanded(
            child: ValueListenableBuilder<String?>(
              valueListenable: _activeListenable!,
              builder: (context, activeId, _) {
                final greeting = _resolveGreeting(activeId);
                if (activeId == null) {
                  return _EmptyHome(
                    accent: _accent,
                    accentSoft: _accentSoft,
                    mode: _mode,
                    thinking: _thinking,
                    onModeChanged: (m) => setState(() => _mode = m),
                    onThinkingChanged: (t) =>
                        setState(() => _thinking = t),
                    greeting: greeting,
                  );
                }
                final conv = store.conversations.firstWhere(
                  (c) => c.id == activeId,
                  orElse: () => store.conversations.first,
                );
                return ChatView(
                  conversation: conv,
                  mode: _mode,
                  thinking: _thinking,
                  accent: _accent,
                  accentSoft: _accentSoft,
                  onModeChanged: (m) => setState(() => _mode = m),
                  onThinkingChanged: (t) => setState(() => _thinking = t),
                  greeting: greeting,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({
    required this.accent,
    required this.accentSoft,
    required this.mode,
    required this.thinking,
    required this.onModeChanged,
    required this.onThinkingChanged,
    required this.greeting,
  });

  final Color accent;
  final Color accentSoft;
  final WorkMode mode;
  final ThinkingLevel thinking;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              _HeroTitle(text: greeting, accent: accent),
              const SizedBox(height: 24),
              ControlsCard(
                mode: mode,
                thinking: thinking,
                accent: accent,
                accentSoft: accentSoft,
                onModeChanged: onModeChanged,
                onThinkingChanged: onThinkingChanged,
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.conversation,
    required this.mode,
    required this.thinking,
    required this.accent,
    required this.accentSoft,
    required this.onModeChanged,
    required this.onThinkingChanged,
    required this.greeting,
  });

  final Conversation conversation;
  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color accent;
  final Color accentSoft;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final String greeting;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ChatView old) {
    super.didUpdateWidget(old);
    if (widget.conversation.messages.length !=
        old.conversation.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(
          children: [
            if (conv.messages.isEmpty)
              Expanded(
                child: Center(
                  child: _HeroTitle(text: widget.greeting, accent: widget.accent),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 16),
                  itemCount: conv.messages.length,
                  itemBuilder: (context, i) {
                    return _MessageBubble(
                      message: conv.messages[i],
                      accent: widget.accent,
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: ControlsCard(
                mode: widget.mode,
                thinking: widget.thinking,
                accent: widget.accent,
                accentSoft: widget.accentSoft,
                onModeChanged: widget.onModeChanged,
                onThinkingChanged: widget.onThinkingChanged,
                conversationId: conv.id,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.accent});

  final Message message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (message.sender == Sender.tool) {
      return _ToolBubble(message: message, accent: accent);
    }
    final isUser = message.sender == Sender.user;
    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final bg = isUser ? accent.withValues(alpha: 0.18) : AppColors.surface;
    final fg = AppColors.textPrimary;
    final label = isUser ? I18n.t('chat.you') : I18n.t('chat.assistant');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isUser ? accent : AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final a in message.attachments)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '📎 ${a.name}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: fg, fontSize: 14, height: 1.5),
                        h1: TextStyle(
                            color: fg,
                            fontSize: 22,
                            fontWeight: FontWeight.w700),
                        h2: TextStyle(
                            color: fg,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                        h3: TextStyle(
                            color: fg,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                        strong: TextStyle(
                            color: fg, fontWeight: FontWeight.w700),
                        em: TextStyle(
                            color: fg, fontStyle: FontStyle.italic),
                        code: TextStyle(
                          color: fg,
                          backgroundColor: AppColors.surfaceAlt,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        codeblockPadding: const EdgeInsets.all(10),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: accent, width: 3),
                          ),
                        ),
                        blockquotePadding: const EdgeInsets.only(left: 10),
                        listBullet: TextStyle(color: fg, fontSize: 14),
                        tableHead: TextStyle(
                            color: fg, fontWeight: FontWeight.w700),
                        tableBorder: TableBorder.all(
                          color: AppColors.border,
                          width: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolBubble extends StatefulWidget {
  const _ToolBubble({required this.message, required this.accent});
  final Message message;
  final Color accent;

  @override
  State<_ToolBubble> createState() => _ToolBubbleState();
}

class _ToolBubbleState extends State<_ToolBubble> {
  bool _expanded = false;

  String _toolLabel(String? name) {
    switch (name) {
      case 'webfetch':
        return '网页抓取';
      case 'websearch':
        return '网页搜索';
      case 'command':
        return '执行命令';
      default:
        return name ?? '工具';
    }
  }

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final running = m.toolRunning;
    final ok = m.toolOk;
    final hasResult = m.toolResult != null;
    String status;
    Color statusColor;
    if (running) {
      status = '执行中…';
      statusColor = AppColors.textSecondary;
    } else if (ok == true) {
      status = '成功';
      statusColor = const Color(0xFF66BB6A);
    } else if (ok == false) {
      status = '失败';
      statusColor = Colors.redAccent;
    } else {
      status = '';
      statusColor = AppColors.textSecondary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.7,
          ),
          child: Material(
            color: AppColors.surfaceAlt,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: running
                    ? widget.accent.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: hasResult ? () => setState(() => _expanded = !_expanded) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🔧', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        Text(
                          '工具使用',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _toolLabel(m.toolName),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (status.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                        if (running) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation(
                                  widget.accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (m.toolArgs != null && m.toolArgs!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _truncate(m.toolArgs!, 140),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: _expanded ? null : 1,
                        overflow: _expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                    ],
                    if (_expanded && hasResult) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          m.toolResult!,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveIdListenable extends ValueNotifier<String?> {
  _ActiveIdListenable(ChatStore store) : super(store.activeId) {
    _store = store;
    _store?.addListener(_sync);
  }

  ChatStore? _store;

  void attach(ChatStore store) {
    if (identical(_store, store)) return;
    final old = _store;
    _store = store;
    if (old != null) old.removeListener(_sync);
    store.addListener(_sync);
    value = store.activeId;
  }

  void _sync() {
    final s = _store;
    if (s == null) return;
    value = s.activeId;
  }

  @override
  void dispose() {
    _store?.removeListener(_sync);
    _store = null;
    super.dispose();
  }
}

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BrandLogo(size: 44, showText: false, color: accent),
        const SizedBox(width: 16),
        Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class ControlsCard extends StatelessWidget {
  const ControlsCard({
    super.key,
    required this.mode,
    required this.thinking,
    required this.accent,
    required this.accentSoft,
    required this.onModeChanged,
    required this.onThinkingChanged,
    this.conversationId,
  });

  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color accent;
  final Color accentSoft;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    final thinkingOn = thinking != ThinkingLevel.fast;

    return Container(
      width: 820,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ModeTabs(mode: mode, onChanged: onModeChanged, accent: accent),
              const SizedBox(width: 16),
              Container(width: 1, height: 22, color: AppColors.border),
              const SizedBox(width: 16),
              Text(
                I18n.t('thinking.label'),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: thinkingOn ? accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: thinkingOn
                        ? accent.withValues(alpha: 0.4)
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bolt,
                      size: 13,
                      color: thinkingOn ? accent : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      thinkingOn
                          ? I18n.t('thinking.on')
                          : I18n.t('thinking.off'),
                      style: TextStyle(
                        color: thinkingOn ? accent : AppColors.textTertiary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ThinkingSlider(
            value: thinking,
            accent: accent,
            onChanged: onThinkingChanged,
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          ChatInput(
            mode: mode,
            thinking: thinking,
            accent: accent,
            accentSoft: accentSoft,
            conversationId: conversationId,
          ),
        ],
      ),
    );
  }
}

class _ModeTabs extends StatelessWidget {
  const _ModeTabs({
    required this.mode,
    required this.onChanged,
    required this.accent,
  });

  final WorkMode mode;
  final ValueChanged<WorkMode> onChanged;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab(WorkMode.work, I18n.t('mode.work')),
          _tab(WorkMode.plan, I18n.t('mode.plan')),
        ],
      ),
    );
  }

  Widget _tab(WorkMode m, String label) {
    final selected = mode == m;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(m),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}