import 'dart:convert';

import '../i18n/strings.dart';

/// Deep Research 模式的产出。
class DeepResearchReport {
  const DeepResearchReport({
    required this.report,
    required this.sources,
    required this.questions,
  });

  final String report;
  final List<String> sources;
  final List<String> questions;
}

/// Deep Research 模式（A：现代化 Agent 功能）。
///
/// 流程：
/// 1. **拆解**：把主题交给模型拆成 4~6 个子问题
/// 2. **并行搜索**：每个子问题走 websearch 工具（复用权限/缓存/审计链）
/// 3. **迭代补搜**：结果空/质量差的子问题追问一轮（最多 [maxRounds] 轮）
/// 4. **综合成文**：模型汇总全部来源生成带引用标记的报告（[1][2]…）
///
/// [chat] 与 [search] 由调用方提供（对话流 / 工具通道），便于测试注入。
class DeepResearchService {
  DeepResearchService._();

  static final DeepResearchService instance = DeepResearchService._();

  static const int maxRounds = 2;

  /// 统计用：允许测试注入替代实现。
  Future<String> Function(String query)? searchOverride;
  Stream<String> Function(String system, List<Map<String, dynamic>> history)?
      chatOverride;

  Future<String> _search(
    String query,
    Future<String> Function(String) search,
  ) =>
      search(query);

