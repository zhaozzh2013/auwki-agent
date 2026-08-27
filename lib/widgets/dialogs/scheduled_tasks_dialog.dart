import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/scheduled_task_service.dart';
import '../../theme.dart';

/// 定时任务管理（A13）。
Future<void> showScheduledTasksDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _ScheduledTasksDialog(),
  );
}

class _ScheduledTasksDialog extends StatelessWidget {
  const _ScheduledTasksDialog();

  @override
  Widget build(BuildContext context) {
    final service = ScheduledTaskService.instance;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('scheduled.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 460,
        height: 360,
        child: AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            final tasks = service.tasks;
            if (tasks.isEmpty) {
              return Center(
                child: Text(
                  I18n.t('scheduled.empty'),
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
                final time =
                    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                final days = t.weekdays.isEmpty
                    ? I18n.t('scheduled.every_day')
                    : t.weekdays.map((d) => '$d').join(',');
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.schedule,
                    size: 18,
                    color: t.enabled
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                  title: Text(
                    t.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '$time · $days · ${t.conversationId}',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: t.enabled,
                        activeThumbColor: AppColors.primary,
                        onChanged: (v) => service.setEnabled(t.id, v),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.redAccent,
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
        TextButton.icon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.add, size: 16),
          label: Text(I18n.t('scheduled.add')),
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

  Future<void> _add(BuildContext context) async {
    final conv = TextEditingController();
    final prompt = TextEditingController();
    final hour = TextEditingController(text: '9');
    final minute = TextEditingController(text: '0');
    final weekdays = <int>{};
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('scheduled.add'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(ctx, conv, I18n.t('scheduled.conversation_id')),
                  const SizedBox(height: 8),
                  _field(ctx, prompt, I18n.t('scheduled.prompt')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _field(ctx, hour, I18n.t('scheduled.hour')),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _field(ctx, minute, I18n.t('scheduled.minute')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text('${I18n.t('scheduled.weekday')} $d'),
                          selected: weekdays.contains(d),
                          onSelected: (v) => setLocal(() {
                            if (v) {
                              weekdays.add(d);
                            } else {
                              weekdays.remove(d);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(I18n.t('dialog.save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      final convId = conv.text.trim();
      final promptText = prompt.text.trim();
      if (convId.isNotEmpty && promptText.isNotEmpty) {
        await ScheduledTaskService.instance.add(
          conversationId: convId,
          prompt: promptText,
          hour: int.tryParse(hour.text.trim()) ?? 9,
          minute: int.tryParse(minute.text.trim()) ?? 0,
          weekdays: weekdays.toList()..sort(),
        );
      }
    }
  }

  Widget _field(
    BuildContext ctx,
    TextEditingController c,
    String label,
  ) {
    return TextField(
      controller: c,
      keyboardType: label.contains('hour') || label.contains('minute')
          ? TextInputType.number
          : TextInputType.text,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppColors.textSecondary),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary),
        ),
      ),
    );
  }
}
