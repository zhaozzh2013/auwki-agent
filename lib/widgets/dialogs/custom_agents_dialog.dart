import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/settings_store.dart';
import '../../theme.dart';

/// 自定义子代理管理（A16）。
Future<void> showCustomAgentsDialog(
  BuildContext context,
  SettingsStore settings,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CustomAgentsDialog(settings: settings),
  );
}

class _CustomAgentsDialog extends StatelessWidget {
  const _CustomAgentsDialog({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('agent.agents.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        height: 360,
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) {
            final list = settings.customAgents;
            if (list.isEmpty) {
              return Center(
                child: Text(
                  I18n.t('agent.agents.empty'),
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
                final m = list[i];
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.person_outline,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    '${m['name'] ?? m['id']}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${m['id']}\n${m['instruction'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
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
                      settings.setCustomAgents([
                        for (final a in settings.customAgents)
                          if (a['id'] != m['id'])
                            Map<String, dynamic>.from(a),
                      ]);
                    },
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
          label: Text(I18n.t('agent.agents.add')),
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
    final id = TextEditingController();
    final name = TextEditingController();
    final instruction = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('agent.agents.add'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(ctx, id, I18n.t('agent.agents.id')),
              const SizedBox(height: 8),
              _field(ctx, name, I18n.t('agent.agents.name')),
              const SizedBox(height: 8),
              _field(ctx, instruction, I18n.t('agent.agents.instruction')),
            ],
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
    );
    if (saved == true) {
      final idText = id.text.trim();
      if (idText.isNotEmpty) {
        settings.setCustomAgents([
          ...settings.customAgents,
          {
            'id': idText,
            'name': name.text.trim().isEmpty ? idText : name.text.trim(),
            'instruction': instruction.text.trim(),
          },
        ]);
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
