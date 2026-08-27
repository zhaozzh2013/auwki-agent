import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/audit_service.dart';
import '../../theme.dart';

/// 审计日志查看器（A14）：最近记录、导出、清空。
Future<void> showAuditLogDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _AuditLogDialog(),
  );
}

class _AuditLogDialog extends StatefulWidget {
  const _AuditLogDialog();

  @override
  State<_AuditLogDialog> createState() => _AuditLogDialogState();
}

class _AuditLogDialogState extends State<_AuditLogDialog> {
  late Future<List<AuditRecord>> _future;

  @override
  void initState() {
    super.initState();
    _future = AuditService.instance.recent(limit: 200);
  }

  void _reload() {
    setState(() => _future = AuditService.instance.recent(limit: 200));
  }

  Future<void> _export() async {
    final path = await FilePicker.saveFile(
      dialogTitle: I18n.t('agent.audit.export'),
      fileName: 'auwki-audit-${DateTime.now().millisecondsSinceEpoch}.jsonl',
      type: FileType.custom,
      allowedExtensions: const ['jsonl'],
    );
    if (path == null || path.isEmpty) return;
    try {
      await AuditService.instance.exportTo(path);
      if (!mounted) return;
      _snack(I18n.t('agent.audit.exported', {'path': path}));
    } catch (e) {
      if (!mounted) return;
      _snack('$e', error: true);
    }
  }

  Future<void> _clear() async {
    await AuditService.instance.clear();
    _reload();
    if (mounted) _snack(I18n.t('agent.audit.cleared'));
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontSize: 12)),
          backgroundColor: error
              ? Colors.redAccent.shade700
              : AppColors.surfaceAlt,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('agent.audit'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 520,
        height: 420,
        child: FutureBuilder<List<AuditRecord>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final records = snap.data ?? const <AuditRecord>[];
            if (records.isEmpty) {
              return Center(
                child: Text(
                  I18n.t('agent.audit.empty'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12.5,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: AppColors.border),
              itemBuilder: (context, i) {
                final r = records[i];
                final time = r.time.toLocal();
                String two(int v) => v.toString().padLeft(2, '0');
                final stamp =
                    '${time.year}-${two(time.month)}-${two(time.day)} '
                    '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
                final color = r.denied
                    ? Colors.redAccent
                    : r.dryRun
                    ? Colors.orangeAccent
                    : r.ok
                    ? const Color(0xFF66BB6A)
                    : Colors.redAccent;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${r.tool}(${r.args})',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          Text(
                            stamp,
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                      if (r.dryRun || r.denied)
                        Padding(
                          padding: const EdgeInsets.only(left: 13, top: 2),
                          child: Text(
                            r.denied
                                ? I18n.t('agent.audit.denied')
                                : I18n.t('agent.audit.dry'),
                            style: TextStyle(
                              color: r.denied
                                  ? Colors.redAccent
                                  : Colors.orangeAccent,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
          onPressed: _export,
          icon: const Icon(Icons.file_download_outlined, size: 16),
          label: Text(I18n.t('agent.audit.export')),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(fontSize: 12.5),
          ),
        ),
        TextButton.icon(
          onPressed: _clear,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: Text(I18n.t('agent.audit.clear')),
          style: TextButton.styleFrom(
            foregroundColor: Colors.redAccent,
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
