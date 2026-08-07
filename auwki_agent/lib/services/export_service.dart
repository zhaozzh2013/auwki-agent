import '../i18n/strings.dart';
import '../models/models.dart';

/// 把一条对话导出为 Markdown。
class ExportService {
  ExportService._();

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

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
