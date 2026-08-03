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
