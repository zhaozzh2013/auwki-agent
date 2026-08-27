import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/agent_runtime.dart';
import '../../services/settings_store.dart';
import '../../theme.dart';
import 'audit_log_dialog.dart';
import 'custom_agents_dialog.dart';
import 'mcp_servers_dialog.dart';

/// 批次 4 设置入口：工具开关（A03）、干跑（A19）、缓存（A18）、
/// 自定义工具（A02）、权限规则（A08）。
Future<void> showAgentToolsDialog(
  BuildContext context,
  SettingsStore settings,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _AgentToolsDialog(settings: settings),
  );
}

class _AgentToolsDialog extends StatefulWidget {
  const _AgentToolsDialog({required this.settings});

  final SettingsStore settings;

  @override
  State<_AgentToolsDialog> createState() => _AgentToolsDialogState();
}

class _AgentToolsDialogState extends State<_AgentToolsDialog> {
  late final TextEditingController _ttl;

  @override
  void initState() {
    super.initState();
    _ttl = TextEditingController(
      text: '${widget.settings.toolCacheTtlSeconds}',
    );
  }

  @override
  void dispose() {
    _ttl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('agent.tools.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 460,
        child: AnimatedBuilder(
          animation: s,
          builder: (context, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(I18n.t('agent.tools.enabled')),
                for (final tool in ToolRuntime.builtInTools)
                  _switchRow(
                    label: tool,
                    value: s.toolEnabled(tool),
                    onChanged: (v) => s.setToolEnabled(tool, v),
                  ),
                for (final m in s.customTools)
                  _switchRow(
                    label: '${m['name'] ?? m['id']} (${m['id']})',
                    value: (m['enabled'] as bool?) ?? true,
                    onChanged: (v) {
                      final tools = [
                        for (final t in s.customTools)
                          t['id'] == m['id']
                              ? {...t, 'enabled': v}
                              : Map<String, dynamic>.from(t),
                      ];
                      s.setCustomTools(tools);
                    },
                  ),
                const SizedBox(height: 12),
                _switchRow(
                  label: I18n.t('agent.tools.dry_run'),
                  value: s.dryRun,
                  onChanged: (v) => s.setDryRun(v),
                ),
                _switchRow(
                  label: I18n.t('git.auto_stage'),
                  value: s.autoStage,
                  onChanged: (v) => s.setAutoStage(v),
                ),
                _switchRow(
                  label: I18n.t('git.auto_commit'),
                  value: s.autoCommit,
                  onChanged: (v) => s.setAutoCommit(v),
                ),
                _switchRow(
                  label: I18n.t('agent.tools.cache'),
                  value: s.toolCacheEnabled,
                  onChanged: (v) => s.setToolCacheEnabled(v),
                ),
                if (s.toolCacheEnabled)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 6),
                    child: TextField(
                      controller: _ttl,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: I18n.t('agent.tools.cache.ttl'),
                        labelStyle: TextStyle(color: AppColors.textSecondary),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary),
                        ),
                      ),
                      onSubmitted: (v) {
                        s.setToolCacheTtl(int.tryParse(v.trim()) ?? 600);
                      },
                    ),
                  ),
                const SizedBox(height: 14),
                _sectionTitle(I18n.t('agent.tools.custom')),
                if (s.customTools.isEmpty)
                  _muted(I18n.t('agent.tools.custom.empty')),
                for (final m in s.customTools)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.extension_outlined,
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
                      '${m['id']}',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
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
                        s.setCustomTools([
                          for (final t in s.customTools)
                            if (t['id'] != m['id'])
                              Map<String, dynamic>.from(t),
                        ]);
                      },
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _addCustomTool(s),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(I18n.t('agent.tools.custom.add')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _sectionTitle(I18n.t('agent.tools.permissions')),
                if (s.permissionRules.isEmpty)
                  _muted(I18n.t('agent.tools.permissions.empty')),
                for (final r in s.permissionRules)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      r['allow'] == false
                          ? Icons.block
                          : Icons.check_circle_outline,
                      size: 18,
                      color: r['allow'] == false
                          ? Colors.redAccent
                          : const Color(0xFF66BB6A),
                    ),
                    title: Text(
                      '${r['tool']}',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                    subtitle: Text(
                      _ruleSummary(r),
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
                        s.setPermissionRules([
                          for (final x in s.permissionRules)
                            if (x != r) Map<String, dynamic>.from(x),
                        ]);
                      },
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _addPermissionRule(s),
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(I18n.t('agent.tools.permissions.add')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => showCustomAgentsDialog(context, s),
                    icon: const Icon(Icons.person_outline, size: 16),
                    label: Text(I18n.t('agent.agents.title')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => showMcpServersDialog(context, s),
                    icon: const Icon(Icons.dns_outlined, size: 16),
                    label: Text(I18n.t('agent.mcp.title')),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => showAuditLogDialog(context),
          child: Text(
            I18n.t('agent.audit'),
            style: TextStyle(color: AppColors.primary, fontSize: 13),
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

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 4, top: 6),
    child: Text(
      t,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _muted(String t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      t,
      style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
    ),
  );

  Widget _switchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  String _ruleSummary(Map<String, dynamic> r) {
    final parts = <String>[];
    final cmdAllow = r['commandAllowPrefixes'];
    final cmdDeny = r['commandDenyPrefixes'];
    final pathAllow = r['pathAllowPrefixes'];
    final pathDeny = r['pathDenyPrefixes'];
    if (cmdAllow is List && cmdAllow.isNotEmpty) {
      parts.add('cmd allow: ${cmdAllow.join(', ')}');
    }
    if (cmdDeny is List && cmdDeny.isNotEmpty) {
      parts.add('cmd deny: ${cmdDeny.join(', ')}');
    }
    if (pathAllow is List && pathAllow.isNotEmpty) {
      parts.add('path allow: ${pathAllow.join(', ')}');
    }
    if (pathDeny is List && pathDeny.isNotEmpty) {
      parts.add('path deny: ${pathDeny.join(', ')}');
    }
    if (parts.isEmpty) {
      return r['allow'] == false
          ? I18n.t('agent.tools.permissions.deny')
          : I18n.t('agent.tools.permissions.allow');
    }
    return parts.join('; ');
  }

  Future<void> _addCustomTool(SettingsStore s) async {
    final id = TextEditingController();
    final name = TextEditingController();
    final desc = TextEditingController();
    final command = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('agent.tools.custom.add'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(ctx, id, I18n.t('agent.tools.custom.id')),
                const SizedBox(height: 8),
                _field(ctx, name, I18n.t('agent.tools.custom.name')),
                const SizedBox(height: 8),
                _field(ctx, desc, I18n.t('agent.tools.custom.desc')),
                const SizedBox(height: 8),
                _field(ctx, command, I18n.t('agent.tools.custom.command')),
                const SizedBox(height: 8),
                Text(
                  I18n.t('agent.tools.custom.hint'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
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
    );
    if (saved == true) {
      final idText = id.text.trim();
      if (idText.isNotEmpty && !ToolRuntime.builtInTools.contains(idText)) {
        s.setCustomTools([
          ...s.customTools,
          {
            'id': idText,
            'name': name.text.trim().isEmpty ? idText : name.text.trim(),
            'description': desc.text.trim(),
            'command': command.text.trim(),
            'enabled': true,
          },
        ]);
      }
    }
  }

  Future<void> _addPermissionRule(SettingsStore s) async {
    final tool = TextEditingController();
    var allow = true;
    final cmdAllow = TextEditingController();
    final cmdDeny = TextEditingController();
    final pathAllow = TextEditingController();
    final pathDeny = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('agent.tools.permissions.add'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(ctx, tool, I18n.t('agent.tools.permissions.tool')),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      ChoiceChip(
                        label: Text(I18n.t('agent.tools.permissions.allow')),
                        selected: allow,
                        onSelected: (_) => setLocal(() => allow = true),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: Text(I18n.t('agent.tools.permissions.deny')),
                        selected: !allow,
                        onSelected: (_) => setLocal(() => allow = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _multiline(
                    ctx,
                    cmdAllow,
                    I18n.t('agent.tools.permissions.cmd_allow'),
                  ),
                  const SizedBox(height: 8),
                  _multiline(
                    ctx,
                    cmdDeny,
                    I18n.t('agent.tools.permissions.cmd_deny'),
                  ),
                  const SizedBox(height: 8),
                  _multiline(
                    ctx,
                    pathAllow,
                    I18n.t('agent.tools.permissions.path_allow'),
                  ),
                  const SizedBox(height: 8),
                  _multiline(
                    ctx,
                    pathDeny,
                    I18n.t('agent.tools.permissions.path_deny'),
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
      List<String> lines(TextEditingController c) => c.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      s.setPermissionRules([
        ...s.permissionRules,
        {
          'tool': tool.text.trim().isEmpty ? '*' : tool.text.trim(),
          'allow': allow,
          'commandAllowPrefixes': lines(cmdAllow),
          'commandDenyPrefixes': lines(cmdDeny),
          'pathAllowPrefixes': lines(pathAllow),
          'pathDenyPrefixes': lines(pathDeny),
        },
      ]);
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

  Widget _multiline(
    BuildContext ctx,
    TextEditingController c,
    String label,
  ) {
    return TextField(
      controller: c,
      minLines: 1,
      maxLines: 3,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
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
