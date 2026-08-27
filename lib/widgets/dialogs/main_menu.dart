import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../theme.dart';
import 'profile_dialog.dart';
import 'settings_dialog.dart';

Future<void> showMainMenu(BuildContext context, Offset position) async {
  final box = context.findRenderObject() as RenderBox?;
  final pos = box?.localToGlobal(Offset.zero) ?? position;
  final size = box?.size ?? Size.zero;

  final result = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(
      pos.dx,
      pos.dy + size.height + 6,
      pos.dx + size.width,
      pos.dy + size.height + 7,
    ),
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: AppColors.border),
    ),
    items: [
      PopupMenuItem(
        value: 1,
        child: _row(Icons.person_outline, I18n.t('menu.profile')),
      ),
      PopupMenuItem(
        value: 2,
        child: _row(Icons.settings_outlined, I18n.t('menu.settings')),
      ),
    ],
  );

  if (!context.mounted) return;

  if (result == 1) {
    showProfileDialog(context);
  } else if (result == 2) {
    showSettingsDialog(context);
  }
}

Widget _row(IconData icon, String label) {
  return Row(
    children: [
      Icon(icon, size: 16, color: AppColors.textPrimary),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
    ],
  );
}
