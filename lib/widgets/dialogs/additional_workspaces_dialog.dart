import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../state/chat_store.dart';
import '../../theme.dart';

/// A12：会话附加工作区目录管理。
Future<void> showAdditionalWorkspacesDialog(
  BuildContext context,
  ChatStore store,
  String convId,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AdditionalWorkspacesDialog(store: store, convId: convId),
  );
}

class _AdditionalWorkspacesDialog extends StatelessWidget {
  const _AdditionalWorkspacesDialog({
    required this.store,
    required this.convId,
  });

  final ChatStore store;
  final String convId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('workspaces.extra'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        height: 300,
        child: AnimatedBuilder(
          animation: store,
          builder: (context, _) {
            final list = store.conversations
                .where((c) => c.id == convId)
                .toList();
            final items = list.isEmpty
                ? const <String>[]
                : list.first.additionalWorkspaces;
            if (items.isEmpty) {
              return Center(
                child: Text(
                  I18n.t('workspaces.empty'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) => ListTile(
                dense: true,
                leading: Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                title: Text(
                  items[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 16,
                    color: Colors.redAccent,
                  ),
                  onPressed: () {
                    store.setAdditionalWorkspaces(
                      convId,
                      [
                        for (final d in items)
                          if (d != items[i]) d,
                      ],
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            final dir = await FilePicker.getDirectoryPath();
            if (dir == null || dir.trim().isEmpty) return;
            final list = store.conversations
                .where((c) => c.id == convId)
                .toList();
            final current = list.isEmpty
                ? const <String>[]
                : list.first.additionalWorkspaces;
            if (!current.contains(dir.trim())) {
              store.setAdditionalWorkspaces(convId, [...current, dir.trim()]);
            }
          },
          icon: const Icon(Icons.add, size: 16),
          label: Text(I18n.t('workspaces.add')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(fontSize: 12.5),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            I18n.t('dialog.cancel'),
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
