import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../models/models.dart';
import '../theme.dart';

/// 把一条对话导出为 Markdown。
class ExportService {
  ExportService._();

  /// 弹出保存对话框导出对话为 Markdown，并提示结果。
  static Future<void> exportConversation(
    BuildContext context,
    Conversation conv,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final md = conversationToMarkdown(conv);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}';
    final safeTitle = conv.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: I18n.t('conv.export'),
        fileName: 'AUWKI-$safeTitle-$stamp.md',
        type: FileType.custom,
        allowedExtensions: ['md'],
        bytes: utf8.encode(md),
      );
      if (path != null && path.isNotEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                I18n.t('conv.export.done', {'path': path}),
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: AppColors.surfaceAlt,
            ),
          );
      }
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(I18n.t('conv.export.failed')),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
  }

  /// 导出对话为 JSONL（F03）。
  static Future<void> exportConversationJsonl(
    BuildContext context,
    Conversation conv,
  ) =>
      _saveWith(context, conv, 'jsonl', conversationToJsonl, ['jsonl']);

  /// 导出对话为 HTML（F03）。
  static Future<void> exportConversationHtml(
    BuildContext context,
    Conversation conv,
  ) =>
      _saveWith(context, conv, 'html', conversationToHtml, ['html']);

  static Future<void> _saveWith(
    BuildContext context,
    Conversation conv,
    String ext,
    String Function(Conversation) builder,
    List<String> allowed,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}';
    final safeTitle = conv.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: I18n.t('conv.export'),
        fileName: 'AUWKI-$safeTitle-$stamp.$ext',
        type: FileType.custom,
        allowedExtensions: allowed,
        bytes: utf8.encode(builder(conv)),
      );
      if (path != null && path.isNotEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                I18n.t('conv.export.done', {'path': path}),
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: AppColors.surfaceAlt,
            ),
          );
      }
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(I18n.t('conv.export.failed')),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
  }

  static String conversationToMarkdown(Conversation conv) {
    final buf = StringBuffer();
    buf.writeln('# ${conv.title}');
    buf.writeln();
    buf.writeln(
      '> ${I18n.t('export.time', {'time': _formatTime(conv.updatedAt)})}',
    );
    buf.writeln();

    for (final m in conv.messages) {
      buf.writeln();
      switch (m.sender) {
        case Sender.user:
          buf.writeln('## ${I18n.t('chat.you')}');
        case Sender.assistant:
          buf.writeln('## ${I18n.t('chat.assistant')}');
        case Sender.tool:
          final name = _toolLabel(m.toolName);
          buf.writeln('## 🔧 $name');
          if (m.toolArgs != null && m.toolArgs!.trim().isNotEmpty) {
            buf.writeln();
            buf.writeln('> ${m.toolArgs}');
          }
        case Sender.system:
          buf.writeln('## System');
      }
      if (m.attachments.isNotEmpty) {
        buf.writeln();
        for (final a in m.attachments) {
          buf.writeln('📎 ${a.name}');
        }
      }
      if (m.text.trim().isNotEmpty) {
        buf.writeln();
        buf.writeln(m.text.trim());
      }
      if (m.toolResult != null && m.toolResult!.trim().isNotEmpty) {
        buf.writeln();
        buf.writeln('```');
        buf.writeln(m.toolResult);
        buf.writeln('```');
      }
    }
    return buf.toString().trim();
  }

  static String _toolLabel(String? name) {
    switch (name) {
      case 'agent.prometheus':
        return 'Prometheus';
      case 'agent.metis':
        return 'Metis';
      case 'agent.oracle':
        return 'Oracle';
      case 'webfetch':
        return I18n.t('tool.webfetch');
      case 'websearch':
        return I18n.t('tool.websearch');
      case 'listfiles':
        return I18n.t('tool.listfiles');
      case 'readfile':
        return I18n.t('tool.readfile');
      case 'writefile':
        return I18n.t('tool.writefile');
      case 'replacefile':
        return I18n.t('tool.replacefile');
      case 'command':
        return I18n.t('tool.command');
      case 'round_summary':
        return I18n.t('tool.round_summary');
      default:
        return name ?? I18n.t('tool.generic');
    }
  }

  /// 导出为 JSONL（F03）：每条消息一行 JSON。
  static String conversationToJsonl(Conversation conv) {
    final buf = StringBuffer();
    for (final m in conv.messages) {
      buf.writeln(
        jsonEncode({
          'id': m.id,
          'sender': m.sender.name,
          'text': m.text,
          'toolName': m.toolName,
          'toolArgs': m.toolArgs,
          'toolResult': m.toolResult,
          'toolOk': m.toolOk,
          'createdAt': m.createdAt.toIso8601String(),
        }),
      );
    }
    return buf.toString().trim();
  }

  /// 导出为 HTML（F03）：自包含样式页面，便于分享与归档。
  static String conversationToHtml(Conversation conv) {
    final buf = StringBuffer()
      ..writeln('<!DOCTYPE html>')
      ..writeln('<html lang="zh">')
      ..writeln('<head>')
      ..writeln('<meta charset="utf-8">')
      ..writeln('<title>${_escapeHtml(conv.title)}</title>')
      ..writeln('<style>')
      ..writeln(
        'body{font-family:system-ui,sans-serif;max-width:860px;margin:32px auto;padding:0 20px;'
        'background:#f6f7f9;color:#1c2026;line-height:1.6}',
      )
      ..writeln(
        'h1{font-size:22px}h2{font-size:14px;color:#5d6570;font-weight:600}',
      )
      ..writeln(
        '.msg{margin:14px 0;padding:12px 14px;border-radius:12px;background:#fff;'
        'border:1px solid #e2e6ec;box-shadow:0 1px 3px rgba(0,0,0,.05)}',
      )
      ..writeln(
        '.meta{font-size:11px;color:#96a0ac;margin-bottom:6px}',
      )
      ..writeln(
        '.tool{background:#f0f2f5;font-family:monospace;font-size:12px;'
        'white-space:pre-wrap;border-radius:8px;padding:8px;margin-top:8px}',
      )
      ..writeln('code{background:#eaedf2;padding:1px 5px;border-radius:4px}')
      ..writeln('pre{background:#f4f5f7;padding:12px;border-radius:8px;overflow-x:auto}')
      ..writeln('blockquote{border-left:3px solid #2f6bed;margin:8px 0;padding-left:10px}')
      ..writeln('table{border-collapse:collapse}td,th{border:1px solid #e2e6ec;padding:6px 10px}')
      ..writeln('</style>')
      ..writeln('</head>')
      ..writeln('<body>')
      ..writeln('<h1>${_escapeHtml(conv.title)}</h1>')
      ..writeln('<h2>${I18n.t('export.time', {'time': _formatTime(conv.updatedAt)})}</h2>');
    for (final m in conv.messages) {
      buf.writeln('<div class="msg">');
      final label = switch (m.sender) {
        Sender.user => I18n.t('chat.you'),
        Sender.assistant => I18n.t('chat.assistant'),
        Sender.tool => '🔧 ${_toolLabel(m.toolName)}',
        Sender.system => 'System',
      };
      buf.writeln(
        '<div class="meta">$label · ${_formatTime(m.createdAt)}</div>',
      );
      if (m.text.trim().isNotEmpty) {
        buf.writeln(_markdownToHtml(m.text));
      }
      if (m.toolResult != null && m.toolResult!.trim().isNotEmpty) {
        buf.writeln(
          '<div class="tool">${_escapeHtml(m.toolResult!)}</div>',
        );
      }
      buf.writeln('</div>');
    }
    buf
      ..writeln('</body>')
      ..writeln('</html>');
    return buf.toString();
  }

  /// 极简 Markdown → HTML（标题/代码/引用/列表/表格），用于导出。
  static String _markdownToHtml(String md) {
    final lines = md.split('\n');
    final out = StringBuffer();
    var inCode = false;
    var inQuote = false;
    for (final line in lines) {
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          out.writeln('</pre>');
          inCode = false;
        } else {
          out.writeln('<pre>');
          inCode = true;
        }
        continue;
      }
      if (inCode) {
        out.writeln(_escapeHtml(line));
        continue;
      }
      final t = line.trim();
      if (t.startsWith('#')) {
        var level = 0;
        while (level < t.length && t[level] == '#') {
          level++;
        }
        level = level.clamp(1, 3);
        out.writeln(
          '<h$level>${_escapeHtml(t.substring(level).trim())}</h$level>',
        );
        continue;
      }
      if (t.startsWith('>')) {
        if (!inQuote) {
          out.writeln('<blockquote>');
          inQuote = true;
        }
        out.writeln(_escapeHtml(t.substring(1).trim()));
        continue;
      }
      if (inQuote) {
        out.writeln('</blockquote>');
        inQuote = false;
      }
      if (t.isEmpty) {
        out.writeln('<br>');
        continue;
      }
      out.writeln('<p>${_inlineHtml(_escapeHtml(line))}</p>');
    }
    if (inQuote) out.writeln('</blockquote>');
    if (inCode) out.writeln('</pre>');
    return out.toString();
  }

  static String _inlineHtml(String escaped) {
    return escaped
        .replaceAllMapped(
          RegExp(r'`([^`]+)`'),
          (m) => '<code>${m.group(1)}</code>',
        )
        .replaceAllMapped(
          RegExp(r'\*\*([^*]+)\*\*'),
          (m) => '<strong>${m.group(1)}</strong>',
        );
  }

  static String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
