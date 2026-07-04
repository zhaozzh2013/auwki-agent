import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'ai_providers.dart';

class AgentToolCall {
  AgentToolCall({required this.tool, required this.args});
  final String tool;
  final String args;

  String get display => '$tool("$args")';
}

class AgentResult {
  AgentResult({required this.call, required this.output, this.error});
  final AgentToolCall call;
  final String output;
  final String? error;

  bool get ok => error == null;
}

class AgentRunner {
  /// 解析 AI 输出中的工具调用块
  /// 格式: [正式输出]\nwebfetch("...")\n... [输出结束]
  static List<AgentToolCall> parse(String text) {
    final calls = <AgentToolCall>[];
    final startIdx = text.indexOf('[正式输出]');
    if (startIdx < 0) return calls;
    var cursor = startIdx + '[正式输出]'.length;
    while (cursor < text.length) {
      final endIdx = text.indexOf('[输出结束]', cursor);
      final slice = endIdx < 0
          ? text.substring(cursor)
          : text.substring(cursor, endIdx);
      final re = RegExp(r'(\w+)\("((?:\\"|[^"])*)"\)');
      for (final m in re.allMatches(slice)) {
        calls.add(AgentToolCall(tool: m.group(1)!, args: m.group(2)!));
      }
      if (endIdx < 0) break;
      cursor = endIdx + '[输出结束]'.length;
    }
    return calls;
  }

  static Future<AgentResult> execute(AgentToolCall call) async {
    try {
      final out = switch (call.tool) {
        'webfetch' => await _webfetch(call.args),
        'websearch' => await _websearch(call.args),
        'command' => await _command(call.args),
        _ => throw Exception('未知工具: ${call.tool}'),
      };
      return AgentResult(call: call, output: out);
    } catch (e) {
      return AgentResult(call: call, output: '', error: e.toString());
    }
  }

  static Future<String> _webfetch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return '[错误] URL 不合法: $url';
    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode ~/ 100 != 2) {
      return '[错误 ${resp.statusCode}] $url';
    }
    final body = resp.body;
    return body.length > 8000
        ? '${body.substring(0, 8000)}\n…[截断]'
        : body;
  }

  static const List<String> _searxInstances = [
    'https://search.disroot.org',
    'https://searx.be',
    'https://search.bus-hit.me',
    'https://priv.au',
    'https://searx.work',
    'https://searx.tiekoetter.com',
    'https://search.privacyguides.net',
    'https://search.ononoki.org',
    'https://searx.lavatech.top',
  ];

  static Future<String> _websearch(String query) async {
    final headers = {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'Accept': 'application/json',
    };

    for (final inst in _searxInstances) {
      try {
        final uri = Uri.parse('$inst/search?q=${Uri.encodeQueryComponent(query)}&format=json');
        final resp = await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) continue;
        final body = resp.body;
        final json = jsonDecode(body) as Map<String, dynamic>;
        final results = (json['results'] as List?) ?? [];
        if (results.isEmpty) continue;
        return results
            .take(8)
            .map((r) {
              final m = r as Map<String, dynamic>;
              final title = (m['title'] ?? '').toString().trim();
              final url = (m['url'] ?? '').toString().trim();
              final content = (m['content'] ?? '').toString().trim();
              return '- $title\n  $url\n  $content';
            })
            .join('\n');
      } catch (_) {
        continue;
      }
    }
    return '[错误] 所有 SearXNG 公共实例均不可用\n请到 lib/services/agent.dart 的 _searxInstances 列表里换成你网络能通的实例';
  }

  static Future<String> _command(String cmd) async {
    final res = await Process.run('bash', ['-c', cmd])
        .timeout(const Duration(seconds: 30));
    final buf = StringBuffer();
    if (res.stdout.toString().isNotEmpty) buf.write(res.stdout);
    if (res.stderr.toString().isNotEmpty) {
      if (buf.isNotEmpty) buf.write('\n--- stderr ---\n');
      buf.write(res.stderr);
    }
    buf.write('\n[exit ${res.exitCode}]');
    final out = buf.toString();
    return out.length > 6000 ? '${out.substring(0, 6000)}\n…[截断]' : out;
  }
}

class AgentTurn {
  AgentTurn({required this.thinking, required this.toolCall, required this.result});
  final String thinking;
  final AgentToolCall toolCall;
  final AgentResult result;
}