import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/settings_store.dart';
import '../services/workspace_manager.dart';
import '../state/chat_store.dart';
import '../theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/chat_input.dart';
import '../widgets/inspector/browser_panel.dart';
import '../widgets/inspector/git_panel.dart';
import '../widgets/inspector/round_changes_panel.dart';
import '../widgets/sidebar.dart';
import '../widgets/thinking_slider.dart';
import '../widgets/dialogs/settings_dialog.dart';
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
  ChatStore? _store;
  String? _workspaceDir;
  bool _inspectorOpen = false;

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
    if (_store != store) {
      _store?.removeListener(_onStoreChange);
      _store = store;
      _store?.addListener(_onStoreChange);
    }
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _activeListenable?.dispose();
    _store?.removeListener(_onStoreChange);
    super.dispose();
  }

  Color get _accent => _thinking == ThinkingLevel.flagship
      ? AppColors.primary
      : _mode == WorkMode.plan
      ? AppColors.planAccent
      : AppColors.primary;
  Color get _accentSoft => _thinking == ThinkingLevel.flagship
      ? AppColors.primarySoft
      : _mode == WorkMode.plan
      ? AppColors.planAccentSoft
      : AppColors.primarySoft;

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
    final settings = AppState.settingsOf(context);
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    final isFlagship = _thinking == ThinkingLevel.flagship;
    AppColors.palette = isFlagship
        ? (settings.theme == AppTheme.dark
              ? AppPalette.darkFlagship
              : AppPalette.lightFlagship)
        : (settings.theme == AppTheme.dark
              ? AppPalette.dark
              : AppPalette.light);

    final chatArea = Expanded(
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
              workspaceDir: _workspaceDir,
              onModeChanged: (m) => setState(() => _mode = m),
              onThinkingChanged: (t) => setState(() => _thinking = t),
              onWorkspaceChanged: (v) => setState(() => _workspaceDir = v),
              greeting: greeting,
            );
          }
          Conversation? conv;
          for (final c in store.conversations) {
            if (c.id == activeId) {
              conv = c;
              break;
            }
          }
          if (conv == null) {
            return _EmptyHome(
              accent: _accent,
              accentSoft: _accentSoft,
              mode: _mode,
              thinking: _thinking,
              workspaceDir: _workspaceDir,
              onModeChanged: (m) => setState(() => _mode = m),
              onThinkingChanged: (t) => setState(() => _thinking = t),
              onWorkspaceChanged: (v) => setState(() => _workspaceDir = v),
              greeting: greeting,
            );
          }
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
    );

    final inspector = ValueListenableBuilder<String?>(
      valueListenable: _activeListenable!,
      builder: (context, activeId, _) {
        Conversation? conv;
        if (activeId != null) {
          for (final c in store.conversations) {
            if (c.id == activeId) {
              conv = c;
              break;
            }
          }
        }
        return _InspectorPanel(
          conversation: conv,
          mode: _mode,
          thinking: _thinking,
          accent: _accent,
          onClose: wide
              ? null
              : () => setState(() => _inspectorOpen = false),
        );
      },
    );

    final Widget content;
    if (wide) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sidebar(accent: _accent),
          chatArea,
          inspector,
        ],
      );
    } else {
      content = Stack(
        children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Sidebar(
                  accent: _accent,
                  showInspectorButton: true,
                  onToggleInspector: () =>
                      setState(() => _inspectorOpen = !_inspectorOpen),
                ),
                chatArea,
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: _inspectorOpen
                  ? Material(
                      key: const ValueKey('inspector-open'),
                      elevation: 12,
                      color: AppColors.surface,
                      child: inspector,
                    )
                  : const SizedBox.shrink(
                      key: ValueKey('inspector-closed'),
                    ),
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _FlagshipShell(enabled: isFlagship, child: content),
    );
  }
}

