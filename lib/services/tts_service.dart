import 'dart:convert';
import 'dart:io';

/// B13：Windows TTS 朗读（基于 PowerShell System.Speech，无额外依赖）。
/// 文本以 base64 传入，避免转义问题；朗读可随时停止。
class TtsService {
  TtsService._();

  static Process? _proc;

  static bool get speaking => _proc != null;

  /// 朗读文本（自动停止上一条）。
  static Future<void> speak(String text) async {
    await stop();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // 截断超长文本，避免命令行过长。
    final payload = trimmed.length > 4000
        ? trimmed.substring(0, 4000)
        : trimmed;
    final b64 = base64Encode(utf8.encode(payload));
    final script =
        'Add-Type -AssemblyName System.Speech; '
        '\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; '
        '\$s.Rate = 0; '
        '\$s.Speak([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(\'$b64\'))); '
        '\$s.Dispose();';
    try {
      _proc = await Process.start(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      );
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
