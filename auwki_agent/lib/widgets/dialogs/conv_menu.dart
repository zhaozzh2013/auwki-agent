import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/models.dart';
import '../../theme.dart';

Future<void> showConvMenu({
  required BuildContext context,
  required Offset position,
  required Conversation conv,
  required List<Folder> folders,
  required ValueChanged<String?> onMoveToFolder,
  required VoidCallback onRename,
  required VoidCallback onTogglePin,
  required VoidCallback onToggleUnread,
  required VoidCallback onDelete,
}) async {
  final items = <PopupMenuEntry<int>>[
    PopupMenuItem(
      onTap: onRename,
      child: _MenuRow(
        icon: Icons.edit_outlined,
        label: I18n.t('sidebar.menu.rename'),
      ),
    ),
    PopupMenuItem(
      onTap: onTogglePin,
      child: _MenuRow(
        icon: conv.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: I18n.t('sidebar.menu.pin'),
      ),
    ),
    PopupMenuItem(
      onTap: onToggleUnread,
      child: _MenuRow(
        icon: conv.unread
            ? Icons.mark_email_read_outlined
            : Icons.mark_email_unread_outlined,
        label: I18n.t('sidebar.menu.unread'),
      ),
    ),
    if (folders.isNotEmpty)
      PopupMenuItem(
        child: SubmenuButton(
          folders: folders,
          currentFolderId: conv.folderId,
          onSelect: (id) {
            Navigator.of(context).pop();
            onMoveToFolder(id);
          },
        ),
      ),
    const PopupMenuDivider(),
    PopupMenuItem(
      onTap: onDelete,
      child: _MenuRow(
        icon: Icons.delete_outline,
        label: I18n.t('sidebar.menu.delete'),
        danger: true,
      ),
    ),
  ];

  await showMenu<int>(
    context: context,
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
    items: items,
  );
}

class SubmenuButton extends StatelessWidget {
  const SubmenuButton({
    super.key,
    required this.folders,
    required this.currentFolderId,
    required this.onSelect,
  });

  final List<Folder> folders;
  final String? currentFolderId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String?>(
      tooltip: I18n.t('sidebar.folder.move_tooltip'),
      offset: const Offset(180, 0),
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border),
      ),
      itemBuilder: (ctx) => [
        PopupMenuItem<String?>(
          onTap: () => onSelect(null),
          child: _MenuRow(
            icon: Icons.inbox,
            label: I18n.t('sidebar.folder.remove'),
            selected: currentFolderId == null,
          ),
        ),
        const PopupMenuDivider(),
        for (final f in folders)
          PopupMenuItem<String?>(
            onTap: () => onSelect(f.id),
            child: _MenuRow(
              icon: Icons.folder_outlined,
              label: f.name,
              selected: currentFolderId == f.id,
            ),
          ),
      ],
      child: _MenuRow(
        icon: Icons.drive_folder_upload_outlined,
        label: I18n.t('sidebar.folder.move_to'),
        trailing: Icon(
          Icons.chevron_right,
          size: 14,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.danger = false,
    this.selected = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool danger;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Colors.redAccent
        : (selected ? AppColors.primary : AppColors.textPrimary);
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
