import 'settings_store.dart';
import 'token_stats.dart';

/// Token 节省引擎：按成本模式压缩上下文、工具结果与轮次。
///
/// 所有预算都是“估算 token”，实际按供应商计费口径会略有出入，
/// 但压缩策略本身不依赖精确计数。
class TokenSaver {
  TokenSaver._();

  /// 发送给模型的对话历史 token 预算（估算值）。
  static int historyBudgetTokens(CostMode mode) => switch (mode) {
    CostMode.poor => 6000,
    CostMode.medium => 14000,
    CostMode.max => 26000,
  };

  /// 单条工具结果回填给模型的最大字符数。
  static int toolResultMaxChars(CostMode mode) => switch (mode) {
    CostMode.poor => 900,
    CostMode.medium => 2200,
    CostMode.max => 4800,
  };

  /// 单轮对话允许的工具轮次数（最终收尾另算）。
  static int maxTurns(CostMode mode) => switch (mode) {
    CostMode.poor => 2,
    CostMode.medium => 3,
    CostMode.max => 4,
  };

  /// 注入系统提示词的记忆最大字符数。
  static int maxMemoryChars(CostMode mode) => switch (mode) {
    CostMode.poor => 300,
    CostMode.medium => 600,
    CostMode.max => 1000,
  };

  /// 估算一组消息的总 token。
  static int tokensOf(List<Map<String, dynamic>> messages) =>
      messages.fold(
        0,
        (sum, m) => sum + estimateTokens((m['content'] as String?) ?? ''),
      );

  /// 长文本保留头尾，中间省略，避免模型丢失关键上下文。
  static String compactText(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final head = text.substring(0, (maxChars * 0.6).round());
    final tail = text.substring(text.length - (maxChars * 0.25).round());
    final omitted = text.length - head.length - tail.length;
    return '$head\n...[$omitted chars omitted]...\n$tail';
  }

  /// 压缩工具结果（用于回填给模型的 user 消息）。
  static String compactToolResult(String text, CostMode mode) =>
      compactText(text, toolResultMaxChars(mode));

  /// 按 token 预算裁剪对话历史：
  /// 1. 先压缩超长单条消息；
  /// 2. 从最新消息往旧消息保留，直到预算用尽；
  /// 3. 用 [summaryNote]（通常是对话摘要或省略提示）替代被丢弃的旧消息。
  static List<Map<String, dynamic>> trimHistory(
    List<Map<String, dynamic>> history,
    CostMode mode, {
    String? summaryNote,
  }) {
    if (history.isEmpty) return history;
    final budget = historyBudgetTokens(mode);
    if (tokensOf(history) <= budget) return history;

    final perMessageMax = (budget / 3).ceil();
    final compressed = <Map<String, dynamic>>[];
    for (final m in history) {
      final content = (m['content'] as String?) ?? '';
      final c = content.length > perMessageMax
          ? compactText(content, perMessageMax)
          : content;
      compressed.add({'role': m['role'], 'content': c});
    }

    final kept = <Map<String, dynamic>>[];
    var keptTokens = 0;
    for (final m in compressed.reversed) {
      final t = estimateTokens((m['content'] as String?) ?? '');
      if (keptTokens + t > budget && kept.isNotEmpty) break;
      kept.add(m);
      keptTokens += t;
    }
    final result = kept.reversed.toList();
    final note = (summaryNote == null || summaryNote.trim().isEmpty)
        ? '[earlier messages omitted]'
        : summaryNote.trim();
    if (result.isEmpty) {
      return [
        {'role': 'user', 'content': note},
        ...history.reversed.take(1).toList().reversed,
      ];
    }
    return [{'role': 'user', 'content': note}, ...result];
  }
}
