import '../models/models.dart';

/// 单条文本的 token 估算（中文约 1 字 ≈ 1 token，英文约 4 字符 ≈ 1 token）。
int estimateTokens(String text) {
  if (text.isEmpty) return 0;
  var cjk = 0;
  var other = 0;
  for (final rune in text.runes) {
    if ((rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF)) {
      cjk++;
    } else {
      other++;
    }
  }
  return (cjk + other / 4).round().clamp(1, 1 << 30);
}

/// 常用模型的每百万 token 输入价格（美元，近似值，G04 成本估算）。
/// 未命中的模型回退到 [_fallbackCostPer1m]。
double costUsdPer1mInput(String modelId) {
  final m = modelId.toLowerCase();
  if (m.contains('opus')) return 15.0;
  if (m.contains('sonnet')) return 3.0;
  if (m.contains('haiku')) return 0.8;
  if (m.contains('gpt-4o') && m.contains('mini')) return 0.15;
  if (m.contains('gpt-4o')) return 2.5;
  if (m.contains('o1-mini')) return 1.1;
  if (m.contains('deepseek') && m.contains('flash')) return 0.07;
  if (m.contains('deepseek')) return 0.27;
  if (m.contains('minimax-m3')) return 0.8;
  if (m.contains('minimax')) return 0.3;
  return 0.5;
}

/// 按输入价格估算成本（输出按 2.5 倍计，忽略方向时的粗略近似）。
double estimateCostUsd(int tokens, String modelId) {
  final input = costUsdPer1mInput(modelId);
  final avg = input * 1.75;
  return tokens / 1000000 * avg;
}

class ConversationTokenStat {
  ConversationTokenStat({
    required this.conversationId,
    required this.title,
    required this.tokens,
    required this.messages,
  });

  final String conversationId;
  final String title;
  final int tokens;
  final int messages;
}

class TokenStats {
  TokenStats({
    required this.totalMessages,
    required this.totalTokens,
    required this.todayTokens,
    required this.daily,
    required this.conversations,
  });

  final int totalMessages;
  final int totalTokens;
  final int todayTokens;

  /// 估算成本（美元，G04）。
  double get estimatedCostUsd => estimateCostUsd(totalTokens, 'global');

  /// 最近 7 天：日期字符串 -> token 数。
  final List<MapEntry<DateTime, int>> daily;

  final List<ConversationTokenStat> conversations;

  static TokenStats compute(List<Conversation> conversations) {
    var totalMessages = 0;
    var totalTokens = 0;
    final today = DateTime.now();
    final todayKey = _dayKey(today);
    var todayTokens = 0;
    final byDay = <String, int>{};
    final byConv = <String, ({String title, int tokens, int messages})>{};

    for (final conv in conversations) {
      for (final m in conv.messages) {
        if (m.sender == Sender.system || m.sender == Sender.tool) continue;
        final tokens = estimateTokens(m.text);
        totalMessages++;
        totalTokens += tokens;
        final day = _dayKey(m.createdAt);
        byDay[day] = (byDay[day] ?? 0) + tokens;
        if (day == todayKey) todayTokens += tokens;

        final cur = byConv[conv.id] ??
            (title: conv.title, tokens: 0, messages: 0);
        byConv[conv.id] = (
          title: cur.title,
          tokens: cur.tokens + tokens,
          messages: cur.messages + 1,
        );
      }
    }

    final daily = <MapEntry<DateTime, int>>[];
    for (var i = 6; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      daily.add(
        MapEntry(
          DateTime(day.year, day.month, day.day),
          byDay[_dayKey(day)] ?? 0,
        ),
      );
    }

    final conversationsStat = byConv.entries
        .map(
          (e) => ConversationTokenStat(
            conversationId: e.key,
            title: e.value.title,
            tokens: e.value.tokens,
            messages: e.value.messages,
          ),
        )
        .toList()
      ..sort((a, b) => b.tokens.compareTo(a.tokens));

    return TokenStats(
      totalMessages: totalMessages,
      totalTokens: totalTokens,
      todayTokens: todayTokens,
      daily: daily,
      conversations: conversationsStat,
    );
  }

  static String _dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}