  /// 解析模型输出的子问题列表：优先 JSON 数组，兼容“1. xxx”序号列表。
  List<String> parseQuestions(String raw) {
    final cleaned = raw.trim();
    // JSON 数组
    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start >= 0 && end > start) {
      try {
        final list = jsonDecode(cleaned.substring(start, end + 1));
        if (list is List) {
          final out = [
            for (final q in list)
              if (q is String && q.trim().isNotEmpty) q.trim(),
          ];
          if (out.isNotEmpty) return out.take(6).toList();
        }
      } catch (_) {}
    }
    // 序号列表行（必须数字开头，避免把闲聊当子问题）
    final out = <String>[];
    for (final line in cleaned.split('\n')) {
      final m = RegExp(r'^\s*\d+[.、)]\s*(.+?)\s*$').firstMatch(line);
      if (m == null) continue;
      final q = m.group(1)!.trim();
      if (q.isNotEmpty && !q.startsWith('[') && q.length > 1) {
        out.add(q);
      }
      if (out.length >= 6) break;
    }
    return out;
  }

  /// 从搜索结果文本中提取 URL（去重，最多 [maxCount] 条）。
  List<String> extractUrls(List<String> results, {int maxCount = 12}) {
    final seen = <String>{};
    final urls = <String>[];
    for (final text in results) {
      final it = RegExp("https?://[^\\s\\)\\]}\"'，。；<>]+")
          .allMatches(text);
      for (final m in it) {
        final u = m.group(0)!.replaceAll(RegExp(r'[.,;:!?]+$'), '');
        if (seen.add(u)) urls.add(u);
        if (urls.length >= maxCount) return urls;
      }
    }
    return urls;
  }

  /// 判断一路搜索是否需要补搜（空/提示无结果/结果太短）。
  bool needsFollowUp(String result) {
    final r = result.trim();
    if (r.isEmpty) return true;
    final lower = r.toLowerCase();
    if (lower.contains('no result') ||
        lower.contains('没有结果') ||
        lower.contains('未能') ||
        lower.contains('failed') ||
        lower.contains('timeout') ||
        lower.contains('超时')) {
      return true;
    }
    if (r.length < 40) return true;
    return false;
  }

  /// 运行一次 Deep Research。
  Future<DeepResearchReport> research({
    required String topic,
    required Stream<String> Function(
      String system,
      List<Map<String, dynamic>> history,
    )
    chat,
    required Future<String> Function(String query) search,
    void Function(String stage)? onProgress,
  }) async {
    onProgress?.call('plan');
    final planBuf = StringBuffer();
    await for (final chunk in chat(_planSystemPrompt(), _planHistory(topic))) {
      planBuf.write(chunk);
    }
    var questions = parseQuestions(planBuf.toString());
    if (questions.isEmpty) {
      questions = [
        '$topic 概述',
        '$topic 关键技术/要点',
        '$topic 现状与进展',
        '$topic 常见问题与解决方案',
      ];
    }

    // 每路子问题独立搜索轮次，记录每轮结果。
    final rounds = <String, List<String>>{};
    for (var round = 0; round < maxRounds; round++) {
      onProgress?.call('search:${round + 1}/$maxRounds');
      final tasks = <Future<(String, String)>>[];
      for (final q in questions) {
        tasks.add(() async {
          final r = await _search(q, search);
          return (q, r);
        }());
      }
      final done = await Future.wait<(String, String)>(tasks);
      for (final (q, r) in done) {
        rounds.putIfAbsent(q, () => []).add(r);
      }
      // 若所有子问题都已达标则提前结束迭代。
      final pending = questions.where((q) {
        final latest = rounds[q]!.isEmpty ? '' : rounds[q]!.last;
        return needsFollowUp(latest);
      });
      if (pending.isEmpty) break;
    }

    // 汇总全部搜索结果，生成报告。
    onProgress?.call('synthesis');
    final digest = StringBuffer();
    var idx = 0;
    for (final q in questions) {
      final rs = rounds[q] ?? const [];
      final merged = rs.join('\n\n---\n\n');
      digest.writeln('## ${++idx}. $q\n$merged\n');
    }
    final sources = extractUrls([
      for (final q in questions) ...(rounds[q] ?? const []),
    ]);
    final reportBuf = StringBuffer();
    await for (final chunk in chat(
      _synthesisSystemPrompt(),
      _synthesisHistory(topic, digest.toString(), sources),
    )) {
      reportBuf.write(chunk);
    }

    return DeepResearchReport(
      report: reportBuf.toString().trim(),
      sources: sources,
      questions: questions,
    );
  }

  String _planSystemPrompt() => '''
你是研究规划器。把用户的研究主题拆解为 4~6 个相互独立、可搜索的子问题。
要求：
- 子问题覆盖：概述、关键技术/机制、现状进展、挑战与解决方案 等维度
- 每个子问题是一个完整的搜索查询，可直接用于搜索引擎
- 只输出 JSON 数组，如 ["q1", "q2", "q3"]，不要任何其它文字''';

  List<Map<String, dynamic>> _planHistory(String topic) => [
        <String, dynamic>{'role': 'user', 'content': topic},
      ];

  String _synthesisSystemPrompt() => '''
你是研究员。根据提供的【子问题与检索资料】撰写一份结构化的深度研究报告。
要求：
- 用 Markdown 输出，标题为主题本身
- 开头写 2~3 句摘要
- 按子问题分节（## 小节），每节内容基于对应检索资料
- 陈述事实处用 [编号] 标注引用来源（编号对应文末的参考来源列表）
- 末尾输出 "## 参考来源" 编号列表（与引用编号一致）
- 用中文撰写；信息不足的段落明确说明
- 只输出报告正文''';

  List<Map<String, dynamic>> _synthesisHistory(
    String topic,
    String digest,
    List<String> sources,
  ) => [
        <String, dynamic>{
          'role': 'user',
          'content': '主题：$topic\n\n【检索资料】\n$digest',
        },
        <String, dynamic>{
          'role': 'user',
          'content': '参考来源（引用编号从 1 开始）：\n${sources.asMap().entries.map((e) => '${e.key + 1}. ${e.value}').join('\n')}\n\n请开始撰写报告。',
        },
      ];

  /// 进度阶段的本地化文案（供 UI 气泡使用）。
  static String stageLabel(String stage) {
    if (stage == 'plan') return I18n.t('research.stage.plan');
    if (stage.startsWith('search:')) {
      final round = int.tryParse(stage.split(':')[1].split('/').first) ?? 1;
      return round > 1
          ? I18n.t('research.stage.search2')
          : I18n.t('research.stage.search1');
    }
    return I18n.t('research.stage.search2');
  }
}