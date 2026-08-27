import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/models.dart';
import '../../state/chat_store.dart';
import '../../theme.dart';

/// B02：收藏夹——跨对话展示所有收藏消息，点击跳转到对应对话。
class FavoritesDialog extends StatelessWidget {
  const FavoritesDialog({super.key, required this.store});

  final ChatStore store;

  @override
  Widget build(BuildContext context) {
    final favorites = store.favorites;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      title: Row(
        children: [
          Icon(Icons.star, size: 18, color: AppColors.planAccent),
          const SizedBox(width: 8),
          Text(
            I18n.t('favorites.title'),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        height: 380,
        child: favorites.isEmpty
            ? Center(
                child: Text(
                  I18n.t('favorites.empty'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: favorites.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: AppColors.border),
                itemBuilder: (context, i) {
                  final (conv, msg) = favorites[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      msg.sender == Sender.user
                          ? Icons.person_outline
                          : Icons.auto_awesome,
                      size: 15,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      msg.text.trim().replaceAll('\n', ' '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                      ),
                    ),
                    subtitle: Text(
                      '${conv.title} · ${_fmtTime(msg.createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () {
                      store.activate(conv.id);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  static String _fmtTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}
