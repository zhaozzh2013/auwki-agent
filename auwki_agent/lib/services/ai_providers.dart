import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ProviderKind { claude, openai, deepseek, MiniMax }

enum ApiStyle { anthropic, openai }

class ModelOption {
  const ModelOption(this.id, this.label);
  final String id;
  final String label;
}

class ProviderConfig {
  const ProviderConfig({
    required this.kind,
    required this.label,
    required this.baseUrl,
    required this.apiStyle,
    required this.defaultModel,
    required this.models,
  });

  final ProviderKind kind;
  final String label;
  final String baseUrl;
  final ApiStyle apiStyle;
  final String defaultModel;
  final List<ModelOption> models;
}

const List<ProviderConfig> kProviders = [
  ProviderConfig(
    kind: ProviderKind.claude,
    label: 'Claude (Anthropic)',
    baseUrl: 'https://api.anthropic.com',
    apiStyle: ApiStyle.anthropic,
    defaultModel: 'claude-sonnet-4-5',
    models: [
      ModelOption('claude-opus-4-6', 'Claude Opus 4.6'),
      ModelOption('claude-sonnet-4-5', 'Claude Sonnet 4.5'),
      ModelOption('claude-haiku-4-5', 'Claude Haiku 4.5'),
    ],
  ),
  ProviderConfig(
    kind: ProviderKind.MiniMax,
    label: 'MiniMax (Anthropic 兼容)',
    baseUrl: 'https://api.minimaxi.com/anthropic',
    apiStyle: ApiStyle.anthropic,
    defaultModel: 'MiniMax-M3',
    models: [
      ModelOption('MiniMax-M3', 'MiniMax-M3 (1M ctx)'),
      ModelOption('MiniMax-M2.7-highspeed', 'MiniMax-M2.7 高速'),
      ModelOption('MiniMax-M2.5-highspeed', 'MiniMax-M2.5 高速'),
    ],
  ),
  ProviderConfig(
    kind: ProviderKind.openai,
    label: 'ChatGPT (OpenAI)',
    baseUrl: 'https://api.openai.com/v1',
    apiStyle: ApiStyle.openai,
    defaultModel: 'gpt-4o-mini',
    models: [
      ModelOption('gpt-4o', 'GPT-4o'),
      ModelOption('gpt-4o-mini', 'GPT-4o mini'),
      ModelOption('o1-mini', 'o1-mini'),
    ],
  ),
  ProviderConfig(
    kind: ProviderKind.deepseek,
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    apiStyle: ApiStyle.openai,
    defaultModel: 'deepseek-v4-flash',
    models: [
      ModelOption('deepseek-v4-flash', 'DeepSeek V4 Flash'),
      ModelOption('deepseek-v4-pro', 'DeepSeek V4 Pro'),
    ],
  ),
];

ProviderConfig providerById(String id) =>
    kProviders.firstWhere((p) => p.kind.name == id, orElse: () => kProviders.first);

class ChatRequest {
  ChatRequest({
    required this.system,
    required this.messages,
    required this.model,
    required this.maxTokens,
    this.temperature = 1.0,
  });

  final String system;
  final List<Map<String, dynamic>> messages;
  final String model;
  final int maxTokens;
  final double temperature;
}

class AiClient {
  AiClient({required this.config, required this.apiKey});

  final ProviderConfig config;
  final String apiKey;

  Future<String> chat(ChatRequest req) async {
    final stream = chatStream(req);
    final buf = StringBuffer();
    await for (final chunk in stream) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  Stream<String> chatStream(ChatRequest req) async* {
    if (apiKey.isEmpty) {
      yield '[错误] 未配置 API Key，请到 设置 中填写';
      return;
    }
    if (config.apiStyle == ApiStyle.anthropic) {
      yield* _anthropicStream(req);
    } else {
      yield* _openaiStream(req);
    }
  }

  Stream<String> _anthropicStream(ChatRequest req) async* {
    final url = Uri.parse('${config.baseUrl}/v1/messages');
    final body = jsonEncode({
      'model': req.model,
      'max_tokens': req.maxTokens,
      'temperature': req.temperature,
      'system': req.system,
      'messages': req.messages,
      'stream': true,
    });

    final request = http.Request('POST', url)
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      })
      ..body = body;

    final response = await request.send();
    if (response.statusCode ~/ 100 != 2) {
      yield '[错误 ${response.statusCode}] ${await response.stream.bytesToString()}';
      return;
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final raw = line.substring(5).trim();
      if (raw.isEmpty || raw == '[DONE]') continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final type = json['type'];
        if (type == 'content_block_delta') {
          final delta = json['delta'] as Map<String, dynamic>?;
          if (delta?['type'] == 'text_delta') {
            yield delta!['text'] as String;
          }
        }
      } catch (_) {}
    }
  }

  Stream<String> _openaiStream(ChatRequest req) async* {
    final url = Uri.parse('${config.baseUrl}/chat/completions');
    final body = jsonEncode({
      'model': req.model,
      'messages': [
        if (req.system.isNotEmpty) {'role': 'system', 'content': req.system},
        ...req.messages,
      ],
      'max_tokens': req.maxTokens,
      'temperature': req.temperature,
      'stream': true,
    });

    final request = http.Request('POST', url)
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
      })
      ..body = body;

    final response = await request.send();
    if (response.statusCode ~/ 100 != 2) {
      yield '[错误 ${response.statusCode}] ${await response.stream.bytesToString()}';
      return;
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final raw = line.substring(5).trim();
      if (raw.isEmpty || raw == '[DONE]') continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final choices = json['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final content = delta?['content'];
        if (content is String) yield content;
      } catch (_) {}
    }
  }
}