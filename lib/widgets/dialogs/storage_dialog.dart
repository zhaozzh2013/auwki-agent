import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/storage_manager.dart';
import '../../theme.dart';

/// 存储管理（F07）：占用统计与清理。
class StorageDialog extends StatefulWidget {
  const StorageDialog({super.key});

  @override
  State<StorageDialog> createState() => _StorageDialogState();
}

class _StorageDialogState extends State<StorageDialog> {
  StorageUsage? _usage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    final usage = await StorageManager.collect();
    if (!mounted) return;
    setState(() {
      _usage = usage;
      _busy = false;
    });
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

  Future<void> _pruneBackups() async {
    setState(() => _busy = true);
    final removed = await StorageManager.pruneBackups(keep: 20);
    _snack(I18n.t('storage.backups_pruned', {'count': '$removed'}));
    await _refresh();
  }

  Future<void> _clearLogs() async {
    setState(() => _busy = true);
    final freed = await StorageManager.clearLogs();
    _snack(I18n.t('storage.logs_cleared', {'size': _fmt(freed)}));
    await _refresh();
  }

  Future<void> _removeEmptyWorkspaces() async {
    setState(() => _busy = true);
    final removed = await StorageManager.removeEmptyWorkspaces();
    _snack(I18n.t('storage.workspaces_cleaned', {'count': '$removed'}));
    await _refresh();
  }

  Future<void> _openDataDir() async {
    final path = await StorageManager.appSupportPath();
    if (path.isEmpty) return;
    try {
      if (Platform.isWindows) {
        Process.start('explorer', [path]);
      } else if (Platform.isMacOS) {
        Process.start('open', [path]);
      } else if (Platform.isLinux) {
        Process.start('xdg-open', [path]);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final u = _usage;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      title: Row(
        children: [
          Icon(Icons.storage_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            I18n.t('storage.title'),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: I18n.t('filetree.refresh'),
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh, size: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: u == null
            ? const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _row(
                    I18n.t('storage.total'),
                    u.fmtTotal,
                    bold: true,
                  ),
                  _row(I18n.t('storage.chats'), _fmt(u.chatsDbBytes)),
                  _row(
                    I18n.t('storage.backups', {'count': '${u.backupCount}'}),
                    _fmt(u.backupsBytes),
                  ),
                  _row(I18n.t('storage.logs'), _fmt(u.logsBytes)),
                  _row(I18n.t('storage.workspaces'), _fmt(u.workspacesBytes)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _action(
                        Icons.backup_outlined,
                        I18n.t('storage.prune_backups'),
                        _pruneBackups,
                      ),
                      _action(
                        Icons.cleaning_services_outlined,
                        I18n.t('storage.clear_logs'),
                        _clearLogs,
                      ),
                      _action(
                        Icons.folder_off_outlined,
                        I18n.t('storage.clean_workspaces'),
                        _removeEmptyWorkspaces,
                      ),
                      _action(
                        Icons.folder_open,
                        I18n.t('storage.open_data_dir'),
                        _openDataDir,
                      ),
                    ],
                  ),
                ],
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

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (n >= 1024 * 1024) return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (n >= 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '$n B';
  }
}
