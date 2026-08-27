import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../models/models.dart';
import '../../services/settings_store.dart';
import '../../state/chat_store.dart';
import '../../theme.dart';

/// 从备份 JSON 恢复（F08 恢复向导）。
/// 支持 AUWKI 备份（{chats, settings}）与裸 chats.json 两种格式。
/// [settings]/[store] 由调用方显式传入：对话框运行在根 Overlay 之上。
class RestoreDialog extends StatefulWidget {
  const RestoreDialog({
    super.key,
    required this.settings,
    required this.store,
  });

  final SettingsStore settings;
  final ChatStore store;

  @override
  State<RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<RestoreDialog> {
  Map<String, dynamic>? _chats;
  Map<String, dynamic>? _settings;
  int _convCount = 0;
  int _msgCount = 0;
  String? _error;
  bool _busy = false;

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      dialogTitle: I18n.t('restore.title'),
    );
    if (res == null || res.files.isEmpty) return;
    final path = res.files.first.path;
    if (path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _chats = null;
      _settings = null;
      _convCount = 0;
      _msgCount = 0;
    });
    try {
      final raw = jsonDecode(await File(path).readAsString());
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : throw FormatException('not a json object');
      final chats = map['chats'];
      final settings = map['settings'];
      Map<String, dynamic> chatsMap;
      if (chats is Map) {
        chatsMap = Map<String, dynamic>.from(chats);
        _settings = settings is Map
            ? Map<String, dynamic>.from(settings)
            : null;
      } else if (map.containsKey('conversations')) {
        chatsMap = map;
      } else {
        throw FormatException('no conversations found');
      }
      final conversations = ((chatsMap['conversations'] as List?) ?? const [])
          .whereType<Map>()
          .toList();
      if (conversations.isEmpty) {
        throw FormatException('no conversations found');
      }
      var msgCount = 0;
      for (final c in conversations) {
        msgCount += ((c['messages'] as List?) ?? const []).length;
      }
      if (!mounted) return;
      setState(() {
        _chats = chatsMap;
        _convCount = conversations.length;
        _msgCount = msgCount;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _restore() async {
    final chats = _chats;
    if (chats == null || _busy) return;
    final settings = widget.settings;
    final store = widget.store;
    setState(() => _busy = true);
    try {
      if (_settings != null) {
        await settings.restoreFrom(_settings!);
      }
      final conversations = ((chats['conversations'] as List?) ?? const [])
          .whereType<Map>()
          .map((c) => Conversation.fromJson(Map<String, dynamic>.from(c)))
          .toList();
      final folders = ((chats['folders'] as List?) ?? const [])
          .whereType<Map>()
          .map((f) => Folder.fromJson(Map<String, dynamic>.from(f)))
          .toList();
      store.restoreAll(
        conversations: conversations,
        folders: folders,
        activeId: chats['activeId']?.toString(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              I18n.t('restore.done', {'count': '${conversations.length}'}),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: AppColors.surfaceAlt,
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _chats != null;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      title: Text(
        I18n.t('restore.title'),
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              I18n.t('restore.body'),
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pick,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(
                _chats == null ? I18n.t('restore.pick') : I18n.t('restore.pick_again'),
                style: const TextStyle(fontSize: 12.5),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.border),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                '${I18n.t('restore.error')} $_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
            if (hasData) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(I18n.t('restore.preview.chats'), '$_convCount'),
                    _row(I18n.t('restore.preview.messages'), '$_msgCount'),
                    if (_settings != null)
                      _row(I18n.t('restore.preview.settings'), I18n.t('restore.preview.yes')),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                I18n.t('restore.warning'),
                style: TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            I18n.t('dialog.cancel'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        if (hasData)
          FilledButton(
            onPressed: _busy ? null : _restore,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Text(I18n.t('restore.confirm')),
          ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
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
}

/// 导入历史对话（F02）：按 id 合并，不覆盖已有数据。
Future<void> importConversationsDialog(
  BuildContext context,
  ChatStore store,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final res = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['json'],
    dialogTitle: I18n.t('import.title'),
  );
  if (res == null || res.files.isEmpty) return;
  final path = res.files.first.path;
  if (path == null) return;
  try {
    final raw = jsonDecode(await File(path).readAsString());
    final map = raw is Map
        ? Map<String, dynamic>.from(raw)
        : throw FormatException('not a json object');
    final chats = map['chats'];
    final chatsMap = chats is Map
        ? Map<String, dynamic>.from(chats)
        : map.containsKey('conversations')
            ? map
            : throw FormatException('no conversations found');
    final conversations = ((chatsMap['conversations'] as List?) ?? const [])
        .whereType<Map>()
        .map((c) => Conversation.fromJson(Map<String, dynamic>.from(c)))
        .toList();
    final added = store.importConversations(conversations);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            I18n.t('import.done', {
              'added': '$added',
              'total': '${conversations.length}',
            }),
            style: const TextStyle(fontSize: 12),
          ),
          backgroundColor: AppColors.surfaceAlt,
        ),
      );
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            '${I18n.t('import.failed')} $e',
            style: const TextStyle(fontSize: 12),
          ),
          backgroundColor: Colors.redAccent.shade700,
        ),
      );
  }
}
