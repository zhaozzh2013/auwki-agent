import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/settings_store.dart';
import '../../theme.dart';

/// MCP 服务器管理（A01）。
Future<void> showMcpServersDialog(
  BuildContext context,
  SettingsStore settings,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _McpServersDialog(settings: settings),
  );
}

class _McpServersDialog extends StatelessWidget {
  const _McpServersDialog({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('agent.mcp.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 460,
        height: 360,
        child: AnimatedBuilder(
          animation: settings,
          builder: (context, _) {
            final servers = settings.mcpServers;
            if (servers.isEmpty) {
              return Center(
                child: Text(
                  I18n.t('agent.mcp.empty'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: servers.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final m = servers[i];
                final enabled = (m['enabled'] as bool?) ?? true;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.dns_outlined,
                    size: 18,
                    color: enabled
                        ? AppColors.primary
                        : AppColors.textTertiary,
                  ),
                  title: Text(
                    '${m['name'] ?? m['id']}',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: Text(
                    '${m['command'] ?? ''} ${(m['args'] as List?)?.join(' ') ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: enabled,
                        activeThumbColor: AppColors.primary,
                        onChanged: (v) {
                          settings.setMcpServers([
                            for (final s in settings.mcpServers)
                              s['id'] == m['id']
                                  ? {...s, 'enabled': v}
                                  : Map<String, dynamic>.from(s),
                          ]);
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        onPressed: () {
                          settings.setMcpServers([
                            for (final s in settings.mcpServers)
                              if (s['id'] != m['id'])
                                Map<String, dynamic>.from(s),
                          ]);
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
          onPressed: () => _add(context),
          icon: const Icon(Icons.add, size: 16),
          label: Text(I18n.t('agent.mcp.add')),
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
    final command = TextEditingController();
    final args = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('agent.mcp.add'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(ctx, id, I18n.t('agent.mcp.id')),
              const SizedBox(height: 8),
              _field(ctx, name, I18n.t('agent.mcp.name')),
              const SizedBox(height: 8),
              _field(ctx, command, I18n.t('agent.mcp.command')),
              const SizedBox(height: 8),
              _field(ctx, args, I18n.t('agent.mcp.args')),
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
      if (idText.isNotEmpty && command.text.trim().isNotEmpty) {
        settings.setMcpServers([
          ...settings.mcpServers,
          {
            'id': idText,
            'name': name.text.trim().isEmpty ? idText : name.text.trim(),
            'command': command.text.trim(),
            'args': args.text
                .trim()
                .split(RegExp(r'\s+'))
                .where((e) => e.isNotEmpty)
                .toList(),
            'enabled': true,
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
