import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 一条工具调用审计记录（A14）。
class AuditRecord {
  AuditRecord({
    required this.time,
    this.conversationId,
    required this.tool,
    required this.args,
    required this.ok,
    this.output = '',
    this.dryRun = false,
    this.denied = false,
  });

  final DateTime time;
  final String? conversationId;
  final String tool;
  final String args;
  final bool ok;
  final String output;
  final bool dryRun;
  final bool denied;

  factory AuditRecord.fromJson(Map<String, dynamic> m) => AuditRecord(
    time: DateTime.tryParse((m['time'] ?? '').toString()) ?? DateTime.now(),
    conversationId: m['conversationId']?.toString(),
    tool: (m['tool'] ?? '').toString(),
    args: (m['args'] ?? '').toString(),
    ok: m['ok'] == true,
    output: (m['output'] ?? '').toString(),
    dryRun: m['dryRun'] == true,
    denied: m['denied'] == true,
  );

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'conversationId': conversationId,
    'tool': tool,
    'args': args,
    'ok': ok,
    'output': output,
    'dryRun': dryRun,
    'denied': denied,
  };
}

/// 审计日志（A14）：JSONL 追加写，可查看、导出、清空。
class AuditService {
  AuditService._();

  static final AuditService instance = AuditService._();

  /// 测试用：覆盖日志文件位置。
  static File? debugFile;

  Future<File> _file() async {
    final override = debugFile;
    if (override != null) return override;
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/audit.jsonl');
  }

  Future<void> record({
    String? conversationId,
    required String tool,
    required String args,
    required bool ok,
    String output = '',
    bool dryRun = false,
    bool denied = false,
  }) async {
    final rec = AuditRecord(
      time: DateTime.now(),
      conversationId: conversationId,
      tool: tool,
      args: args,
      ok: ok,
      output: _clip(output),
      dryRun: dryRun,
      denied: denied,
    );
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(
        '${jsonEncode(rec.toJson())}\n',
        mode: FileMode.append,
      );
    } catch (_) {
      // 审计失败不阻断工具执行。
    }
  }

  /// 最近的记录（新的在前）。
  Future<List<AuditRecord>> recent({int limit = 200}) async {
    final out = <AuditRecord>[];
    try {
      final f = await _file();
      if (!await f.exists()) return out;
      final lines = await f.readAsLines();
      for (final line in lines.reversed) {
        if (line.trim().isEmpty) continue;
        try {
          out.add(
            AuditRecord.fromJson(jsonDecode(line) as Map<String, dynamic>),
          );
        } catch (_) {}
        if (out.length >= limit) break;
      }
    } catch (_) {}
    return out;
  }

  Future<void> exportTo(String path) async {
    final f = await _file();
    if (await f.exists()) {
      await File(path).writeAsString(await f.readAsString());
    }
  }

  Future<void> clear() async {
    try {
      final f = await _file();
      if (await f.exists()) await f.writeAsString('');
    } catch (_) {}
  }

  static String _clip(String s) =>
      s.length > 2000 ? '${s.substring(0, 2000)}\n...[truncated]' : s;
}
