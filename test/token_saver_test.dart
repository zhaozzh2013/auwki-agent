import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:auwki_agent/services/ai_providers.dart';
import 'package:auwki_agent/services/settings_store.dart';
import 'package:auwki_agent/services/token_saver.dart';

class _CaptureHttpClient extends http.BaseClient {
  _CaptureHttpClient(this.onRequest);

  final void Function(http.BaseRequest request, String body) onRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    onRequest(request, utf8.decode(bytes));
    final lines = [
      'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"ok"}}',
      'data: [DONE]',
    ];
    return http.StreamedResponse(
      Stream.fromIterable(lines.map((l) => utf8.encode('$l\n\n'))),
      200,
    );
  }
}

void main() {
  group('TokenSaver', () {
    test('compactText 保留头尾并标注省略', () {
      final src = 'a' * 5000;
      final out = TokenSaver.compactText(src, 1000);
      expect(out.length, lessThan(1000));
      expect(out.contains('chars omitted'), isTrue);
      expect(out.startsWith('a' * 600), isTrue);
      expect(out.endsWith('a' * 250), isTrue);
    });

    test('compactToolResult 按成本模式压缩', () {
      final src = 'x' * 5000;
      expect(
        TokenSaver.compactToolResult(src, CostMode.poor).length,
        lessThan(TokenSaver.toolResultMaxChars(CostMode.poor)),
      );
      expect(
        TokenSaver.compactToolResult(src, CostMode.max).length,
        lessThan(TokenSaver.toolResultMaxChars(CostMode.max)),
      );
    });

    test('trimHistory 超出预算时保留最新消息并注入摘要', () {
      final history = <Map<String, dynamic>>[
        for (var i = 0; i < 60; i++)
          {
            'role': i.isEven ? 'user' : 'assistant',
            'content': '这是一条用于填充上下文的较长消息，编号 $i。' * 8,
          },
      ];
      final out = TokenSaver.trimHistory(
        history,
        CostMode.poor,
        summaryNote: '[历史摘要] 已完成前面的工作',
      );
      expect(out.first['content'], '[历史摘要] 已完成前面的工作');
      expect(
        TokenSaver.tokensOf(out),
        lessThanOrEqualTo(TokenSaver.historyBudgetTokens(CostMode.poor) + 400),
      );
      expect(out.last['content'], history.last['content']);
    });

    test('预算充足时不裁剪', () {
      final history = [
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hello'},
      ];
      final out = TokenSaver.trimHistory(history, CostMode.max);
      expect(out.length, 2);
      expect(out.first['content'], 'hi');
    });
  });

  group('AiClient 提示词缓存', () {
    test('Claude 请求携带 system 与末条 user 的 cache_control', () async {
      String? body;
      final client = AiClient(
        config: providerById('claude'),
        apiKeys: ['sk-test'],
        httpClient: _CaptureHttpClient((_, b) => body = b),
      );
      final text = await client.chat(
        ChatRequest(
          system: 'sys',
          messages: [
            {'role': 'user', 'content': 'hi'},
            {'role': 'assistant', 'content': 'hello'},
            {'role': 'user', 'content': 'continue'},
          ],
          model: 'claude-sonnet-4-5',
          maxTokens: 100,
        ),
      );
      expect(text, 'ok');
      final json = jsonDecode(body!) as Map<String, dynamic>;
      final system = (json['system'] as List).first as Map<String, dynamic>;
      expect(system['cache_control'], {'type': 'ephemeral'});
      final messages = json['messages'] as List;
      final last = messages.last as Map<String, dynamic>;
      final content = last['content'] as List;
      expect(
        (content.first as Map<String, dynamic>)['cache_control'],
        {'type': 'ephemeral'},
      );
    });

    test('MiniMax 兼容请求保持原格式', () async {
      String? body;
      final client = AiClient(
        config: providerById('MiniMax'),
        apiKeys: ['sk-test'],
        httpClient: _CaptureHttpClient((_, b) => body = b),
      );
      await client.chat(
        ChatRequest(
          system: 'sys',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          model: 'MiniMax-M3',
          maxTokens: 100,
        ),
      );
      final json = jsonDecode(body!) as Map<String, dynamic>;
      expect(json['system'], 'sys');
      final messages = json['messages'] as List;
      expect((messages.last as Map<String, dynamic>)['content'], 'hi');
    });
  });

  group('AiClient 图片内容块', () {
    test('OpenAI 请求把图片转成 image_url', () async {
      String? body;
      final client = AiClient(
        config: providerById('openai'),
        apiKeys: ['sk-test'],
        httpClient: _CaptureHttpClient((_, b) => body = b),
      );
      await client.chat(
        ChatRequest(
          system: 'sys',
          messages: [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'look'},
                {
                  'type': 'image',
                  'media_type': 'image/png',
                  'data': 'AAA',
                },
              ],
            },
          ],
          model: 'gpt-4o',
          maxTokens: 100,
        ),
      );
      final json = jsonDecode(body!) as Map<String, dynamic>;
      final msg = (json['messages'] as List).last as Map<String, dynamic>;
      final content = msg['content'] as List;
      expect(content.first['type'], 'text');
      expect(content.last['type'], 'image_url');
      final url = ((content.last as Map)['image_url'] as Map)['url'];
      expect(url, startsWith('data:image/png;base64,AAA'));
    });

    test('OpenAI o 系列使用 max_completion_tokens 且不带 temperature', () async {
      String? body;
      final client = AiClient(
        config: providerById('openai'),
        apiKeys: ['sk-test'],
        httpClient: _CaptureHttpClient((_, b) => body = b),
      );
      await client.chat(
        ChatRequest(
          system: 'sys',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          model: 'o1-mini',
          maxTokens: 123,
          temperature: 0.7,
        ),
      );
      final json = jsonDecode(body!) as Map<String, dynamic>;
      expect(json.containsKey('max_completion_tokens'), isTrue);
      expect(json['max_completion_tokens'], 123);
      expect(json.containsKey('max_tokens'), isFalse);
      expect(json.containsKey('temperature'), isFalse);
    });

    test('普通 OpenAI 模型仍使用 max_tokens + temperature', () async {
      String? body;
      final client = AiClient(
        config: providerById('openai'),
        apiKeys: ['sk-test'],
        httpClient: _CaptureHttpClient((_, b) => body = b),
      );
      await client.chat(
        ChatRequest(
          system: 'sys',
          messages: [
            {'role': 'user', 'content': 'hi'},
          ],
          model: 'gpt-4o-mini',
          maxTokens: 200,
          temperature: 0.5,
        ),
      );
      final json = jsonDecode(body!) as Map<String, dynamic>;
      expect(json['max_tokens'], 200);
      expect(json['temperature'], 0.5);
    });

    test('Anthropic 请求把图片转成 image source', () async {
      String? body;
      final client = AiClient(
        config: providerById('claude'),
        apiKeys: ['sk-test'],
        httpClient: _CaptureHttpClient((_, b) => body = b),
      );
      await client.chat(
        ChatRequest(
          system: 'sys',
          messages: [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': 'look'},
                {
                  'type': 'image',
                  'media_type': 'image/png',
                  'data': 'AAA',
                },
              ],
            },
          ],
          model: 'claude-sonnet-4-5',
          maxTokens: 100,
        ),
      );
      final json = jsonDecode(body!) as Map<String, dynamic>;
      final msg = (json['messages'] as List).last as Map<String, dynamic>;
      final content = msg['content'] as List;
      expect(content.last['type'], 'image');
      final source = (content.last as Map)['source'] as Map;
      expect(source['data'], 'AAA');
      expect(source['media_type'], 'image/png');
    });
  });

  group('视觉模型识别', () {
    test('已知视觉模型返回 true', () {
      expect(isVisionModel('gpt-4o'), isTrue);
      expect(isVisionModel('gpt-4o-mini'), isTrue);
      expect(isVisionModel('claude-sonnet-4-5'), isTrue);
      expect(isVisionModel('claude-opus-4-6'), isTrue);
      expect(isVisionModel('gemini-2.0-flash'), isTrue);
    });

    test('纯文本模型返回 false', () {
      expect(isVisionModel('deepseek-v4-pro'), isFalse);
      expect(isVisionModel('deepseek-v4-flash'), isFalse);
      expect(isVisionModel('gpt-3.5-turbo'), isFalse);
    });
  });
}
