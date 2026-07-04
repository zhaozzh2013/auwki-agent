import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../models/models.dart';
import '../services/settings_store.dart';
import '../state/chat_store.dart';
import '../theme.dart';
import 'dialogs/conv_menu.dart';
import 'dialogs/main_menu.dart';

class Sidebar extends StatefulWidget {
  const Sidebar({super.key, this.accent});

  final Color? accent;

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  Color get _accent => widget.accent ?? AppColors.primary;
  String? _hoveredKey;
  String? _dragOverFolderId;

  @override
  Widget build(BuildContext context) {
    final store = AppState.chatOf(context);
    return Container(
      width: 260,
      color: AppColors.sidebar,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildNewChatButton(store),
            const SizedBox(height: 16),
            Expanded(child: _buildList(store)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final settings = AppState.settingsOf(context);
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(

                        color: AppColors.surfaceAlt,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        settings.userInitial,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        settings.userName,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SquareIconButton(
              icon: Icons.menu,
              tooltip: I18n.t('sidebar.menu'),
              onTap: () => showMainMenu(context, Offset.zero),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewChatButton(ChatStore store) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          final id = store.newConversation();
          store.activate(id);
        },
        child: Container(
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 20, color: _accent),
              const SizedBox(width: 8),
              Text(
                I18n.t('sidebar.new_chat'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
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

    // Build static widgets (pinned + folders + section header)
    final staticChildren = <Widget>[
      if (pinned.isNotEmpty) ...[
        _SectionHeader(label: I18n.t('sidebar.section.pinned')),
        for (final c in pinned)
          _ConvRow(
            keyStr: 'pin_${c.id}',
            conv: c,
            accent: _accent,
            hoveredKey: _hoveredKey,
            onHover: (k) => setState(() => _hoveredKey = k),
            isActive: store.activeId == c.id,
            onTap: () => store.activate(c.id),
            onMenu: (offset) => _showConvMenu(context, c, offset),
          ),
        const SizedBox(height: 12),
      ],
      for (final f in folders) ...[
        _FolderHeader(
          folder: f,
          accent: _accent,
          isDragOver: _dragOverFolderId == f.id,
          onTap: () => store.toggleFolder(f.id),
          onWillAccept: () => setState(() => _dragOverFolderId = f.id),
          onLeave: () {
            if (_dragOverFolderId == f.id) {
              setState(() => _dragOverFolderId = null);
            }
          },
          onAccept: (convId) {
            store.moveToFolder(convId, f.id);
            setState(() => _dragOverFolderId = null);
          },
        ),
        if (f.expanded)
          for (final c in store.inFolder(f.id))
            _ConvRow(
              keyStr: 'fld_${c.id}',
              conv: c,
              accent: _accent,
              hoveredKey: _hoveredKey,
              onHover: (k) => setState(() => _hoveredKey = k),
              isActive: store.activeId == c.id,
              onTap: () => store.activate(c.id),
              onMenu: (offset) => _showConvMenu(context, c, offset),
              indent: true,
            ),
        const SizedBox(height: 12),
      ],
      _SectionHeader(label: I18n.t('sidebar.section.7d')),
    ];

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      buildDefaultDragHandles: false,
      onReorder: (oldIdx, newIdx) {
        // indices include staticChildren prepended
        final realOld = oldIdx - staticChildren.length;
        var realNew = newIdx - staticChildren.length;
        if (realNew > realOld) realNew -= 1;
        if (realOld < 0 || realOld >= topLevel.length) return;
        if (realNew < 0 || realNew >= topLevel.length) return;
        store.reorderTopLevel(realOld, realNew);
      },
      itemCount: staticChildren.length + topLevel.length,
      itemBuilder: (context, idx) {
        if (idx < staticChildren.length) {
          return KeyedSubtree(
            key: ValueKey('static_$idx'),
            child: staticChildren[idx],
          );
        }
        final c = topLevel[idx - staticChildren.length];
        return _ConvRow(
          keyStr: 'top_${c.id}',
          key: ValueKey('top_${c.id}'),
          conv: c,
          accent: _accent,
          hoveredKey: _hoveredKey,
          onHover: (k) => setState(() => _hoveredKey = k),
          isActive: store.activeId == c.id,
          onTap: () => store.activate(c.id),
          onMenu: (offset) => _showConvMenu(context, c, offset),
          draggable: true,
        );
      },
    );
  }

  void _showConvMenu(BuildContext context, Conversation c, Offset offset) {
    final store = AppState.chatOf(context);
    showConvMenu(
      context: context,
      position: offset,
      conv: c,
      onRename: () => _renameDialog(context, c),
      onTogglePin: () => store.togglePin(c.id),
      onToggleUnread: () => store.toggleUnread(c.id),
      onDelete: () => _deleteDialog(context, c),
    );
  }

  Future<void> _renameDialog(BuildContext context, Conversation c) async {
    final controller = TextEditingController(text: c.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(I18n.t('dialog.rename.title'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
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
            child: Text(I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(I18n.t('dialog.confirm'),
                style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty) {
      AppState.chatOf(context).rename(c.id, newName);
    }
  }

  Future<void> _deleteDialog(BuildContext context, Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(I18n.t('dialog.delete.title'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: Text(
          I18n.t('dialog.delete.body', {'name': c.title}),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(I18n.t('dialog.cancel'),
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('删除',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      AppState.chatOf(context).delete(c.id);
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Text(
        label,
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

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
    this.indent = false,
    this.draggable = false,
  });

  final String keyStr;
  final Conversation conv;
  final Color accent;
  final String? hoveredKey;
  final ValueChanged<String?> onHover;
  final bool isActive;
  final VoidCallback onTap;
  final void Function(Offset) onMenu;
  final bool indent;
  final bool draggable;

  bool get _hovered => hoveredKey == keyStr;

  @override
  Widget build(BuildContext context) {
    final tile = _buildTile(context);
    if (!draggable) return tile;

    // For draggable rows: long-press to start drag → drop into folder
    return LongPressDraggable<String>(
      data: conv.id,
      feedback: _DragFeedback(title: conv.title),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }

  Widget _buildTile(BuildContext context) {
    final hovered = _hovered;
    return Padding(
      padding: EdgeInsets.only(bottom: 2, left: indent ? 16 : 0),
      child: MouseRegion(
        onEnter: (_) => onHover(keyStr),
        onExit: (_) {
          if (_hovered) onHover(null);
        },
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapDown: (d) => onMenu(d.globalPosition),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
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
                      fontSize: 13,
                      fontWeight:
                          conv.unread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (conv.pinned)
                  Icon(Icons.push_pin, size: 14, color: accent)
                else if (hovered)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                        width: 22, height: 22),
                    iconSize: 14,
                    color: AppColors.textSecondary,
                    icon: Icon(Icons.more_horiz),
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox?;
                      if (box != null) {
                        final pos = box.localToGlobal(Offset.zero) +
                            const Offset(220, 28);
                        onMenu(pos);
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
        ),
      ),
    );
  }
}

class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.folder,
    required this.accent,
    required this.isDragOver,
    required this.onTap,
    required this.onWillAccept,
    required this.onLeave,
    required this.onAccept,
  });

  final Folder folder;
  final Color accent;
  final bool isDragOver;
  final VoidCallback onTap;
  final VoidCallback onWillAccept;
  final VoidCallback onLeave;
  final void Function(String convId) onAccept;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (_) {
        onWillAccept();
        return true;
      },
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (d) => onAccept(d.data),
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 32,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDragOver
                ? accent.withValues(alpha: 0.18)
                : Colors.transparent,
            border: isDragOver
                ? Border.all(color: accent.withValues(alpha: 0.5))
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 16,
                    color: isDragOver ? accent : AppColors.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: folder.expanded ? 0.5 : 0,
                  child: Icon(Icons.expand_more,
                      size: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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
      width: 42,
      height: 42,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Icon(icon, size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}