import 'dart:convert';
import 'dart:io';

/// B13：跨平台 TTS 朗读。
/// - Windows：PowerShell System.Speech（无额外依赖）
/// - macOS：`say` 命令
/// - Linux：espeak-ng（回退 espeak），优先中文语音
/// 文本以参数/base64 传入避免转义问题；朗读可随时停止。
class TtsService {
  TtsService._();

  static Process? _proc;
  static String? _linuxCmd; // 探测到的 Linux 命令（espeak-ng / espeak）

  static bool get speaking => _proc != null;

  static Future<bool> _has(String cmd) async {
    try {
      final r = await Process.run('sh', ['-c', 'command -v $cmd']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// 当前平台朗读是否可用（命令存在性探测）。
  static Future<bool> get supported async {
    if (Platform.isWindows) return true;
    if (Platform.isMacOS) return _has('say');
    if (Platform.isLinux) {
      _linuxCmd ??= await _has('espeak-ng') ? 'espeak-ng' : 'espeak';
      return _linuxCmd!.isNotEmpty;
    }
    return false;
  }

  /// 朗读文本（自动停止上一条）。命令不存在时静默失败。
  static Future<void> speak(String text) async {
    await stop();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // 截断超长文本，避免命令行过长。
    final payload = trimmed.length > 4000
        ? trimmed.substring(0, 4000)
        : trimmed;
    try {
      if (Platform.isWindows) {
        final b64 = base64Encode(utf8.encode(payload));
        final script =
            'Add-Type -AssemblyName System.Speech; '
            '\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
            '\$s.Rate = 0; '
            '\$s.Speak([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\'$b64\'))); '
            '\$s.Dispose();';
        _proc = await Process.start(
          'powershell.exe',
          ['-NoProfile', '-NonInteractive', '-Command', script],
        );
      } else if (Platform.isMacOS) {
        _proc = await Process.start('say', ['-r', '180', payload]);
      } else if (Platform.isLinux) {
        _linuxCmd ??= await _has('espeak-ng') ? 'espeak-ng' : 'espeak';
        _proc = await Process.start(_linuxCmd!, ['-v', 'zh', payload]);
      }
    } catch (_) {
      _proc = null;
    }
  }

  /// 停止朗读。
  static Future<void> stop() async {
    final p = _proc;
    if (p == null) return;
    _proc = null;
    try {
      p.kill();
    } catch (_) {}
    try {
      await p.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}