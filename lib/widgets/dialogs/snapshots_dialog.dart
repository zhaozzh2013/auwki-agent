import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/models.dart';
import '../../services/snapshot_service.dart';
import '../../state/chat_store.dart';
import '../../theme.dart';

/// 会话快照列表（A15）：存档、恢复、删除。
Future<void> showSnapshotsDialog(
  BuildContext context, {
  required ChatStore store,
  required Conversation conversation,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _SnapshotsDialog(store: store, conversation: conversation),
  );
}

class _SnapshotsDialog extends StatefulWidget {
  const _SnapshotsDialog({
    required this.store,
    required this.conversation,
  });

  final ChatStore store;
  final Conversation conversation;

  @override
  State<_SnapshotsDialog> createState() => _SnapshotsDialogState();
}

class _SnapshotsDialogState extends State<_SnapshotsDialog> {
  late Future<List<ConversationSnapshot>> _future;

  @override
  void initState() {
    super.initState();
    _future = SnapshotService.instance.list(
      conversationId: widget.conversation.id,
    );
  }

  void _reload() {
    setState(() {
      _future = SnapshotService.instance.list(
        conversationId: widget.conversation.id,
      );
    });
  }

  Future<void> _save() async {
    await SnapshotService.instance.save(widget.conversation);
    _reload();
  }

  Future<void> _restore(ConversationSnapshot snap) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('snapshot.restore.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: Text(
          I18n.t('snapshot.restore.body', {'label': snap.label}),
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              I18n.t('dialog.cancel'),
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(I18n.t('snapshot.restore.confirm')),
          ),
        ],
      ),
    );
    if (ok == true) {
      widget.store.restoreConversationSnapshot(snap.conversation.toJson());
      if (mounted) Navigator.pop(context);
    }
  }

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('snapshot.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        height: 360,
        child: FutureBuilder<List<ConversationSnapshot>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final list = snap.data ?? const <ConversationSnapshot>[];
            if (list.isEmpty) {
              return Center(
                child: Text(
                  I18n.t('snapshot.empty'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final s = list[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.history,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    s.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${s.conversation.messages.length} msg · ${_fmt(s.createdAt)}',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.restore,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        tooltip: I18n.t('snapshot.restore'),
                        onPressed: () => _restore(s),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        onPressed: () async {
                          await SnapshotService.instance.delete(s.id);
                          _reload();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.add, size: 16),
          label: Text(I18n.t('snapshot.save')),
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
