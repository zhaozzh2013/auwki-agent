import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../i18n/strings.dart';
import 'net_client.dart';

enum ProviderKind {
  claude,
  openai,
  deepseek,
  // ignore: constant_identifier_names — kind.name 用于配置持久化，保持原名
  MiniMax,
  custom,
}

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

  ProviderConfig withBaseUrl(String value) => ProviderConfig(
    kind: kind,
    label: label,
    baseUrl: value,
    apiStyle: apiStyle,
    defaultModel: defaultModel,
    models: models,
  );
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
    label: 'MiniMax (Anthropic compatible)',
    baseUrl: 'https://api.minimaxi.com/anthropic',
    apiStyle: ApiStyle.anthropic,
    defaultModel: 'MiniMax-M3',
    models: [
      ModelOption('MiniMax-M3', 'MiniMax-M3 (1M ctx)'),
      ModelOption('MiniMax-M2.7-highspeed', 'MiniMax-M2.7 Highspeed'),
      ModelOption('MiniMax-M2.5-highspeed', 'MiniMax-M2.5 Highspeed'),
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

ProviderConfig providerById(String id) => kProviders.firstWhere(
  (p) => p.kind.name == id,
  orElse: () => kProviders.first,
);

/// 判断模型是否支持图片输入（视觉模型）。
/// 命中已知视觉系列；不确定的模型保守按纯文本处理。
bool isVisionModel(String modelId) {
  final m = modelId.toLowerCase();
  if (m.contains('vision') || m.contains('-vl') || m.contains('gemini')) {
    return true;
  }
  if (m.contains('gpt-4o') ||
      m.contains('gpt-4.1') ||
      m.contains('gpt-5') ||
      m.contains('o1') ||
      m.contains('o3') ||
      m.contains('o4')) {
    return true;
  }
  if (m.contains('claude') &&
      (m.contains('opus') || m.contains('sonnet') || m.contains('haiku'))) {
    return true;
  }
  if (m.contains('qwen') &&
      (m.contains('vl') || m.contains('max') || m.contains('plus'))) {
    return true;
  }
  if (m.contains('glm-4v') ||
      m.contains('moonshot-vision') ||
      m.contains('internvl')) {
    return true;
  }
  return false;
}

/// 用户在设置里添加的自定义供应商（OpenAI / Anthropic 兼容）。
class CustomProviderSeed {
  const CustomProviderSeed({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiStyle,
    required this.models,
  });

  final String id;
  final String name;
  final String baseUrl;
  final ApiStyle apiStyle;
  final List<String> models;
}

ProviderConfig providerFromSeed(CustomProviderSeed seed) => ProviderConfig(
  kind: ProviderKind.custom,
  label: seed.name.trim().isEmpty ? seed.id : seed.name.trim(),
  baseUrl: seed.baseUrl.trim(),
  apiStyle: seed.apiStyle,
  defaultModel: seed.models.isEmpty ? 'model' : seed.models.first.trim(),
  models: [
    for (final m in seed.models)
      if (m.trim().isNotEmpty) ModelOption(m.trim(), m.trim()),
  ],
);

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

/// 连接测试结果（G03）。
class ConnectionTestResult {
  const ConnectionTestResult({
    required this.ok,
    required this.latencyMs,
    this.models,
    this.error,
  });

  final bool ok;
  final int latencyMs;
  final List<String>? models;
  final String? error;
}

class AiClient {
  AiClient({
    required this.config,
    required this.apiKeys,
    http.Client? httpClient,
  }) : _http = httpClient ?? NetClient.build();

  final ProviderConfig config;

  /// 一个或多个 API Key（G05：多 Key 自动轮换）。
  final List<String> apiKeys;
  final http.Client _http;

  /// 跨实例轮换索引（同一供应商的所有 AiClient 共享）。
  static final Map<String, int> _rotationIndex = {};

  int get _keyIndex =>
      _rotationIndex[config.kind.name] ?? 0;

  String get _currentKey {
    final keys = apiKeys.where((k) => k.trim().isNotEmpty).toList();
    if (keys.isEmpty) return '';
    final i = _keyIndex % keys.length;
    return _normalizeKey(keys[i]);
  }

  String get apiKey => _currentKey;

  Future<String> chat(ChatRequest req) async {
    final stream = chatStream(req);
    final buf = StringBuffer();
    await for (final chunk in stream) {
      buf.write(chunk);
    }
    return buf.toString();
  }

  Stream<String> chatStream(ChatRequest req) async* {
    if (_currentKey.isEmpty) {
      throw Exception(I18n.t('agent.no_api_key'));
    }
    if (config.apiStyle == ApiStyle.anthropic) {
      yield* _anthropicStream(req);
    } else {
      yield* _openaiStream(req);
    }
  }

  /// 请求返回 401/403 时轮换到下一个 Key，返回是否还有可用的 Key。
  bool _rotateOnAuthFailure() {
    final count = apiKeys.where((k) => k.trim().isNotEmpty).length;
    if (count <= 1) return false;
    _rotationIndex[config.kind.name] =
        (_rotationIndex[config.kind.name] ?? 0) + 1;
    return true;
  }

  Stream<String> _anthropicStream(ChatRequest req) async* {
    final url = Uri.parse('${config.baseUrl}/v1/messages');
    // Claude 官方 API 支持显式提示词缓存；兼容类供应商保持原格式避免报错。
    final cacheable = config.kind == ProviderKind.claude;
    final body = jsonEncode({
      'model': req.model,
      'max_tokens': req.maxTokens,
      'temperature': req.temperature,
      if (cacheable)
        'system': [
          {
            'type': 'text',
            'text': req.system,
            'cache_control': {'type': 'ephemeral'},
          },
        ]
      else
        'system': req.system,
      'messages': cacheable
          ? _withAnthropicCache(
              req.messages.map(_anthropicMessage).toList(),
            )
          : req.messages.map(_anthropicMessage).toList(),
      'stream': true,
    });

    var attempts = apiKeys.where((k) => k.trim().isNotEmpty).length;
    while (attempts > 0) {
      attempts--;
      final request = http.Request('POST', url)
        ..headers.addAll({
          'content-type': 'application/json',
          'x-api-key': _currentKey,
          'anthropic-version': '2023-06-01',
        })
        ..body = body;

      final response = await _http.send(request);
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (_rotateOnAuthFailure()) continue;
        throw Exception(
          await _formatHttpError(response.statusCode, response.stream),
        );
      }
      if (response.statusCode ~/ 100 != 2) {
        throw Exception(
          await _formatHttpError(response.statusCode, response.stream),
        );
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
      return;
    }
    throw Exception(I18n.t('agent.no_api_key'));
  }

  /// 为 Claude 官方 API 添加提示词缓存断点：
  /// system 块固定可缓存，最后一轮 user 消息作为前缀断点，
  /// 多轮请求命中缓存后可省下大部分输入 token。
  List<Map<String, dynamic>> _withAnthropicCache(
    List<Map<String, dynamic>> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      final content = m['content'];
      if (i == messages.length - 1 &&
          (m['role'] ?? '') == 'user' &&
          content is String) {
        out.add({
          ...m,
          'content': [
            {
              'type': 'text',
              'text': content,
              'cache_control': {'type': 'ephemeral'},
            },
          ],
        });
      } else {
        out.add(m);
      }
    }
    return out;
  }

  /// 把通用内容块（text/image）转换成 Anthropic 格式。
  Map<String, dynamic> _anthropicMessage(Map<String, dynamic> m) {
    final content = m['content'];
    if (content is! List) return m;
    final blocks = <Map<String, dynamic>>[];
    for (final b in content) {
      final type = (b['type'] ?? '').toString();
      if (type == 'image') {
        blocks.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': b['media_type'] ?? 'image/png',
            'data': b['data'] ?? '',
          },
        });
      } else {
        blocks.add({'type': 'text', 'text': (b['text'] ?? '').toString()});
      }
    }
    return {...m, 'content': blocks};
  }

  Stream<String> _openaiStream(ChatRequest req) async* {
    final url = Uri.parse('${config.baseUrl}/chat/completions');
    // OpenAI o 系列推理模型：必须用 max_completion_tokens，且不接受 temperature。
    final m = req.model.toLowerCase();
    final isOSeries = RegExp(r'(^|-)o[134]($|-)').hasMatch(m);
    final body = jsonEncode({
      'model': req.model,
      'messages': [
        if (req.system.isNotEmpty) {'role': 'system', 'content': req.system},
        ...req.messages.map(_openAiMessage),
      ],
      if (isOSeries)
        'max_completion_tokens': req.maxTokens
      else
        'max_tokens': req.maxTokens,
      if (!isOSeries) 'temperature': req.temperature,
      'stream': true,
    });

    var attempts = apiKeys.where((k) => k.trim().isNotEmpty).length;
    while (attempts > 0) {
      attempts--;
      final request = http.Request('POST', url)
        ..headers.addAll({
          'content-type': 'application/json',
          'authorization': 'Bearer $_currentKey',
        })
        ..body = body;

      final response = await _http.send(request);
      if (response.statusCode == 401 || response.statusCode == 403) {
        if (_rotateOnAuthFailure()) continue;
        throw Exception(
          await _formatHttpError(response.statusCode, response.stream),
        );
      }
      if (response.statusCode ~/ 100 != 2) {
        throw Exception(
          await _formatHttpError(response.statusCode, response.stream),
        );
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
      return;
    }
    throw Exception(I18n.t('agent.no_api_key'));
  }

  /// 把通用内容块（text/image）转换成 OpenAI 格式。
  Map<String, dynamic> _openAiMessage(Map<String, dynamic> m) {
    final content = m['content'];
    if (content is! List) return m;
    final blocks = <Map<String, dynamic>>[];
    for (final b in content) {
      final type = (b['type'] ?? '').toString();
      if (type == 'image') {
        blocks.add({
          'type': 'image_url',
          'image_url': {
            'url':
                'data:${b['media_type'] ?? 'image/png'};base64,${b['data'] ?? ''}',
          },
        });
      } else {
        blocks.add({
          'type': 'text',
          'text': (b['text'] ?? '').toString(),
        });
      }
    }
    return {...m, 'content': blocks};
  }

  /// G03：连接测试——OpenAI 风格优先 GET /models，否则发最小 chat 请求。
  Future<ConnectionTestResult> testConnection({
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final sw = Stopwatch()..start();
    try {
      if (config.apiStyle == ApiStyle.openai) {
        final models = await _tryFetchOpenAiModels(timeout: timeout);
        if (models != null) {
          return ConnectionTestResult(
            ok: true,
            latencyMs: sw.elapsedMilliseconds,
            models: models,
          );
        }
      }
      // 最小 chat 请求验证（两种风格通用）。
      final req = ChatRequest(
        system: 'ping',
        messages: [
          {'role': 'user', 'content': 'ping'},
        ],
        model: config.defaultModel,
        maxTokens: 8,
      );
      final buf = StringBuffer();
      await for (final chunk in chatStream(req).timeout(timeout)) {
        buf.write(chunk);
        if (buf.length > 200) break;
      }
      return ConnectionTestResult(
        ok: true,
        latencyMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      return ConnectionTestResult(
        ok: false,
        latencyMs: sw.elapsedMilliseconds,
        error: '$e',
      );
    }
  }

  /// G01：拉取模型列表（OpenAI 风格 GET /models；Anthropic 风格 GET /v1/models）。
  Future<List<String>?> fetchModels({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    try {
      if (config.apiStyle == ApiStyle.openai) {
        return await _tryFetchOpenAiModels(timeout: timeout);
      }
      final resp = await _http
          .get(
            Uri.parse('${config.baseUrl}/v1/models'),
            headers: {
              'x-api-key': _currentKey,
              'anthropic-version': '2023-06-01',
            },
          )
          .timeout(timeout);
      if (resp.statusCode ~/ 100 != 2) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = json['data'];
      if (data is List) {
        return [
          for (final m in data)
            if (m is Map && (m['id'] ?? '').toString().isNotEmpty)
              (m['id'] ?? '').toString(),
        ];
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<String>?> _tryFetchOpenAiModels({
    required Duration timeout,
  }) async {
    try {
      final resp = await _http
          .get(
            Uri.parse('${config.baseUrl}/models'),
            headers: {'authorization': 'Bearer $_currentKey'},
          )
          .timeout(timeout);
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = json['data'];
      if (data is List) {
        return [
          for (final m in data)
            if (m is Map && (m['id'] ?? '').toString().isNotEmpty)
              (m['id'] ?? '').toString(),
        ];
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _normalizeKey(String key) {
    final trimmed = key.trim();
    return trimmed.toLowerCase().startsWith('bearer ')
        ? trimmed.substring(7).trim()
        : trimmed;
  }

  Future<String> _formatHttpError(
    int statusCode,
    http.ByteStream stream,
  ) async {
    final body = await stream.bytesToString();
    if (statusCode == 401 || statusCode == 403) {
      return I18n.t('agent.error.auth_failed', {'provider': config.label});
    }
    return I18n.t('agent.error.http_status', {
      'code': '$statusCode',
      'body': _sanitizeErrorBody(body),
    });
  }

  String _sanitizeErrorBody(String body) {
    return body
        .replaceAll(RegExp(r'sk-[A-Za-z0-9_\-]{8,}'), 'sk-***')
        .replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9_\.\-]{8,}'), 'Bearer ***');
  }

  void dispose() {
    _http.close();
  }
}
