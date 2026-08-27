import 'dart:io';
import 'dart:math';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/settings_store.dart';
import '../services/tts_service.dart';
import '../services/command_palette.dart';
import '../services/export_service.dart';
import '../services/ai_providers.dart';
import '../services/demo_conversation.dart';
import '../services/provider_stats.dart';
import '../services/snapshot_service.dart';
import '../services/ui_state.dart';
import '../services/backup_service.dart';
import '../state/chat_store.dart';
import '../theme.dart';
import '../widgets/brand_logo.dart';
import '../widgets/code_block_builder.dart';
import '../widgets/chat_input.dart';
import '../widgets/inspector/browser_panel.dart';
import '../widgets/inspector/file_tree_panel.dart';
import '../widgets/inspector/git_panel.dart';
import '../widgets/inspector/round_changes_panel.dart';
import '../widgets/sidebar.dart';
import '../widgets/thinking_slider.dart';
import '../widgets/dialogs/favorites_dialog.dart';
import '../widgets/dialogs/settings_dialog.dart';
import '../widgets/dialogs/snapshots_dialog.dart';
import '../widgets/dialogs/scheduled_tasks_dialog.dart';
import '../widgets/dialogs/task_center_dialog.dart';
import '../widgets/dialogs/storage_dialog.dart';
import '../widgets/dialogs/logs_dialog.dart';
import '../widgets/dialogs/restore_dialog.dart';
import '../widgets/dialogs/model_compare_dialog.dart';
import '../widgets/dialogs/provider_status_dialog.dart';
import '../widgets/dialogs/guide_dialog.dart';
import '../pages/profile_page.dart';
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
  final ValueNotifier<String?> _regenerateDraft = ValueNotifier<String?>(null);
  final ValueNotifier<ReplyTarget?> _replyDraft = ValueNotifier<ReplyTarget?>(null);

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
    _regenerateDraft.dispose();
    _replyDraft.dispose();
    super.dispose();
  }

  KeyEventResult _handlePaletteShortcut(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyK) {
      _openCommandPalette();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _requestRegenerate(String convId, String userMsgId) {
    final store = AppState.chatOf(context);
    String? text;
    for (final c in store.conversations) {
      if (c.id == convId) {
        for (final m in c.messages) {
          if (m.id == userMsgId && m.sender == Sender.user) {
            text = m.text;
            break;
          }
        }
        break;
      }
    }
    if (text == null || text.trim().isEmpty) return;
    store.regenerateFrom(convId, userMsgId);
    _regenerateDraft.value = text;
  }

  void _startTask(String prompt) {
    // 只注入草稿，由空首页的 ChatInput 统一创建对话并发送，
    // 避免在这里先建对话、_send 再建一个导致残留空白对话。
    final store = AppState.chatOf(context);
    final id = store.newConversation(workspaceDir: _workspaceDir);
    store.activate(id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _regenerateDraft.value = prompt;
    });
  }

  Future<void> _pickWorkspace() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir != null && dir.trim().isNotEmpty) {
      setState(() => _workspaceDir = dir.trim());
    }
  }

  void _openCommandPalette() {
    final store = AppState.chatOf(context);
    final settings = AppState.settingsOf(context);
    final conv = store.active;
    final actions = <PaletteAction>[
      PaletteAction(
        icon: Icons.add_comment_outlined,
        label: I18n.t('palette.new_chat'),
        keywords: ['new', 'chat', '对话'],
        onTap: () => store.activate(null),
      ),
      PaletteAction(
        icon: Icons.settings_outlined,
        label: I18n.t('palette.settings'),
        keywords: ['setting', '设置'],
        onTap: () => showSettingsDialog(context),
      ),
      PaletteAction(
        icon: Icons.star,
        label: I18n.t('palette.favorites'),
        keywords: ['favorite', 'star', '收藏'],
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => FavoritesDialog(store: store),
        ),
      ),
      PaletteAction(
        icon: Icons.live_help_outlined,
        label: I18n.t('palette.demo'),
        keywords: ['demo', '演示', '示例'],
        onTap: () => _createDemoConversation(context),
      ),
      PaletteAction(
        icon: Icons.person_outline,
        label: I18n.t('palette.profile'),
        keywords: ['profile', '个人'],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
        ),
      ),
      PaletteAction(
        icon: Icons.dark_mode_outlined,
        label: I18n.t('palette.theme'),
        keywords: ['theme', '主题'],
        onTap: () => settings.setTheme(
          settings.theme == AppTheme.dark
              ? AppTheme.light
              : AppTheme.dark,
        ),
      ),
      PaletteAction(
        icon: Icons.swap_horiz,
        label: I18n.t('palette.mode'),
        keywords: ['mode', 'plan', 'work', '模式'],
        onTap: () => setState(
          () => _mode = _mode == WorkMode.work ? WorkMode.plan : WorkMode.work,
        ),
      ),
      PaletteAction(
        icon: Icons.bolt_outlined,
        label: I18n.t('palette.thinking'),
        keywords: ['thinking', '思考'],
        onTap: () => setState(() {
          final values = ThinkingLevel.values;
          _thinking = values[(values.indexOf(_thinking) + 1) % values.length];
        }),
      ),
      if (conv != null)
        PaletteAction(
          icon: Icons.ios_share,
          label: I18n.t('palette.export'),
          keywords: ['export', '导出'],
          onTap: () => ExportService.exportConversation(context, conv),
        ),
      if (conv != null)
        PaletteAction(
          icon: Icons.delete_sweep_outlined,
          label: I18n.t('palette.clear'),
          keywords: ['clear', '清空'],
          onTap: () => store.clearMessages(conv.id),
        ),
      if (conv != null && conv.messages.isNotEmpty)
        PaletteAction(
          icon: Icons.summarize_outlined,
          label: I18n.t('palette.summarize'),
          keywords: ['summary', 'summarize', '总结'],
          onTap: () => _summarizeConversation(context, conv),
        ),
      if (conv?.workspaceDir != null)
        PaletteAction(
          icon: Icons.folder_open,
          label: I18n.t('palette.workspace'),
          keywords: ['folder', 'workspace', '目录'],
          onTap: () => _openWorkspace(conv!.workspaceDir!),
        ),
      if (conv != null)
        PaletteAction(
          icon: Icons.history,
          label: I18n.t('snapshot.save'),
          keywords: ['snapshot', '快照', '存档'],
          onTap: () => SnapshotService.instance.save(conv),
        ),
      if (conv != null)
        PaletteAction(
          icon: Icons.history_toggle_off,
          label: I18n.t('snapshot.title'),
          keywords: ['snapshots', '快照列表', '恢复'],
          onTap: () =>
              showSnapshotsDialog(context, store: store, conversation: conv),
        ),
      PaletteAction(
        icon: Icons.task_alt,
        label: I18n.t('task.center'),
        keywords: ['task', '任务', 'queue'],
        onTap: () => showTaskCenterDialog(context, store),
      ),
      PaletteAction(
        icon: Icons.schedule,
        label: I18n.t('scheduled.title'),
        keywords: ['schedule', '定时', 'cron'],
        onTap: () => showScheduledTasksDialog(context),
      ),
      PaletteAction(
        icon: Icons.compress,
        label: I18n.t('palette.collapse_tools'),
        keywords: ['collapse', '折叠', 'tools'],
        onTap: UiState.toggleCollapseTools,
      ),
      PaletteAction(
        icon: Icons.school_outlined,
        label: I18n.t('guide.title'),
        keywords: ['guide', '引导', 'tutorial'],
        onTap: () => showGuideDialog(context),
      ),
      PaletteAction(
        icon: Icons.storage_outlined,
        label: I18n.t('settings.storage'),
        keywords: ['storage', '存储'],
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const StorageDialog(),
        ),
      ),
      PaletteAction(
        icon: Icons.article_outlined,
        label: I18n.t('settings.logs'),
        keywords: ['log', '日志'],
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const LogsDialog(),
        ),
      ),
      PaletteAction(
        icon: Icons.settings_backup_restore,
        label: I18n.t('settings.restore'),
        keywords: ['restore', '恢复'],
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => RestoreDialog(settings: settings, store: store),
        ),
      ),
      PaletteAction(
        icon: Icons.compare_arrows,
        label: I18n.t('settings.model_compare'),
        keywords: ['compare', '对比'],
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const ModelCompareDialog(),
        ),
      ),
      PaletteAction(
        icon: Icons.monitor_heart_outlined,
        label: I18n.t('settings.provider_status'),
        keywords: ['status', '状态'],
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => const ProviderStatusDialog(),
        ),
      ),
      PaletteAction(
        icon: Icons.star_outline,
        label: I18n.t('palette.favorites'),
        keywords: ['favorite', '收藏'],
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => FavoritesDialog(store: store),
        ),
      ),
      PaletteAction(
        icon: Icons.backup_outlined,
        label: I18n.t('settings.backup_now'),
        keywords: ['backup', '备份'],
        onTap: () => BackupService.createBackup(),
      ),
    ];
    showCommandPalette(context, actions: actions);
  }

  void _openWorkspace(String dir) {
    if (Platform.isWindows) {
      Process.start('explorer', [dir]);
    } else if (Platform.isMacOS) {
      Process.start('open', [dir]);
    } else if (Platform.isLinux) {
      Process.start('xdg-open', [dir]);
    }
  }

  /// 功能演示对话：删除旧的演示对话后重新创建并激活。
  void _createDemoConversation(BuildContext context) {
    final store = AppState.chatOf(context);
    for (final c in store.conversations.toList()) {
      if (c.id == DemoConversation.id) {
        store.delete(c.id);
      }
    }
    final demo = DemoConversation.build();
    store.importConversations([demo]);
    store.activate(demo.id);
  }

  /// B06：AI 生成对话摘要并保存。
  Future<void> _summarizeConversation(
    BuildContext context,
    Conversation conv,
  ) async {
    final settings = AppState.settingsOf(context);
    final store = AppState.chatOf(context);
    final messenger = ScaffoldMessenger.of(context);
    if (settings.apiKey.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.t('agent.no_api_key'))),
      );
      return;
    }
    // 取最近的消息（控制 token）。
    final buf = StringBuffer();
    var total = 0;
    for (final m in conv.messages.reversed) {
      if (m.sender == Sender.system || m.sender == Sender.tool) continue;
      final role = m.sender == Sender.user ? '用户' : 'AI';
      final line = '$role：${m.text.trim().replaceAll('\n', ' ')}\n';
      total += line.length;
      if (total > 30000 && buf.isNotEmpty) break;
      buf.write(line);
    }
    final text = buf.toString();
    if (text.trim().isEmpty) return;
    messenger.showSnackBar(
      SnackBar(content: Text(I18n.t('chat.summarizing'))),
    );
    try {
      final result = await settings.client.chat(
        ChatRequest(
          system: I18n.t('chat.summary_system'),
          messages: [
            {'role': 'user', 'content': text},
          ],
          model: settings.model,
          maxTokens: 800,
          temperature: 0.3,
        ),
      );
      final summary = result.trim();
      store.setSummary(conv.id, summary);
      if (!mounted || !context.mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(I18n.t('chat.summary_done')),
            backgroundColor: AppColors.surfaceAlt,
          ),
        );
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('chat.summary_title'),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: 440,
            child: SelectableText(
              summary,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.6,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                I18n.t('git.close'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${I18n.t('chat.summary_failed')} $e'),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
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
              recentWorkspaces: settings.recentWorkspaces,
              onModeChanged: (m) => setState(() => _mode = m),
              onThinkingChanged: (t) => setState(() => _thinking = t),
                  onWorkspaceChanged: (v) => setState(() => _workspaceDir = v),
                  regenerateDraft: _regenerateDraft,
                  replyDraft: _replyDraft,
                  onStartTask: _startTask,
                  onPickWorkspace: _pickWorkspace,
                  onUseWorkspace: (d) {
                    setState(() => _workspaceDir = d);
                    settings.addRecentWorkspace(d);
                  },
                  onResetWorkspace: () => setState(() => _workspaceDir = null),
                  onDemo: () => _createDemoConversation(context),
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
              recentWorkspaces: settings.recentWorkspaces,
              onModeChanged: (m) => setState(() => _mode = m),
              onThinkingChanged: (t) => setState(() => _thinking = t),
                  onWorkspaceChanged: (v) => setState(() => _workspaceDir = v),
                  regenerateDraft: _regenerateDraft,
                  replyDraft: _replyDraft,
                  onStartTask: _startTask,
                  onPickWorkspace: _pickWorkspace,
                  onUseWorkspace: (d) {
                    setState(() => _workspaceDir = d);
                    settings.addRecentWorkspace(d);
                  },
                  onResetWorkspace: () => setState(() => _workspaceDir = null),
                  onDemo: () => _createDemoConversation(context),
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
            onRegenerate: _requestRegenerate,
            regenerateDraft: _regenerateDraft,
            replyDraft: _replyDraft,
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
          width: settings.inspectorWidth,
          onClose: wide
              ? null
              : () => setState(() => _inspectorOpen = false),
        );
      },
    );

    final Widget content;
    if (wide) {
      final rightInspector = !settings.inspectorOnLeft;
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Sidebar(accent: _accent),
          if (!rightInspector) _inspectorHandle(settings, inspector),
          chatArea,
          if (rightInspector) _inspectorHandle(settings, inspector),
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
          if (_inspectorOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _inspectorOpen = false),
                child: Container(color: Colors.black38),
              ),
            ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width * 0.85,
              child: AnimatedSwitcher(
                duration: kAnimSlow,
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
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(AppColors.bg, AppColors.primary, 0.05)!,
              AppColors.bg,
            ],
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Focus(
                autofocus: true,
                onKeyEvent: _handlePaletteShortcut,
                child: _FlagshipShell(enabled: isFlagship, child: content),
              ),
            ),
            // C04：底部状态栏。
            const _StatusBar(),
          ],
        ),
      ),
    );
  }

  Widget _inspectorHandle(SettingsStore settings, Widget inspector) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            final w = settings.inspectorWidth +
                (settings.inspectorOnLeft ? -d.delta.dx : d.delta.dx);
            settings.setInspectorWidth(w);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: Container(width: 6, color: Colors.transparent),
          ),
        ),
        SizedBox(width: settings.inspectorWidth, child: inspector),
      ],
    );
  }
}

