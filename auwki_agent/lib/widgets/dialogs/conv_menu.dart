import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/models.dart';
import '../../theme.dart';

Future<void> showConvMenu({
  required BuildContext context,
  required Offset position,
  required Conversation conv,
  required VoidCallback onRename,
  required VoidCallback onTogglePin,
  required VoidCallback onToggleUnread,
  required VoidCallback onDelete,
}) async {
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
    items: [
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
      const PopupMenuDivider(),
      PopupMenuItem(
        onTap: onDelete,
        child: _MenuRow(
          icon: Icons.delete_outline,
          label: I18n.t('sidebar.menu.delete'),
          danger: true,
        ),
      ),
    ],
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
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
        Text(
          label,
          style: TextStyle(color: color, fontSize: 13),
        ),
      ],
    );
  }
}