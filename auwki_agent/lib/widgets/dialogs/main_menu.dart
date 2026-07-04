import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../theme.dart';
import 'profile_dialog.dart';
import 'settings_dialog.dart';

Future<void> showMainMenu(BuildContext context, Offset position) async {
  final box = context.findRenderObject() as RenderBox?;
  final pos = box?.localToGlobal(Offset.zero) ?? position;
  await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx + 40, pos.dy + 30, pos.dx + 41, pos.dy + 31),
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: AppColors.border),
    ),
    items: [
      PopupMenuItem(
        onTap: () => Future.delayed(
            const Duration(milliseconds: 50),
            () => showProfileDialog(context)),
        child: _row(Icons.person_outline, I18n.t('menu.profile')),
      ),
      PopupMenuItem(
        onTap: () => Future.delayed(
            const Duration(milliseconds: 50),
            () => showSettingsDialog(context)),
        child: _row(Icons.settings_outlined, I18n.t('menu.settings')),
      ),
    ],
  );
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