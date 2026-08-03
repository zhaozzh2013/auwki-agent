import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/models/models.dart';
import 'package:auwki_agent/services/token_stats.dart';

void main() {
  test('estimateTokens：中英文混合估算', () {
    expect(estimateTokens('你好世界'), 4);
    expect(estimateTokens('hello'), 1);
    expect(estimateTokens(''), 0);
    expect(estimateTokens('a'), 1);
  });

  test('TokenStats.compute 汇总会话与每日数据', () {
    final now = DateTime.now();
    final conv = Conversation(
      id: 'c1',
      title: '测试对话',
      messages: [
        Message(
          id: 'm1',
          sender: Sender.user,
          text: '你好',
          createdAt: now,
        ),
        Message(
          id: 'm2',
          sender: Sender.assistant,
          text: 'hello world',
          createdAt: now,
        ),
        // 工具消息不应计入
        Message(
          id: 'm3',
          sender: Sender.tool,
          text: 'writefile x',
          toolName: 'writefile',
          createdAt: now,
        ),
      ],
    );

    final stats = TokenStats.compute([conv]);
    expect(stats.totalMessages, 2);
    expect(stats.totalTokens, estimateTokens('你好') + estimateTokens('hello world'));
    expect(stats.todayTokens, stats.totalTokens);
    expect(stats.daily, hasLength(7));
    expect(stats.conversations, hasLength(1));
    expect(stats.conversations.first.title, '测试对话');
  });

  test('空数据时图表与列表为空', () {
    final stats = TokenStats.compute([]);
    expect(stats.totalTokens, 0);
    expect(stats.daily, hasLength(7));
    expect(stats.conversations, isEmpty);
  });
}