/// C04：底部状态栏——当前供应商/模型、最近请求延迟、成功率。
class _StatusBar extends StatelessWidget {
  const _StatusBar();

  @override
  Widget build(BuildContext context) {
    final settings = AppState.settingsOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([
        settings,
        ProviderStatsService.instance,
      ]),
      builder: (context, _) {
        final overview = ProviderStatsService.instance.overview(
          settings.providerId,
        );
        final last = ProviderStatsService.instance.entries.isEmpty
            ? null
            : ProviderStatsService.instance.entries.last;
        final successRate = overview.count == 0
            ? null
            : overview.okCount / overview.count;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.sidebar,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.bolt, size: 12, color: AppColors.primary),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '${settings.provider.label} · ${settings.model}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ),
              const Spacer(),
              if (last != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    I18n.t('status.last_req', {
                      'ms': '${last.latencyMs}',
                    }),
                    style: TextStyle(
                      color: last.ok
                          ? AppColors.textTertiary
                          : Colors.redAccent,
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              if (successRate != null)
                Text(
                  I18n.t('status.success', {
                    'rate': '${(successRate * 100).toStringAsFixed(0)}%',
                    'count': '${overview.count}',
                  }),
                  style: TextStyle(
                    color: successRate >= 0.9
                        ? const Color(0xFF66BB6A)
                        : Colors.orangeAccent,
                    fontSize: 10.5,
                    fontFamily: 'monospace',
                  ),
                ),
            ],
          ),
        );
      },
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
    this.width = 340,
    this.onClose,
  });

  final Conversation? conversation;
  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color accent;
  final double width;
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
      width: widget.width,
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
                  3 => GitPanel(
                    accent: widget.accent,
                    workspacePath: conv?.workspaceDir,
                  ),
                  4 => FileTreePanel(
                    workspaceDir: conv?.workspaceDir,
                    accent: widget.accent,
                  ),
                  _ => const SizedBox.shrink(),
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
      (Icons.folder_outlined, I18n.t('inspector.tab.files')),
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
                  duration: kAnimFast,
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
          Flexible(
            flex: 2,
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
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
    required this.recentWorkspaces,
    required this.regenerateDraft,
    required this.replyDraft,
    required this.onStartTask,
    required this.onPickWorkspace,
    required this.onUseWorkspace,
    required this.onResetWorkspace,
    required this.onDemo,
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
  final List<String> recentWorkspaces;
  final ValueNotifier<String?> regenerateDraft;
  final ValueNotifier<ReplyTarget?> replyDraft;
  final ValueChanged<String> onStartTask;
  final VoidCallback onPickWorkspace;
  final ValueChanged<String> onUseWorkspace;
  final VoidCallback onResetWorkspace;
  final VoidCallback onDemo;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final ValueChanged<String?> onWorkspaceChanged;
  final String greeting;

  @override
  Widget build(BuildContext context) {
    final settings = AppState.settingsOf(context);
    // 路由已配置 Key 时也视为已配置，避免引导页一直显示。
    final showOnboarding =
        settings.apiKey.trim().isEmpty &&
        !settings.providerRoutes.any(
          (r) => (r['apiKey'] ?? '').toString().trim().isNotEmpty,
        );
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
                    if (showOnboarding) ...[
                      _OnboardingCard(accent: accent),
                      const SizedBox(height: 12),
                    ],
                    ControlsCard(
                      mode: mode,
                      thinking: thinking,
                      accent: accent,
                      accentSoft: accentSoft,
                      workspaceDir: workspaceDir,
                      regenerateDraft: regenerateDraft,
                      replyDraft: replyDraft,
                      onModeChanged: onModeChanged,
                      onThinkingChanged: onThinkingChanged,
                    ),
                    const SizedBox(height: 12),
                    _Entrance(
                      child: _QuickStartRow(
                        workspaceDir: workspaceDir,
                        accent: accent,
                        onPickWorkspace: onPickWorkspace,
                        onStart: onStartTask,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // C10：模板卡片 + 最近项目。
                    _Entrance(
                      child: _TemplateCards(
                        accent: accent,
                        onStart: onStartTask,
                      ),
                    ),
                    if (recentWorkspaces.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _Entrance(
                        child: _RecentProjects(
                          dirs: recentWorkspaces,
                          accent: accent,
                          onUse: onUseWorkspace,
                          onReset: onResetWorkspace,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: onDemo,
                      icon: const Icon(Icons.live_help_outlined, size: 15),
                      label: Text(I18n.t('palette.demo')),
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        textStyle: const TextStyle(fontSize: 12),
                      ),
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
      width: 680,
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
    required this.onRegenerate,
    required this.regenerateDraft,
    required this.replyDraft,
    required this.greeting,
  });

  final Conversation conversation;
  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color accent;
  final Color accentSoft;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final void Function(String convId, String userMsgId) onRegenerate;
  final ValueNotifier<String?> regenerateDraft;
  final ValueNotifier<ReplyTarget?> replyDraft;
  final String greeting;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ScrollController _scroll = ScrollController();
  int? _lastMessageTextLength;
  bool _userScrolling = false;

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
      // 用户正在向上滚动浏览历史时不要抢滚动条；
      // 新消息追加（countChanged）且用户停留在底部时才跟到末尾。
      if (_userScrolling) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scroll.hasClients || !_scroll.position.hasPixels) return;
        final nearBottom =
            _scroll.position.maxScrollExtent - _scroll.offset < 160;
        if (!nearBottom) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!mounted || !_scroll.hasClients) return;
      final offset = _scroll.offset;
      if (_scroll.position.userScrollDirection != ScrollDirection.idle) {
        _userScrolling = true;
      } else if (_userScrolling) {
        // 用户滚回底部附近时解除锁定，允许自动跟随。
        if (_scroll.position.maxScrollExtent - offset < 160) {
          _userScrolling = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── B13：TTS 朗读 ──
  Future<void> _speakMessage(Conversation conv, Message msg) async {
    if (TtsService.speaking) {
      await TtsService.stop();
      return;
    }
    await TtsService.speak(msg.text);
  }

  // ── B09：消息翻译 ──
  Future<void> _translateMessage(Conversation conv, Message msg) async {
    final settings = AppState.settingsOf(context);
    final store = AppState.chatOf(context);
    final messenger = ScaffoldMessenger.of(context);
    if (settings.apiKey.isEmpty || msg.text.trim().isEmpty) return;
    messenger.showSnackBar(
      SnackBar(content: Text(I18n.t('chat.translating'))),
    );
    try {
      final result = await settings.client.chat(
        ChatRequest(
          system: I18n.t('chat.translate_system'),
          messages: [
            {'role': 'user', 'content': msg.text},
          ],
          model: settings.model,
          maxTokens: 2048,
          temperature: 0.2,
        ),
      );
      final text = result.trim();
      if (text.isEmpty) throw StateError('empty translation');
      store.addMessage(
        conv.id,
        Message(
          id: 'm_${DateTime.now().microsecondsSinceEpoch}_tr',
          sender: Sender.assistant,
          text: '> 🌐 ${I18n.t('chat.translation')}\n\n$text',
        ),
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(I18n.t('chat.translation_done')),
            backgroundColor: AppColors.surfaceAlt,
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${I18n.t('chat.translation_failed')} $e'),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
  }

  // ── B10：续写 / 重写（复用 regenerateDraft 触发发送） ──
  void _continueMessage(Conversation conv) {
    widget.regenerateDraft.value = I18n.t('chat.continue_prompt');
  }

  Future<void> _rewriteMessage(Conversation conv, Message msg) async {
    final controller = TextEditingController();
    final requirement = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('chat.rewrite_title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: I18n.t('chat.rewrite_hint'),
            hintStyle: TextStyle(color: AppColors.textTertiary),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              I18n.t('git.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text(I18n.t('dialog.confirm')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (requirement == null || requirement.trim().isEmpty) return;
    widget.regenerateDraft.value = I18n.t('chat.rewrite_prompt', {
      'requirement': requirement.trim(),
    });
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
                  // B08 长对话优化：关闭自动保活、限制缓存范围，
                  // 配合 builder 延迟构建保持万条消息滚动流畅。
                  // 注意：不要设置 scrollCacheExtent——该 API 在当前 SDK
                  // 会触发 RenderViewportBase 空指针异常导致消息列表空白。
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  // 不要用 AnimatedSwitcher 包每个 item：滚动虚拟化回收时
                  // 重建动画状态机 + 悬停 setState 重建 MouseRegion，
                  // 会触发该 SDK 的 MouseTracker 重入渲染 bug（消息空白/滚动卡顿）。
                  itemBuilder: (context, i) {
                    final message = conv.messages[i];
                    return KeyedSubtree(
                      key: ValueKey(message.id),
                      child: _MessageBubble(
                        message: message,
                        accent: widget.accent,
                        palette: context.palette,
                        onToggleFavorite: () {
                          AppState.chatOf(context).toggleFavorite(
                            conv.id,
                            message.id,
                          );
                        },
                        onReply: () {
                          final preview =
                              message.text.trim().replaceAll('\n', ' ');
                          widget.replyDraft.value = ReplyTarget(
                            sender: message.sender,
                            preview: preview.length > 120
                                ? '${preview.substring(0, 120)}…'
                                : preview,
                          );
                        },
                        onTranslate: message.sender == Sender.tool
                            ? null
                            : () => _translateMessage(conv, message),
                        onContinue: message.sender == Sender.assistant
                            ? () => _continueMessage(conv)
                            : null,
                        onRewrite: message.sender == Sender.assistant
                            ? () => _rewriteMessage(conv, message)
                            : null,
                        onSpeak: message.sender == Sender.tool
                            ? null
                            : () => _speakMessage(conv, message),
                        onEdit: message.sender == Sender.user
                            ? (newText) {
                                AppState.chatOf(context).editUserMessage(
                                  conv.id,
                                  message.id,
                                  newText,
                                );
                                widget.onRegenerate(conv.id, message.id);
                              }
                            : null,
                        onRegenerate: message.sender == Sender.user
                            ? () => widget.onRegenerate(conv.id, message.id)
                            : null,
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
                regenerateDraft: widget.regenerateDraft,
                replyDraft: widget.replyDraft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickStartRow extends StatelessWidget {
  const _QuickStartRow({
    required this.workspaceDir,
    required this.accent,
    required this.onPickWorkspace,
    required this.onStart,
  });

  final String? workspaceDir;
  final Color accent;
  final VoidCallback onPickWorkspace;
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context) {
    final tasks = [
      I18n.t('home.task.progress'),
      I18n.t('home.task.snake'),
      I18n.t('home.task.review'),
      I18n.t('home.task.report'),
    ];
    return Container(
      width: 680,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: onPickWorkspace,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Icon(
                      Icons.folder_outlined,
                      size: 15,
                      color: accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        workspaceDir?.trim().isNotEmpty == true
                            ? workspaceDir!
                            : I18n.t('home.workspace.pick'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: workspaceDir?.trim().isNotEmpty == true
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                for (final t in tasks)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      t,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                      ),
                    ),
                    backgroundColor: AppColors.surfaceAlt,
                    side: BorderSide(color: AppColors.border),
                    onPressed: () => onStart(t),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Entrance extends StatelessWidget {
  const _Entrance({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: kAnimSlow,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.accent,
    required this.palette,
    this.onEdit,
    this.onRegenerate,
    this.onToggleFavorite,
    this.onReply,
    this.onTranslate,
    this.onContinue,
    this.onRewrite,
    this.onSpeak,
  });

  final Message message;
  final Color accent;
  final AppPalette palette;
  final ValueChanged<String>? onEdit;
  final VoidCallback? onRegenerate;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onReply;
  final VoidCallback? onTranslate;
  final VoidCallback? onContinue;
  final VoidCallback? onRewrite;
  final VoidCallback? onSpeak;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  // 悬停状态用 ValueNotifier 局部驱动按钮行，避免 setState 重建整个气泡
  // （含 MarkdownBody / MouseRegion 重挂载），消除滚动卡顿和该 SDK
  // MouseTracker 在帧回调中的重入渲染 bug。
  final ValueNotifier<bool> _hover = ValueNotifier(false);

  void _setHovered(bool value) {
    if (_hover.value == value) return;
    _hover.value = value;
  }

  @override
  void dispose() {
    _hover.dispose();
    super.dispose();
  }

  Message get message => widget.message;
  Color get accent => widget.accent;

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

  Future<void> _editMessage(BuildContext context) async {
    final controller = TextEditingController(text: message.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('chat.edit.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 8,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.primary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              I18n.t('git.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(I18n.t('dialog.save')),
          ),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      widget.onEdit?.call(result.trim());
    }
  }

  Widget _smallIcon(
    BuildContext context,
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: 12, color: AppColors.textTertiary),
        ),
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
    final fg = isUser ? Colors.white : AppColors.textPrimary;
    final label = isUser ? I18n.t('chat.you') : I18n.t('chat.assistant');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: align,
        child: MouseRegion(
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
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
                  children: isUser
                      ? [
                            _smallIcon(
                              context,
                              Icons.copy,
                              I18n.t('conv.copy'),
                              () => _copyMessage(context),
                            ),
                            if (widget.onToggleFavorite != null)
                              _smallIcon(
                                context,
                                message.favorite
                                    ? Icons.star
                                    : Icons.star_border,
                                I18n.t('chat.favorite'),
                                widget.onToggleFavorite!,
                              ),
                            if (widget.onReply != null)
                              _smallIcon(
                                context,
                                Icons.reply,
                                I18n.t('chat.reply'),
                                widget.onReply!,
                              ),
                            if (widget.onTranslate != null)
                              _smallIcon(
                                context,
                                Icons.translate,
                                I18n.t('chat.translate'),
                                widget.onTranslate!,
                              ),
                            if (widget.onSpeak != null)
                              _smallIcon(
                                context,
                                Icons.volume_up_outlined,
                                I18n.t('chat.speak'),
                                widget.onSpeak!,
                              ),
                            if (widget.onEdit != null)
                              _smallIcon(
                                context,
                                Icons.edit_outlined,
                                I18n.t('chat.edit'),
                                () => _editMessage(context),
                              ),
                            if (widget.onRegenerate != null)
                              _smallIcon(
                                context,
                                Icons.refresh,
                                I18n.t('chat.regenerate'),
                                widget.onRegenerate!,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              label,
                              style: TextStyle(
                                color: accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ]
                      : [
                            Text(
                              label,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            ValueListenableBuilder<bool>(
                              valueListenable: _hover,
                              builder: (context, hovered, _) => AnimatedOpacity(
                                opacity: hovered ? 1 : 0,
                                duration: const Duration(milliseconds: 150),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.onToggleFavorite != null)
                                      _smallIcon(
                                        context,
                                        message.favorite
                                            ? Icons.star
                                            : Icons.star_border,
                                        I18n.t('chat.favorite'),
                                        widget.onToggleFavorite!,
                                      ),
                                    if (widget.onReply != null)
                                      _smallIcon(
                                        context,
                                        Icons.reply,
                                        I18n.t('chat.reply'),
                                        widget.onReply!,
                                      ),
                                    if (widget.onTranslate != null)
                                      _smallIcon(
                                        context,
                                        Icons.translate,
                                        I18n.t('chat.translate'),
                                        widget.onTranslate!,
                                      ),
                                    if (widget.onSpeak != null)
                                      _smallIcon(
                                        context,
                                        Icons.volume_up_outlined,
                                        I18n.t('chat.speak'),
                                        widget.onSpeak!,
                                      ),
                                    if (widget.onContinue != null)
                                      _smallIcon(
                                        context,
                                        Icons.more_horiz,
                                        I18n.t('chat.continue'),
                                        widget.onContinue!,
                                      ),
                                    if (widget.onRewrite != null)
                                      _smallIcon(
                                        context,
                                        Icons.auto_fix_high,
                                        I18n.t('chat.rewrite'),
                                        widget.onRewrite!,
                                      ),
                                    _smallIcon(
                                      context,
                                      Icons.copy,
                                      I18n.t('conv.copy'),
                                      () => _copyMessage(context),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              accent,
                              Color.lerp(accent, Colors.black, 0.26)!,
                            ],
                          )
                        : null,
                    color: isUser ? null : AppColors.surface,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(isUser ? 16 : 4),
                      topRight: Radius.circular(isUser ? 4 : 16),
                      bottomLeft: const Radius.circular(16),
                      bottomRight: const Radius.circular(16),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: isUser
                            ? accent.withValues(alpha: 0.16)
                            : AppColors.cardShadow,
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
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
                                    color: isUser
                                        ? Colors.white.withValues(alpha: 0.16)
                                        : AppColors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '📎 ${a.name}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isUser
                                          ? Colors.white.withValues(
                                              alpha: 0.92,
                                            )
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      MarkdownBody(
                        data: message.text,
                        selectable: true,
                        builders: {
                          'pre': CopyCodeBlockBuilder(),
                        },
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: fg,
                            fontSize: 13.5,
                            height: 1.45,
                          ),
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
                          em: TextStyle(
                            color: fg,
                            fontStyle: FontStyle.italic,
                          ),
                          code: TextStyle(
                            color: isUser
                                ? Colors.white
                                : widget.palette.codeFg,
                            backgroundColor: isUser
                                ? Colors.white.withValues(alpha: 0.18)
                                : widget.palette.codeBg.withValues(
                                    alpha: 0.5,
                                  ),
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: isUser
                                ? Colors.white.withValues(alpha: 0.08)
                                : widget.palette.codeblockBg,
                            border: Border.all(
                              color: AppColors.border,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          codeblockPadding: const EdgeInsets.all(12),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: accent, width: 3),
                            ),
                          ),
                          blockquotePadding: const EdgeInsets.only(left: 10),
                          horizontalRuleDecoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppColors.border,
                                width: 1,
                              ),
                            ),
                          ),
                          listBullet: TextStyle(
                            color: fg,
                            fontSize: 13.5,
                          ),
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
              boxShadow: [
                BoxShadow(
                  color: AppColors.cardShadow,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
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
    final debug = AppState.settingsOf(context).debugMode;
    final collapsed = UiState.collapseTools.value;
    final expanded = (!collapsed && _expanded) || debug;
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
                        Flexible(
                          child: Text(
                            _toolLabel(m.toolName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (status.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          AnimatedSwitcher(
                            duration: kAnimFast,
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
                        _truncate(
                          _visibleToolContent(m),
                          debug ? 2000 : 140,
                        ),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                        maxLines: expanded ? null : 1,
                        overflow: expanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                      ),
                    ],
                    if (expanded && hasResult) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (m.toolName == 'screenshot') ...[
                              _ScreenshotPreview(path: m.toolResult!),
                              const SizedBox(height: 6),
                            ],
                            Text(
                              m.toolResult!,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11,
                                fontFamily: 'monospace',
                                height: 1.4,
                              ),
                            ),
                          ],
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
    this.regenerateDraft,
    this.replyDraft,
    required this.onModeChanged,
    required this.onThinkingChanged,
    this.conversationId,
  });

  final WorkMode mode;
  final ThinkingLevel thinking;
  final Color accent;
  final Color accentSoft;
  final String? workspaceDir;
  final ValueNotifier<String?>? regenerateDraft;
  final ValueNotifier<ReplyTarget?>? replyDraft;
  final ValueChanged<WorkMode> onModeChanged;
  final ValueChanged<ThinkingLevel> onThinkingChanged;
  final String? conversationId;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 680,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
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
              if (conversationId != null)
                Flexible(
                  child: _ModelMenuButton(
                    conversationId: conversationId!,
                    accent: accent,
                  ),
                ),
              const SizedBox(width: 6),
              Flexible(
                child: _ThinkingMenuButton(
                  thinking: thinking,
                  accent: accent,
                  accentSoft: accentSoft,
                  onThinkingChanged: onThinkingChanged,
                ),
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
            regenerateDraft: regenerateDraft,
            replyDraft: replyDraft,
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

/// G02：对话级模型选择器（null = 跟随全局设置）。
class _ModelMenuButton extends StatelessWidget {
  const _ModelMenuButton({
    required this.conversationId,
    required this.accent,
  });

  final String conversationId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final settings = AppState.settingsOf(context);
    final store = AppState.chatOf(context);
    Conversation? conv;
    for (final c in store.conversations) {
      if (c.id == conversationId) {
        conv = c;
        break;
      }
    }
    if (conv == null || settings.provider.models.isEmpty) {
      return const SizedBox.shrink();
    }
    final current = conv.model ?? settings.model;
    String? currentLabel;
    for (final m in settings.provider.models) {
      if (m.id == current) {
        currentLabel = m.label;
        break;
      }
    }
    final label = currentLabel ?? current;
    final usingGlobal = conv.model == null;
    return PopupMenuButton<String?>(
      tooltip: I18n.t('chat.conv_model'),
      color: AppColors.surface,
      onSelected: (v) => store.setConversationModel(conversationId, v),
      itemBuilder: (context) => [
        PopupMenuItem<String?>(
          value: null,
          child: Row(
            children: [
              Icon(
                Icons.settings_suggest_outlined,
                size: 15,
                color: usingGlobal ? accent : AppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Text(
                I18n.t('chat.conv_model_global'),
                style: TextStyle(
                  color: usingGlobal ? accent : AppColors.textPrimary,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        for (final m in settings.provider.models)
          PopupMenuItem<String?>(
            value: m.id,
            child: Row(
              children: [
                Icon(
                  Icons.model_training,
                  size: 15,
                  color: current == m.id ? accent : AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: current == m.id
                          ? accent
                          : AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: current == m.id
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (current == m.id)
                  Icon(Icons.check, size: 14, color: accent),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.model_training, size: 13, color: accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.expand_more,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
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
        duration: kAnimMed,
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
            Flexible(
              child: Text(
                thinking.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? accent : AppColors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
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

/// A10：截图工具结果的图片预览。
class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final f = File(path);
    if (!f.existsSync()) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(f, height: 180, fit: BoxFit.contain),
    );
  }
}

/// C10：新建对话模板卡片。
class _TemplateCards extends StatelessWidget {
  const _TemplateCards({required this.accent, required this.onStart});

  final Color accent;
  final ValueChanged<String> onStart;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        Icons.forum_outlined,
        I18n.t('home.template.empty'),
        I18n.t('home.template.empty.prompt'),
      ),
      (
        Icons.code,
        I18n.t('home.template.review'),
        I18n.t('home.template.review.prompt'),
      ),
      (
        Icons.edit_note,
        I18n.t('home.template.writing'),
        I18n.t('home.template.writing.prompt'),
      ),
      (
        Icons.translate,
        I18n.t('home.template.translation'),
        I18n.t('home.template.translation.prompt'),
      ),
      (
        Icons.summarize_outlined,
        I18n.t('home.template.report'),
        I18n.t('home.template.report.prompt'),
      ),
    ];
    return Container(
      width: 680,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (icon, label, prompt) in items)
            ActionChip(
              avatar: Icon(icon, size: 14, color: accent),
              label: Text(
                label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                ),
              ),
              backgroundColor: AppColors.surfaceAlt,
              side: BorderSide(color: AppColors.border),
              onPressed: () => onStart(prompt),
            ),
        ],
      ),
    );
  }
}

/// C10：最近项目快捷入口。
class _RecentProjects extends StatelessWidget {
  const _RecentProjects({
    required this.dirs,
    required this.accent,
    required this.onUse,
    required this.onReset,
  });

  final List<String> dirs;
  final Color accent;
  final ValueChanged<String> onUse;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 680,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final d in dirs.take(4))
                  ActionChip(
                    label: Text(
                      d,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    backgroundColor: AppColors.surfaceAlt,
                    side: BorderSide(color: AppColors.border),
                    onPressed: () => onUse(d),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onReset,
            child: Text(
              I18n.t('home.workspace.reset'),
              style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
