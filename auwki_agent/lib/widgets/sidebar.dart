import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../pages/profile_page.dart';
import '../services/export_service.dart';
import '../state/chat_store.dart';
import '../theme.dart';
import 'dialogs/conv_menu.dart';
import 'dialogs/main_menu.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({
    super.key,
    this.accent,
    this.showInspectorButton = false,
    this.onToggleInspector,
  });

  final Color? accent;

  /// 窄屏下显示“打开右侧面板”的开关按钮。
  final bool showInspectorButton;
  final VoidCallback? onToggleInspector;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  Color get _accent => widget.accent ?? AppColors.primary;
  String? _hoveredKey;

  bool _itemRightClickClaimed = false;

  void _claimItemRightClick() {
    _itemRightClickClaimed = true;
  }

  @override
  Widget build(BuildContext context) {
    final store = AppState.chatOf(context);
    return Container(
      width: 236,
      color: AppColors.sidebar,
      child: SafeArea(
        right: false,
        child: Listener(
          onPointerDown: (event) {
            if (event.buttons != kSecondaryButton) return;

            _itemRightClickClaimed = false;

            // 等待子项的 PointerDown / SecondaryTapDown 先声明右键归属，
            // 避免空白区域菜单和条目菜单同时弹出。
            Future.delayed(const Duration(milliseconds: 80), () {
              if (mounted && !_itemRightClickClaimed) {
                _showAreaMenu(context, event.position, store);
              }
            });
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const SizedBox(height: 10),
              _buildNewChatButton(store),
              const SizedBox(height: 12),
              Expanded(child: _buildList(store)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final settings = AppState.settingsOf(context);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: AppColors.border),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ProfilePage(),
                      ),
                    ),
                    child: Container(
                      height: 36,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              settings.userInitial,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              settings.userName,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (widget.showInspectorButton) ...[
              _SquareIconButton(
                icon: Icons.dashboard_customize_outlined,
                tooltip: 'Inspector',
                onTap: widget.onToggleInspector ?? () {},
              ),
              const SizedBox(width: 4),
            ],
            Builder(
              builder: (buttonContext) => _SquareIconButton(
                icon: Icons.menu,
                tooltip: I18n.t('sidebar.menu'),
                onTap: () => showMainMenu(buttonContext, Offset.zero),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewChatButton(ChatStore store) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          final id = store.newConversation();
          store.activate(id);
        },
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 18, color: _accent),
              const SizedBox(width: 7),
              Text(
                I18n.t('sidebar.new_chat'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(ChatStore store) {
    final pinned = store.pinned;
    final topLevel = store.topLevel;
    final folders = store.folders;

    final staticSlivers = <Widget>[
      if (pinned.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _SectionHeader(label: I18n.t('sidebar.section.pinned')),
        ),
        for (final c in pinned)
          SliverToBoxAdapter(
            child: _ConvRow(
              key: ValueKey('pin_${c.id}'),
              keyStr: 'pin_${c.id}',
              conv: c,
              accent: _accent,
              hoveredKey: _hoveredKey,
              onHover: (k) => setState(() => _hoveredKey = k),
              isActive: store.activeId == c.id,
              onTap: () => store.activate(c.id),
              onMenu: (offset) => _showConvMenu(context, c, offset),
              onClaimRightClick: _claimItemRightClick,
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
      for (final f in folders) ...[
        SliverToBoxAdapter(
          child: _FolderHeader(
            folder: f,
            accent: _accent,
            onTap: () => store.toggleFolder(f.id),
            onMenu: (offset) => _showFolderMenu(context, f, offset),
            onClaimRightClick: _claimItemRightClick,
          ),
        ),
        if (f.expanded)
          for (final c in store.inFolder(f.id))
            SliverToBoxAdapter(
              child: _ConvRow(
                key: ValueKey('fld_${c.id}'),
                keyStr: 'fld_${c.id}',
                conv: c,
                accent: _accent,
                hoveredKey: _hoveredKey,
                onHover: (k) => setState(() => _hoveredKey = k),
                isActive: store.activeId == c.id,
                onTap: () => store.activate(c.id),
                onMenu: (offset) => _showConvMenu(context, c, offset),
                onClaimRightClick: _claimItemRightClick,
                indent: true,
              ),
            ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
      SliverToBoxAdapter(
        child: _SectionHeader(label: I18n.t('sidebar.section.7d')),
      ),
    ];

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          sliver: SliverMainAxisGroup(slivers: staticSlivers),
        ),
        if (topLevel.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverReorderableList(
              itemBuilder: (context, idx) {
                final c = topLevel[idx];
                return _ConvRow(
                  key: ValueKey('top_${c.id}'),
                  keyStr: 'top_${c.id}',
                  conv: c,
                  accent: _accent,
                  hoveredKey: _hoveredKey,
                  onHover: (k) => setState(() => _hoveredKey = k),
                  isActive: store.activeId == c.id,
                  onTap: () => store.activate(c.id),
                  onMenu: (offset) => _showConvMenu(context, c, offset),
                  onClaimRightClick: _claimItemRightClick,
                  reorderIndex: idx,
                );
              },
              itemCount: topLevel.length,
              onReorder: (oldIdx, newIdx) {
                if (oldIdx < 0 || oldIdx >= topLevel.length) return;

                if (newIdx > oldIdx) {
                  newIdx -= 1;
                }

                newIdx = newIdx.clamp(0, topLevel.length - 1);

                if (oldIdx == newIdx) return;

                store.reorderTopLevel(oldIdx, newIdx);
              },
            ),
          ),
      ],
    );
  }

  Future<void> _showAreaMenu(
    BuildContext context,
    Offset position,
    ChatStore store,
  ) async {
    final result = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      items: [
        PopupMenuItem(
          value: 1,
          child: _EmptyAreaRow(
            icon: Icons.add,
            label: I18n.t('sidebar.new_chat'),
          ),
        ),
        PopupMenuItem(
          value: 2,
          child: _EmptyAreaRow(
            icon: Icons.create_new_folder_outlined,
            label: I18n.t('sidebar.folder.new'),
          ),
        ),
      ],
    );

    if (!mounted) return;

    if (result == 1) {
      // 等 PopupMenu 路由彻底关闭后再修改状态
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      final id = store.newConversation();
      store.activate(id);
    } else if (result == 2) {
      // 关键：不要在 PopupMenu 刚 pop 的同一帧里 showDialog
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;

      await _newFolderDialog(context, store);
    }
  }

  Future<void> _newFolderDialog(BuildContext context, ChatStore store) async {
    final controller = TextEditingController();

    try {
      final name = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('sidebar.folder.new'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: _accent,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: I18n.t('sidebar.folder.name'),
              hintStyle: TextStyle(color: AppColors.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent),
              ),
            ),
            onSubmitted: (value) {
              Navigator.of(ctx, rootNavigator: true).pop(value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx, rootNavigator: true).pop();
              },
              child: Text(
                I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(
                  ctx,
                  rootNavigator: true,
                ).pop(controller.text.trim());
              },
              child: Text(
                I18n.t('dialog.create'),
                style: TextStyle(color: _accent),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;

      final folderName = name?.trim();
      if (folderName == null || folderName.isEmpty) return;

      // 关键：Dialog 关闭后，再等一小段时间，保证 route / inherited dependencies 已释放
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;

      store.addFolder(folderName);
    } finally {
      controller.dispose();
    }
  }

  void _showConvMenu(BuildContext context, Conversation c, Offset offset) {
    final store = AppState.chatOf(context);
    showConvMenu(
      context: context,
      position: offset,
      conv: c,
      folders: store.folders,
      onMoveToFolder: (folderId) => store.moveToFolder(c.id, folderId),
      onRename: () => _renameDialog(context, c),
      onTogglePin: () => store.togglePin(c.id),
      onToggleUnread: () => store.toggleUnread(c.id),
      onDelete: () => _deleteDialog(context, c),
      onExport: () => _exportConversation(context, c),
    );
  }

  Future<void> _exportConversation(
    BuildContext context,
    Conversation c,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final md = ExportService.conversationToMarkdown(c);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}';
    final safeTitle = c.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: I18n.t('conv.export'),
        fileName: 'AUWKI-$safeTitle-$stamp.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
        bytes: utf8.encode(md),
      );
      if (path != null && path.isNotEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                I18n.t('conv.export.done', {'path': path}),
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: AppColors.surfaceAlt,
            ),
          );
      }
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(I18n.t('conv.export.failed')),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
  }

  Future<void> _showFolderMenu(
    BuildContext context,
    Folder f,
    Offset position,
  ) async {
    final result = await showMenu<int>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      items: [
        PopupMenuItem(
          value: 1,
          child: _EmptyAreaRow(
            icon: Icons.edit_outlined,
            label: I18n.t('sidebar.menu.rename'),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 2,
          child: _EmptyAreaRow(
            icon: Icons.delete_outline,
            label: I18n.t('sidebar.folder.delete'),
            danger: true,
          ),
        ),
      ],
    );

    if (!mounted) return;

    if (result == 1) {
      _renameFolderDialog(context, f);
    } else if (result == 2) {
      _deleteFolderDialog(context, f);
    }
  }

  Future<void> _renameFolderDialog(BuildContext context, Folder f) async {
    final store = AppState.chatOf(context);
    final controller = TextEditingController(text: f.name);

    try {
      final newName = await showDialog<String>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('sidebar.folder.rename'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: _accent,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent),
              ),
            ),
            onSubmitted: (value) {
              Navigator.of(ctx, rootNavigator: true).pop(value.trim());
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx, rootNavigator: true).pop();
              },
              child: Text(
                I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(
                  ctx,
                  rootNavigator: true,
                ).pop(controller.text.trim());
              },
              child: Text(
                I18n.t('dialog.save'),
                style: TextStyle(color: _accent),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;

      final name = newName?.trim();
      if (name == null || name.isEmpty) return;

      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      store.renameFolder(f.id, name);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteFolderDialog(BuildContext context, Folder f) async {
    final store = AppState.chatOf(context);
    final inFolder = store.conversations
        .where((c) => c.folderId == f.id)
        .length;

    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('sidebar.folder.delete'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: Text(
          I18n.t('sidebar.folder.delete_body', {
            'name': f.name,
            'count': '$inFolder',
          }),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx, rootNavigator: true).pop(false);
            },
            child: Text(
              I18n.t('dialog.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx, rootNavigator: true).pop(true);
            },
            child: Text(
              I18n.t('sidebar.menu.delete'),
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (ok == true) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;

      store.deleteFolder(f.id);
    }
  }

  Future<void> _renameDialog(BuildContext context, Conversation c) async {
    final controller = TextEditingController(text: c.title);
    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('dialog.rename.title'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: _accent,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: I18n.t('dialog.rename.hint'),
              hintStyle: TextStyle(color: AppColors.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: _accent),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(
                I18n.t('dialog.confirm'),
                style: TextStyle(color: _accent),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (newName != null && newName.trim().isNotEmpty) {
        AppState.chatOf(context).rename(c.id, newName);
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteDialog(BuildContext context, Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('dialog.delete.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: Text(
          I18n.t('dialog.delete.body', {'name': c.title}),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('dialog.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              I18n.t('sidebar.menu.delete'),
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (ok == true) {
      AppState.chatOf(context).delete(c.id);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 5),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ConvRow extends StatelessWidget {
  const _ConvRow({
    super.key,
    required this.keyStr,
    required this.conv,
    required this.accent,
    required this.hoveredKey,
    required this.onHover,
    required this.isActive,
    required this.onTap,
    required this.onMenu,
    required this.onClaimRightClick,
    this.indent = false,
    this.reorderIndex,
  });

  final String keyStr;
  final Conversation conv;
  final Color accent;
  final String? hoveredKey;
  final ValueChanged<String?> onHover;
  final bool isActive;
  final VoidCallback onTap;
  final void Function(Offset) onMenu;
  final VoidCallback onClaimRightClick;
  final bool indent;
  final int? reorderIndex;

  bool get _hovered => hoveredKey == keyStr;

  @override
  Widget build(BuildContext context) {
    final hovered = _hovered;

    Widget content = Padding(
      padding: EdgeInsets.only(bottom: 1, left: indent ? 14 : 0),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryButton) {
            onClaimRightClick();
          }
        },
        child: MouseRegion(
          onEnter: (_) => onHover(keyStr),
          onExit: (_) {
            if (_hovered) onHover(null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onSecondaryTapDown: (details) {
              onClaimRightClick();
              onMenu(details.globalPosition);
            },
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: isActive
                    ? accent.withValues(alpha: 0.18)
                    : (hovered ? AppColors.hover : Colors.transparent),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (conv.unread)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: conv.unread
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (conv.pinned)
                    Icon(Icons.push_pin, size: 14, color: accent)
                  else if (hovered)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final box = context.findRenderObject() as RenderBox?;
                        if (box != null) {
                          final pos =
                              box.localToGlobal(Offset.zero) +
                              const Offset(208, 26);
                          onMenu(pos);
                        }
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.more_horiz,
                          size: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (reorderIndex != null) {
      // 立即拖拽，桌面端不需要长按。
      content = ReorderableDragStartListener(
        index: reorderIndex!,
        child: content,
      );
    }

    return content;
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.folder,
    required this.accent,
    required this.onTap,
    required this.onMenu,
    required this.onClaimRightClick,
  });

  final Folder folder;
  final Color accent;
  final VoidCallback onTap;
  final void Function(Offset) onMenu;
  final VoidCallback onClaimRightClick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryButton) {
            onClaimRightClick();
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onSecondaryTapDown: (details) {
            onClaimRightClick();
            onMenu(details.globalPosition);
          },
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 15,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    folder.name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: folder.expanded ? 0.5 : 0,
                  child: Icon(
                    Icons.expand_more,
                    size: 16,
                    color: AppColors.textSecondary,
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

// ─────────────────────────────────────────────────────────────────────────────

class _EmptyAreaRow extends StatelessWidget {
  const _EmptyAreaRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Icon(icon, size: 19, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
