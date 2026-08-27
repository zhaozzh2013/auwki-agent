import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/deep_research.dart';

Stream<String> _s(String text) => Stream.fromIterable([text]);

void main() {
  final svc = DeepResearchService.instance;

  test('parseQuestions 解析 JSON 数组', () {
    final qs = svc.parseQuestions('["q1", "q2", "q3"]');
    expect(qs, ['q1', 'q2', 'q3']);
  });

  test('parseQuestions 解析序号列表与多余内容', () {
    final qs = svc.parseQuestions(
      '好的，我拆解如下：\n1. 概述\n2. 关键技术\n3. 现状\n4. 挑战',
    );
    expect(qs, hasLength(4));
    expect(qs.first, '概述');
  });

  test('parseQuestions 空输入回退为空', () {
    expect(svc.parseQuestions('无法回答'), isEmpty);
  });

  test('extractUrls 去重并限制数量', () {
    final urls = svc.extractUrls([
      '结果1: https://a.com/x 和 https://a.com/x 重复',
      '结果2: https://b.com, https://c.com',
    ], maxCount: 10);
    expect(urls, ['https://a.com/x', 'https://b.com', 'https://c.com']);
  });

  test('needsFollowUp 判定空/无结果/过短结果', () {
    expect(svc.needsFollowUp(''), isTrue);
    expect(svc.needsFollowUp('没有结果'), isTrue);
    expect(svc.needsFollowUp('short'), isTrue);
    expect(svc.needsFollowUp('这是一段足够长的搜索结果内容，包含了关键信息、背景资料与多个可用来源，可以放心使用。'), isFalse);
  });

  test('research 全流程：拆解→并行搜索→报告与来源', () async {
    final searched = <String>[];
    var chatCalls = 0;
    Stream<String> chat(String system, List<Map<String, dynamic>> history) {
      chatCalls++;
      if (chatCalls == 1) {
        // 拆解阶段
        return _s('["q1", "q2"]');
      }
      // 综合阶段（带 [1][2] 引用）
      return _s('# 研究报告\n\n摘要。\n\n## 第一节\n内容 [1][2]\n\n## 参考来源\n1. https://s1.example\n2. https://s2.example');
    }

    final report = await svc.research(
      topic: '测试主题',
      chat: chat,
      search: (q) async {
        searched.add(q);
        return '关于 $q 的资料：https://s${searched.length}.example 的概述。';
      },
    );

    expect(chatCalls, 2); // 拆解 + 综合
    expect(report.questions, ['q1', 'q2']);
    expect(searched, containsAll(['q1', 'q2'])); // 两个子问题都搜了
    expect(report.report, contains('研究报告'));
    expect(report.report, contains('[1]'));
    expect(report.sources, isNotEmpty);
    expect(report.sources.first, contains('http'));
  });

  test('research 对低质量结果执行补搜（第二轮）', () async {
    final searched = <String>[];
    var chatCalls = 0;
    Stream<String> chat(String system, List<Map<String, dynamic>> history) {
      chatCalls++;
      if (chatCalls == 1) return _s('["q-ok", "q-bad"]');
      return _s('完成。');
    }

    final report = await svc.research(
      topic: 't',
      chat: chat,
      search: (q) async {
        searched.add(q);
        // q-bad 第一轮返回空 → 触发补搜
        if (q == 'q-bad' && searched.where((x) => x == 'q-bad').length == 1) {
          return '';
        }
        return '有效资料：https://e.example 内容足够长。';
      },
    );

    // q-bad 被补搜了一次
    expect(
      searched.where((x) => x == 'q-bad').length,
      greaterThanOrEqualTo(2),
    );
    expect(report.sources, isNotEmpty);
  });
}