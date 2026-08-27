import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/task_queue_service.dart';
import '../../state/chat_store.dart';
import '../../theme.dart';

/// 任务中心（A04）：查看后台任务、取消、继续。
Future<void> showTaskCenterDialog(
  BuildContext context,
  ChatStore store,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _TaskCenterDialog(store: store),
  );
}

class _TaskCenterDialog extends StatelessWidget {
  const _TaskCenterDialog({required this.store});

  final ChatStore store;

  @override
  Widget build(BuildContext context) {
    final service = TaskQueueService.instance;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('task.center'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 480,
        height: 400,
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final tasks = service.tasks;
            if (tasks.isEmpty) {
              return Center(
                child: Text(
                  I18n.t('task.empty'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: tasks.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final t = tasks[i];
                final color = switch (t.status) {
                  TaskStatus.running => AppColors.primary,
                  TaskStatus.cancelled => Colors.orangeAccent,
                  TaskStatus.finished => const Color(0xFF66BB6A),
                  TaskStatus.failed => Colors.redAccent,
                };
                final statusLabel = switch (t.status) {
                  TaskStatus.running => I18n.t('task.status.running'),
                  TaskStatus.cancelled => I18n.t('task.status.cancelled'),
                  TaskStatus.finished => I18n.t('task.status.finished'),
                  TaskStatus.failed => I18n.t('task.status.failed'),
                };
                return ListTile(
                  dense: true,
                  leading: Icon(Icons.task_alt, size: 18, color: color),
                  title: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    t.progress.isEmpty
                        ? '$statusLabel · ${t.conversationId}'
                        : '$statusLabel · ${t.progress}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (t.status == TaskStatus.cancelled &&
                          t.checkpoint != null)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.play_circle_outline,
                            size: 18,
                            color: AppColors.primary,
                          ),
                          tooltip: I18n.t('task.resume'),
                          onPressed: () {
                            store.activate(t.conversationId);
                            service.requestResume(t.id);
                            Navigator.pop(context);
                          },
                        ),
                      if (t.status == TaskStatus.running)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.stop_circle_outlined,
                            size: 18,
                            color: Colors.redAccent,
                          ),
                          tooltip: I18n.t('task.cancel'),
                          onPressed: () => service.cancelTask(t.id),
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: AppColors.textTertiary,
                        ),
                        onPressed: () => service.remove(t.id),
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