class _FlagshipShell extends StatefulWidget {
  const _FlagshipShell({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_FlagshipShell> createState() => _FlagshipShellState();
}

class _FlagshipShellState extends State<_FlagshipShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _FlagshipShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = widget.enabled ? 0.10 + _controller.value * 0.08 : 0.0;
        return Stack(
          children: [
            Positioned.fill(child: child!),
            if (widget.enabled)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.85, -0.85),
                      radius: 0.75,
                      colors: [
                        AppColors.primary.withValues(alpha: glow),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _InspectorPanel extends StatefulWidget {
  const _InspectorPanel({
    required this.conversation,
    required this.mode,
    required this.thinking,
    required this.accent,
    this.onClose,
  });

  final Conversation? conversation;
  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color accent;
  final VoidCallback? onClose;

  @override
  State<_InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<_InspectorPanel> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final conv = widget.conversation;
    final messages = conv?.messages ?? const <Message>[];
    final toolMessages = messages
        .where((m) => m.sender == Sender.tool)
        .toList();
    final runningTools = toolMessages.where((m) => m.toolRunning).toList();
    final agents = toolMessages
        .where((m) => m.toolName?.startsWith('agent.') == true)
        .toList();
    final blocked = toolMessages.where((m) {
      final text = '${m.text}\n${m.toolResult ?? ''}';
      return text.contains('[已拦截]') || text.contains('[Blocked]');
    }).length;

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    size: 17,
                    color: widget.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    I18n.t('inspector.title'),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (widget.onClose != null) ...[
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      tooltip: I18n.t('inspector.close'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              _TabBar(
                selected: _tab,
                accent: widget.accent,
                onSelect: (i) => setState(() => _tab = i),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: switch (_tab) {
                  0 => _OverviewTab(
                    mode: widget.mode,
                    thinking: widget.thinking,
                    messages: messages,
                    workspaceDir: conv?.workspaceDir,
                    toolMessages: toolMessages,
                    runningTools: runningTools,
                    agents: agents,
                    blocked: blocked,
                    accent: widget.accent,
                  ),
                  1 => RoundChangesPanel(accent: widget.accent),
                  2 => BrowserPanel(accent: widget.accent),
                  _ => GitPanel(
                    accent: widget.accent,
                    workspacePath: conv?.workspaceDir,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.selected,
    required this.accent,
    required this.onSelect,
  });

  final int selected;
  final Color accent;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (Icons.dashboard_outlined, I18n.t('inspector.tab.overview')),
      (Icons.difference_outlined, I18n.t('inspector.tab.changes')),
      (Icons.public, I18n.t('inspector.tab.browser')),
      (Icons.alt_route, 'Git'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: () => onSelect(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? accent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tabs[i].$1,
                        size: 15,
                        color: selected == i
                            ? accent
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tabs[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected == i
                              ? accent
                              : AppColors.textSecondary,
                          fontSize: 9.5,
                          fontWeight: selected == i
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.mode,
    required this.thinking,
    required this.messages,
    required this.workspaceDir,
    required this.toolMessages,
    required this.runningTools,
    required this.agents,
    required this.blocked,
    required this.accent,
  });

  final WorkMode mode;
  final ThinkingLevel thinking;
  final List<Message> messages;
  final String? workspaceDir;
  final List<Message> toolMessages;
  final List<Message> runningTools;
  final List<Message> agents;
  final int blocked;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _InspectorCard(
          title: I18n.t('inspector.session'),
          children: [
            _InspectorRow(
              I18n.t('inspector.mode'),
              mode.name.toUpperCase(),
            ),
            _InspectorRow(I18n.t('inspector.thinking'), thinking.label),
            _InspectorRow(
              I18n.t('inspector.messages'),
              '${messages.length}',
            ),
            if (workspaceDir != null && workspaceDir!.trim().isNotEmpty) ...[
              _InspectorRow(I18n.t('inspector.workspace'), workspaceDir!),
            ],
          ],
        ),
        const SizedBox(height: 10),
        _InspectorCard(
          title: I18n.t('inspector.workflow'),
          children: [
            _InspectorRow(
              I18n.t('inspector.running'),
              '${runningTools.length}',
            ),
            _InspectorRow(I18n.t('inspector.agents'), '${agents.length}'),
            _InspectorRow(I18n.t('inspector.blocked'), '$blocked'),
          ],
        ),
        const SizedBox(height: 10),
        _InspectorCard(
          title: I18n.t('inspector.recent_tools'),
          children: [
            if (toolMessages.isEmpty)
              Text(
                I18n.t('inspector.empty'),
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              )
            else
              for (final m in toolMessages.reversed.take(8))
                _ToolTraceLine(message: m, accent: accent),
          ],
        ),
      ],
    );
  }
}

class _InspectorCard extends StatelessWidget {
  const _InspectorCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InspectorRow extends StatelessWidget {
  const _InspectorRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolTraceLine extends StatelessWidget {
  const _ToolTraceLine({required this.message, required this.accent});

  final Message message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final ok = message.toolOk;
    final color = message.toolRunning
        ? accent
        : ok == false
        ? Colors.redAccent
        : const Color(0xFF66BB6A);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message.toolName == 'round_summary'
                  ? I18n.t('tool.round_summary')
                  : message.toolName ?? I18n.t('tool.generic'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
    required this.workspaceDir,
    required this.onModeChanged,
    required this.onThinkingChanged,
    required this.onWorkspaceChanged,
    required this.greeting,
  });

  final Color accent;
  final Color accentSoft;
  final WorkMode mode;
  final ThinkingLevel thinking;
  final String? workspaceDir;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final ValueChanged<String?> onWorkspaceChanged;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _HeroTitle(text: greeting, accent: accent),
                    const SizedBox(height: 20),
                    _OnboardingCard(accent: accent),
                    const SizedBox(height: 12),
                    _WorkspaceCard(
                      workspaceDir: workspaceDir,
                      accent: accent,
                      onChanged: onWorkspaceChanged,
                    ),
                    const SizedBox(height: 12),
                    ControlsCard(
                      mode: mode,
                      thinking: thinking,
                      accent: accent,
                      accentSoft: accentSoft,
                      workspaceDir: workspaceDir,
                      onModeChanged: onModeChanged,
                      onThinkingChanged: onThinkingChanged,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 760,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.waving_hand_outlined, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                I18n.t('home.onboarding.title'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            I18n.t('home.onboarding.body'),
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          _OnboardingStep(text: I18n.t('home.onboarding.step1')),
          _OnboardingStep(text: I18n.t('home.onboarding.step2')),
          _OnboardingStep(text: I18n.t('home.onboarding.step3')),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => showSettingsDialog(context),
              icon: const Icon(Icons.settings_outlined, size: 16),
              label: Text(I18n.t('home.onboarding.settings')),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                textStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  const _OnboardingStep({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: AppColors.textTertiary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({
    required this.workspaceDir,
    required this.accent,
    required this.onChanged,
  });

  final String? workspaceDir;
  final Color accent;
  final ValueChanged<String?> onChanged;

  Future<void> _pick(BuildContext context) async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    onChanged(dir.trim());
  }

  @override
  Widget build(BuildContext context) {
    final custom = workspaceDir != null && workspaceDir!.trim().isNotEmpty;
    return Container(
      width: 760,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: custom
              ? accent.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.folder_outlined, color: accent, size: 17),
              const SizedBox(width: 8),
              Text(
                I18n.t('home.workspace.title'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _pick(context),
                child: Text(
                  I18n.t('home.workspace.pick'),
                  style: TextStyle(color: accent, fontSize: 12),
                ),
              ),
              if (custom) ...[
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => onChanged(null),
                  child: Text(
                    I18n.t('home.workspace.reset'),
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            custom
                ? workspaceDir!
                : I18n.t('home.workspace.none'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: custom ? AppColors.textPrimary : AppColors.textTertiary,
              fontSize: 11.5,
              fontFamily: custom ? 'monospace' : null,
            ),
          ),
          if (!custom) ...[
            const SizedBox(height: 4),
            Text(
              I18n.t('home.workspace.default_hint', {
                'base': WorkspaceManager.appBaseDirectory,
              }),
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ],
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
  final Set<String> _autoSwitchedFor = <String>{};
  int? _lastMessageTextLength;
  bool _hasChangeModelMarker(String text) {
    return RegExp(
      r'change_model\s*\(\s*work\s*\)',
      caseSensitive: false,
    ).hasMatch(text);
  }

  @override
  void didUpdateWidget(covariant ChatView old) {
    super.didUpdateWidget(old);
    final messages = widget.conversation.messages;
    final last = messages.isEmpty ? null : messages.last.text.length;
    final countChanged = messages.length != old.conversation.messages.length;
    final textGrew = !countChanged &&
        last != null &&
        last > (_lastMessageTextLength ?? -1);
    if (countChanged || textGrew) {
      _lastMessageTextLength = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }

    // Protocol from prompts.dart: when in PLAN mode and AI's latest
    // message contains `change_model(work)`, force-switch to WORK.
    if (widget.mode == WorkMode.plan) {
      for (final m in messages) {
        if (m.sender != Sender.assistant) continue;
        if (_autoSwitchedFor.contains(m.id)) continue;
        if (_hasChangeModelMarker(m.text)) {
          _autoSwitchedFor.add(m.id);
          widget.onModeChanged(WorkMode.work);
          break;
        }
      }
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
                  child: _HeroTitle(
                    text: widget.greeting,
                    accent: widget.accent,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  itemCount: conv.messages.length,
                  itemBuilder: (context, i) {
                    final message = conv.messages[i];
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) {
                        return FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.06),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(message.id),
                        child: _MessageBubble(
                          message: message,
                          accent: widget.accent,
                          palette: context.palette,
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: ControlsCard(
                mode: widget.mode,
                thinking: widget.thinking,
                accent: widget.accent,
                accentSoft: widget.accentSoft,
                onModeChanged: widget.onModeChanged,
                onThinkingChanged: widget.onThinkingChanged,
                conversationId: conv.id,
                workspaceDir: conv.workspaceDir,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.accent,
    required this.palette,
  });

  final Message message;
  final Color accent;
  final AppPalette palette;

  void _copyMessage(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.text));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            I18n.t('conv.copy.done'),
            style: const TextStyle(fontSize: 12),
          ),
          backgroundColor: AppColors.surfaceAlt,
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (message.sender == Sender.tool &&
        message.toolName == 'round_summary') {
      return _RoundSummaryBubble(message: message, accent: accent);
    }
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
            maxWidth: MediaQuery.of(context).size.width * 0.64,
          ),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: isUser ? accent : AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => _copyMessage(context),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.copy,
                        size: 11,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
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
                                  horizontal: 8,
                                  vertical: 4,
                                ),
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
                        p: TextStyle(color: fg, fontSize: 13.5, height: 1.45),
                        h1: TextStyle(
                          color: fg,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                        h2: TextStyle(
                          color: fg,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        h3: TextStyle(
                          color: fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        strong: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
                        em: TextStyle(color: fg, fontStyle: FontStyle.italic),
                        code: TextStyle(
                          color: palette.codeFg,
                          // 半透明背景：选中文字时蓝色高亮可以透出来，
                          // 不会被深色代码块背景完全盖住。
                          backgroundColor: palette.codeBg.withValues(
                            alpha: 0.5,
                          ),
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: palette.codeblockBg,
                          border: Border.all(color: AppColors.border, width: 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        codeblockPadding: const EdgeInsets.all(12),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(color: accent, width: 3),
                          ),
                        ),
                        blockquotePadding: const EdgeInsets.only(left: 10),
                        listBullet: TextStyle(color: fg, fontSize: 13.5),
                        tableHead: TextStyle(
                          color: fg,
                          fontWeight: FontWeight.w700,
                        ),
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

/// “本轮更改”独立气泡：显示在本轮输出的末尾。
class _RoundSummaryBubble extends StatelessWidget {
  const _RoundSummaryBubble({required this.message, required this.accent});

  final Message message;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final lines = message.text.split('\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.64,
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.difference_outlined,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      I18n.t('tool.round_summary'),
                      style: TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      line,
                      style: TextStyle(
                        color: _lineColor(line),
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
      ),
    );
  }

  Color _lineColor(String line) {
    final t = line.trim();
    if (t.isEmpty) return AppColors.textSecondary;
    if (RegExp(r'\s-\s*$').hasMatch(t)) return Colors.redAccent;
    if (t == I18n.t('round_summary.none')) return AppColors.textTertiary;
    if (t.contains('+')) return const Color(0xFF66BB6A);
    return AppColors.textPrimary;
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
      case 'agent.prometheus':
        return 'Prometheus';
      case 'agent.metis':
        return 'Metis';
      case 'agent.oracle':
        return 'Oracle';
      case 'agent.artistry':
        return 'Artistry';
      case 'agent.librarian':
        return 'Librarian';
      case 'agent.explorer':
        return 'Explorer';
      case 'webfetch':
        return I18n.t('tool.webfetch');
      case 'websearch':
        return I18n.t('tool.websearch');
      case 'listfiles':
        return I18n.t('tool.listfiles');
      case 'readfile':
        return I18n.t('tool.readfile');
      case 'writefile':
        return I18n.t('tool.writefile');
      case 'replacefile':
        return I18n.t('tool.replacefile');
      case 'command':
        return I18n.t('tool.command');
      case 'round_summary':
        return I18n.t('tool.round_summary');
      default:
        return name ?? I18n.t('tool.generic');
    }
  }

  String _truncate(String s, int n) =>
      s.length <= n ? s : '${s.substring(0, n)}…';

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    final isAgent = m.toolName?.startsWith('agent.') == true;
    final running = m.toolRunning;
    final ok = m.toolOk;
    final hasResult = m.toolResult != null;
    String status;
    Color statusColor;
    if (running) {
      status = isAgent
          ? (m.text.trim().isEmpty
                ? I18n.t('tool.status.agent_creating')
                : I18n.t('tool.status.agent_working'))
          : I18n.t('tool.status.running');
      statusColor = AppColors.textSecondary;
    } else if (ok == true) {
      status = I18n.t('tool.status.success');
      statusColor = const Color(0xFF66BB6A);
    } else if (ok == false) {
      status = I18n.t('tool.status.failed');
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
            maxWidth: MediaQuery.of(context).size.width * 0.64,
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
              onTap: hasResult
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
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
                          isAgent ? I18n.t('tool.agent') : I18n.t('tool.use'),
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
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            transitionBuilder: (child, anim) {
                              return FadeTransition(
                                opacity: anim,
                                child: child,
                              );
                            },
                            child: Container(
                              key: ValueKey(status),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
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
                          ),
                        ],
                        if (running) ...[
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor: AlwaysStoppedAnimation(widget.accent),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_visibleToolContent(m).isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _truncate(_visibleToolContent(m), 140),
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

  /// 子代理气泡显示思维链（text）；普通工具气泡显示参数行。
  String _visibleToolContent(Message m) {
    final isAgent = m.toolName?.startsWith('agent.') == true;
    if (isAgent && m.text.trim().isNotEmpty) return m.text;
    return m.toolArgs ?? '';
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
        BrandLogo(size: 38, showText: false, color: accent),
        const SizedBox(width: 14),
        Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 34,
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
    this.workspaceDir,
    required this.onModeChanged,
    required this.onThinkingChanged,
    this.conversationId,
  });

  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color accent;
  final Color accentSoft;
  final String? workspaceDir;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 760,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ModeTabs(mode: mode, onChanged: onModeChanged, accent: accent),
              const Spacer(),
              _ThinkingMenuButton(
                thinking: thinking,
                accent: accent,
                accentSoft: accentSoft,
                onThinkingChanged: onThinkingChanged,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ChatInput(
            mode: mode,
            thinking: thinking,
            accent: accent,
            accentSoft: accentSoft,
            conversationId: conversationId,
            workspaceDir: workspaceDir,
            onModeChanged: onModeChanged,
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
        borderRadius: BorderRadius.circular(9),
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
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

class _ThinkingMenuButton extends StatelessWidget {
  const _ThinkingMenuButton({
    required this.thinking,
    required this.accent,
    required this.accentSoft,
    required this.onThinkingChanged,
  });

  final ThinkingLevel thinking;
  final Color accent;
  final Color accentSoft;
  final ValueChanged<ThinkingLevel> onThinkingChanged;

  @override
  Widget build(BuildContext context) {
    final active = thinking != ThinkingLevel.fast;
    return PopupMenuButton<ThinkingLevel>(
      tooltip: I18n.t('thinking.label'),
      color: AppColors.surface,
      onSelected: onThinkingChanged,
      itemBuilder: (context) => [
        PopupMenuItem<ThinkingLevel>(
          enabled: false,
          child: SizedBox(
            width: 280,
            child: _GearSliderItem(
              value: thinking,
              accent: accent,
              onCommit: onThinkingChanged,
            ),
          ),
        ),
      ],
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? accent.withValues(alpha: 0.4) : AppColors.border,
          ),
          boxShadow: thinking == ThinkingLevel.flagship
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.24),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bolt,
              size: 14,
              color: active ? accent : AppColors.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              thinking.label,
              style: TextStyle(
                color: active ? accent : AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 15, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _GearSliderItem extends StatefulWidget {
  const _GearSliderItem({
    required this.value,
    required this.accent,
    required this.onCommit,
  });

  final ThinkingLevel value;
  final Color accent;
  final ValueChanged<ThinkingLevel> onCommit;

  @override
  State<_GearSliderItem> createState() => _GearSliderItemState();
}

class _GearSliderItemState extends State<_GearSliderItem> {
  late ThinkingLevel _preview;

  @override
  void initState() {
    super.initState();
    _preview = widget.value;
  }

  @override
  void didUpdateWidget(covariant _GearSliderItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _preview = widget.value;
    }
  }

  void _commit(ThinkingLevel level) {
    Navigator.of(context).pop();
    widget.onCommit(level);
  }

  @override
  Widget build(BuildContext context) {
    return ThinkingSlider(
      value: _preview,
      accent: widget.accent,
      onChanged: (v) => setState(() => _preview = v),
      onChangeEnd: _commit,
    );
  }
}
