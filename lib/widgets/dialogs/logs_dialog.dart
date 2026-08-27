import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/log_service.dart';
import '../../theme.dart';

/// 日志查看器（E02）：展示最近日志，支持过滤、导出与打开目录。
class LogsDialog extends StatefulWidget {
  const LogsDialog({super.key});

  @override
  State<LogsDialog> createState() => _LogsDialogState();
}

class _LogsDialogState extends State<LogsDialog> {
  List<String> _logs = const [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logs = await LogService.tail(lines: 1000);
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  List<String> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _logs;
    return _logs.where((l) => l.toLowerCase().contains(q)).toList();
  }

  Future<void> _export() async {
    final path = await FilePicker.saveFile(
      dialogTitle: I18n.t('logs.export'),
      fileName: 'auwki-logs-${DateTime.now().millisecondsSinceEpoch}.log',
      type: FileType.any,
    );
    if (path == null || path.isEmpty) return;
    try {
      await LogService.exportTo(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              I18n.t('logs.export.done', {'path': path}),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: AppColors.surfaceAlt,
          ),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(I18n.t('logs.export.failed')),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
  }

  Future<void> _openFolder() async {
    final path = await LogService.logFilePath();
    if (path == null) return;
    try {
      _openPath(path);
    } catch (_) {}
  }

  void _openPath(String filePath) {
    if (Platform.isWindows) {
      Process.start('explorer', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      Process.start('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      Process.start('xdg-open', [File(filePath).parent.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      title: Row(
        children: [
          Icon(Icons.terminal, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            I18n.t('logs.title'),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: I18n.t('logs.filter_hint'),
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: I18n.t('logs.refresh'),
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 17),
                  color: AppColors.textSecondary,
                ),
                IconButton(
                  tooltip: I18n.t('logs.export'),
                  onPressed: _export,
                  icon: const Icon(Icons.save_alt, size: 17),
                  color: AppColors.textSecondary,
                ),
                IconButton(
                  tooltip: I18n.t('logs.open_folder'),
                  onPressed: _openFolder,
                  icon: const Icon(Icons.folder_open, size: 17),
                  color: AppColors.textSecondary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        I18n.t('logs.empty'),
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 3,
                          ),
                          child: SelectableText(
                            filtered[i],
                            style: TextStyle(
                              color: _lineColor(filtered[i]),
                              fontSize: 11,
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
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

  Color _lineColor(String line) {
    if (line.contains('[FLUTTER]') || line.contains('[ASYNC]')) {
      return Colors.redAccent;
    }
    if (line.contains('[TIMING]')) return AppColors.planAccent;
    return AppColors.textPrimary;
  }
}
