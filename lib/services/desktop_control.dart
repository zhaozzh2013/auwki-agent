import 'dart:convert';
import 'dart:io';

import '../i18n/strings.dart';

/// 跨平台桌面控制适配器。
///
/// 统一把屏幕翻译成“文本地图 + 坐标”，让纯文本模型也能操作桌面：
/// - Windows：UI Automation + user32（PowerShell）
/// - macOS：系统辅助功能 System Events（osascript）
/// - Linux：AT-SPI 枚举 + xdotool 输入（python3/pyatspi）
/// - Android：预留 AccessibilityService 适配（后续版本）
///
/// 所有工具返回值保持简短（[ok] ...），避免浪费 token。
class DesktopControl {
  DesktopControl._();

  static bool get supported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<String> run(String tool, String arg) async {
    if (Platform.isWindows) return _windows(tool, arg);
    if (Platform.isMacOS) return _macos(tool, arg);
    if (Platform.isLinux) return _linux(tool, arg);
    return I18n.t('agent.error.platform_unsupported', {'tool': tool});
  }

  // ───────────────────────── Windows ─────────────────────────

  static Future<String> _windows(String tool, String arg) async {
    switch (tool) {
      case 'desktop_dump':
        return _windowsDump(arg);
      case 'desktop_click':
        return _windowsClick(arg);
      case 'desktop_type':
        return _windowsType(arg);
      case 'desktop_key':
        return _windowsKey(arg);
      case 'desktop_open':
        return _windowsOpen(arg);
      case 'desktop_scroll':
        return _windowsScroll(arg);
      case 'desktop_wait':
        return _windowsWait(arg);
      case 'desktop_ocr':
        return _windowsOcr();
      default:
        return I18n.t('agent.error.platform_unsupported', {'tool': tool});
    }
  }

  static Future<String> _runWindowsPs(String script) async {
    try {
      final r = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', script],
      );
      if (r.exitCode != 0) {
        return '[错误] 桌面操作失败\n${r.stderr}';
      }
      return (r.stdout as String).trim();
    } catch (e) {
      return '[错误] 桌面操作失败\n$e';
    }
  }

  static Future<String> _windowsDump(String arg) async {
    const script = r'''
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$full = @@FULL@@
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AuWin {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@
if ($full) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $winTitle = 'all'
} else {
  $hwnd = [AuWin]::GetForegroundWindow()
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $winTitle = $root.Current.Name
}
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$keep = @('Button','Edit','MenuItem','ListItem','TabItem','Hyperlink','CheckBox','RadioButton','ComboBox','TreeItem','DataItem','Text','Document')
$rows = New-Object System.Collections.Generic.List[string]
$i = 0
foreach ($el in $all) {
  if ($i -ge 200) { break }
  try {
    if ($el.Current.IsOffscreen) { continue }
    $name = $el.Current.Name
    if ([string]::IsNullOrWhiteSpace($name)) { continue }
    $type = ($el.Current.ControlType.ProgrammaticName -replace 'ControlType\.','')
    if ($keep -notcontains $type) { continue }
    $rect = $el.Current.BoundingRectangle
    if ($rect.Width -le 0 -or $rect.Height -le 0) { continue }
    $x = [int]$rect.X
    $y = [int]$rect.Y
    $w = [int]$rect.Width
    $h = [int]$rect.Height
    if ($x -ge $bounds.Width -or $y -ge $bounds.Height) { continue }
    $n = ($name -replace "[\r\n]", ' ') -replace '"', ''
    if ($n.Length -gt 60) { $n = $n.Substring(0, 60) }
    $rows.Add("$i $type `"$n`" ($x,$y ${w}x${h})")
    $i++
  } catch {}
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("SCREEN $($bounds.Width)x$($bounds.Height) window `"$winTitle`"")
foreach ($row in $rows) { [void]$sb.AppendLine($row) }
$sb.ToString()
''';
    final full = arg.trim().toLowerCase() == 'all';
    final out = await _runWindowsPs(
      script.replaceFirst('@@FULL@@', full ? r'$true' : r'$false'),
    );
    if (out.startsWith('[错误]')) return out;
    final lines = out.split('\n').toList();
    final header = lines.isNotEmpty && lines.first.startsWith('SCREEN')
        ? lines.removeAt(0)
        : '';
    final coord = RegExp(r'\((\d+),(\d+)');
    lines.sort((a, b) {
      final ma = coord.firstMatch(a);
      final mb = coord.firstMatch(b);
      if (ma == null || mb == null) return 0;
      final ay = int.parse(ma.group(2)!);
      final by = int.parse(mb.group(2)!);
      if (ay != by) return ay.compareTo(by);
      return int.parse(ma.group(1)!).compareTo(int.parse(mb.group(1)!));
    });
    final body = lines.where((l) => l.trim().isNotEmpty).take(200).join('\n');
    return body.isEmpty ? '[错误] 桌面扫描无输出' : '$header\n$body';
  }

  static Future<String> _windowsClick(String arg) async {
    final m = RegExp(r'^\s*(\d+)\s*[,，]\s*(\d+)\s*$').firstMatch(arg.trim());
    if (m == null) return '[错误] desktop_click 参数应为 "x,y"';
    final x = int.parse(m.group(1)!);
    final y = int.parse(m.group(2)!);
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AuMouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
[AuMouse]::SetCursorPos($x, $y)
Start-Sleep -Milliseconds 80
[AuMouse]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
Start-Sleep -Milliseconds 50
[AuMouse]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
''';
    final out = await _runWindowsPs(script);
    return out.startsWith('[错误]') ? out : '[ok] clicked ($x,$y)';
  }

  static Future<String> _windowsType(String arg) async {
    final b64 = base64Encode(utf8.encode(arg));
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$bytes = [Convert]::FromBase64String('$b64')
\$text = [System.Text.Encoding]::UTF8.GetString(\$bytes)
try {
  [System.Windows.Forms.Clipboard]::SetText(\$text)
} catch {
  Write-Error \$_.Exception.Message
  exit 1
}
Start-Sleep -Milliseconds 120
[System.Windows.Forms.SendKeys]::SendWait('^v')
Start-Sleep -Milliseconds 100
''';
    final out = await _runWindowsPs(script);
    return out.startsWith('[错误]') ? out : '[ok] typed ${arg.length} chars';
  }

  static Future<String> _windowsKey(String arg) async {
    final b64 = base64Encode(utf8.encode(arg));
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$keys = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))
[System.Windows.Forms.SendKeys]::SendWait(\$keys)
Start-Sleep -Milliseconds 100
''';
    final out = await _runWindowsPs(script);
    return out.startsWith('[错误]') ? out : '[ok] key $arg';
  }

  static Future<String> _windowsOpen(String arg) async {
    final b64 = base64Encode(utf8.encode(arg.trim()));
    final script = '''
\$target = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64'))
Start-Process -FilePath \$target
''';
    final out = await _runWindowsPs(script);
    return out.startsWith('[错误]') ? out : '[ok] opened $arg';
  }

  static Future<String> _windowsScroll(String arg) async {
    final m = RegExp(
      r'^\s*(\d+)\s*[,，]\s*(\d+)\s*[,，]\s*(-?\d+)\s*$',
    ).firstMatch(arg.trim());
    if (m == null) return '[错误] desktop_scroll 参数应为 "x,y,delta"';
    final x = int.parse(m.group(1)!);
    final y = int.parse(m.group(2)!);
    final delta = int.parse(m.group(3)!);
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AuWheel {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);
}
"@
[AuWheel]::SetCursorPos($x, $y)
Start-Sleep -Milliseconds 60
\$d = [uint32]($delta -band 0xFFFFFFFF)
[AuWheel]::mouse_event(0x0800, 0, 0, \$d, [UIntPtr]::Zero)
''';
    final out = await _runWindowsPs(script);
    return out.startsWith('[错误]') ? out : '[ok] scrolled ($x,$y,$delta)';
  }

  static Future<String> _windowsWait(String arg) async {
    final n = int.tryParse(arg.trim());
    if (n == null) return '[错误] desktop_wait 参数应为毫秒数字';
    final ms = n.clamp(0, 10000);
    final out = await _runWindowsPs('Start-Sleep -Milliseconds $ms');
    return out.startsWith('[错误]') ? out : '[ok] waited ${ms}ms';
  }

  static Future<String> _windowsCapture(String file) async {
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
\$bmp = New-Object System.Drawing.Bitmap \$bounds.Width, \$bounds.Height
\$g = [System.Drawing.Graphics]::FromImage(\$bmp)
\$g.CopyFromScreen(\$bounds.Location, [System.Drawing.Point]::Empty, \$bounds.Size)
\$bmp.Save('$file', [System.Drawing.Imaging.ImageFormat]::Png)
\$g.Dispose()
\$bmp.Dispose()
''';
    final out = await _runWindowsPs(script);
    return out.startsWith('[错误]') ? out : file;
  }

  static Future<String> _windowsOcr() async {
    final tmp = File(
      '${Directory.systemTemp.path}/auwki_ocr_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    try {
      final shot = await _windowsCapture(tmp.path);
      if (shot.startsWith('[错误]')) return shot;
      final script = '''
Add-Type -AssemblyName System.Runtime.WindowsRuntime
\$null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
\$null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics,ContentType=WindowsRuntime]
\$null = [Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
\$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { \$_.Name -eq 'AsTask' -and \$_.GetParameters().Count -eq 1 -and \$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
function Await(\$WinRtTask, \$ResultType) {
  \$asTask = \$asTaskGeneric.MakeGenericMethod(\$ResultType)
  \$netTask = \$asTask.Invoke(\$null, @(\$WinRtTask))
  \$netTask.Wait(-1) | Out-Null
  \$netTask.Result
}
\$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync('${tmp.path}')) ([Windows.Storage.StorageFile])
\$stream = Await (\$file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
\$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync(\$stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
\$bitmap = Await (\$decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
\$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
if (\$null -eq \$engine) {
  Write-Error 'No OCR language pack installed'
  exit 1
}
\$result = Await (\$engine.RecognizeAsync(\$bitmap)) ([Windows.Media.Ocr.OcrResult])
\$sb = New-Object System.Text.StringBuilder
\$i = 0
foreach (\$line in \$result.Lines) {
  if (\$i -ge 200) { break }
  \$txt = (\$line.Text -replace "[\r\n]", ' ') -replace '"', ''
  if ([string]::IsNullOrWhiteSpace(\$txt)) { continue }
  if (\$txt.Length -gt 60) { \$txt = \$txt.Substring(0, 60) }
  \$minX = 1e9; \$minY = 1e9; \$maxX = 0; \$maxY = 0
  foreach (\$w in \$line.Words) {
    \$r = \$w.BoundingRect
    if (\$r.X -lt \$minX) { \$minX = \$r.X }
    if (\$r.Y -lt \$minY) { \$minY = \$r.Y }
    \$rx = \$r.X + \$r.Width
    \$ry = \$r.Y + \$r.Height
    if (\$rx -gt \$maxX) { \$maxX = \$rx }
    if (\$ry -gt \$maxY) { \$maxY = \$ry }
  }
  [void]\$sb.AppendLine("\$i ocr `"\$txt`" (\$([int]\$minX),\$([int]\$minY) \$([int](\$maxX-\$minX))x\$([int](\$maxY-\$minY)))")
  \$i++
}
[void]\$sb.AppendLine("SCREEN OCR")
\$sb.ToString()
''';
      final out = await _runWindowsPs(script);
      if (out.startsWith('[错误]')) return out;
      final lines = out
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(201)
          .toList();
      return lines.isEmpty ? '[错误] OCR 无结果' : lines.join('\n');
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  // ───────────────────────── macOS ─────────────────────────

  static Future<String> _macos(String tool, String arg) async {
    switch (tool) {
      case 'desktop_dump':
        return _macosDump();
      case 'desktop_click':
        return _macosClick(arg);
      case 'desktop_type':
        return _macosType(arg);
      case 'desktop_key':
        return _macosKey(arg);
      case 'desktop_open':
        return _macosOpen(arg);
      case 'desktop_scroll':
        return _macosScroll(arg);
      case 'desktop_wait':
        return _macosWait(arg);
      case 'desktop_ocr':
        return _macosOcr();
      default:
        return I18n.t('agent.error.platform_unsupported', {'tool': tool});
    }
  }

  static Future<String> _osascript(String script) async {
    try {
      final r = await Process.run('osascript', ['-e', script]);
      if (r.exitCode != 0) {
        return '[错误] 桌面操作失败（需在 系统设置→隐私与安全性→辅助功能 授权）\n${r.stderr}';
      }
      return (r.stdout as String).trim();
    } catch (e) {
      return '[错误] 桌面操作失败\n$e';
    }
  }

  static Future<String> _macosDump() async {
    const script = '''
tell application "System Events"
  set out to ""
  set n to 0
  repeat with p in (every process whose background only is false)
    try
      repeat with w in windows of p
        try
          set entries to entire contents of w
          repeat with e in entries
            if n > 199 then exit repeat
            try
              set r to role of e
              set d to description of e
              if d is not missing value and (count of d) > 0 then
                set pos to position of e
                set sz to size of e
                set out to out & n & " " & r & " [" & d & "] (" & (item 1 of pos) & "," & (item 2 of pos) & " " & (item 1 of sz) & "x" & (item 2 of sz) & ")" & linefeed
                set n to n + 1
              end if
            end try
          end repeat
        end try
      end repeat
    end try
  end repeat
  return out
end tell
''';
    final out = await _osascript(script);
    if (out.startsWith('[错误]')) return out;
    final lines = out
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(200)
        .toList();
    return lines.isEmpty ? '[错误] 桌面扫描无输出' : 'SCREEN macOS\n${lines.join('\n')}';
  }

  static Future<String> _macosClick(String arg) async {
    final m = RegExp(r'^\s*(\d+)\s*[,，]\s*(\d+)\s*$').firstMatch(arg.trim());
    if (m == null) return '[错误] desktop_click 参数应为 "x,y"';
    final x = int.parse(m.group(1)!);
    final y = int.parse(m.group(2)!);
    final out = await _osascript(
      'tell application "System Events" to click at {$x, $y}',
    );
    return out.startsWith('[错误]') ? out : '[ok] clicked ($x,$y)';
  }

  static Future<String> _macosType(String arg) async {
    final b64 = base64Encode(utf8.encode(arg));
    final script = '''
set txt to do shell script "echo $b64 | base64 --decode"
set the clipboard to txt
tell application "System Events" to keystroke "v" using command down
''';
    final out = await _osascript(script);
    return out.startsWith('[错误]') ? out : '[ok] typed ${arg.length} chars';
  }

  static Future<String> _macosKey(String arg) async {
    final key = arg.trim().toLowerCase();
    const codes = <String, int>{
      'enter': 36, 'return': 36, 'tab': 48, 'escape': 53, 'esc': 53,
      'space': 49, 'up': 126, 'down': 125, 'left': 123, 'right': 124,
      'pageup': 116, 'pagedown': 121, 'home': 115, 'end': 119,
      'delete': 117, 'backspace': 51,
    };
    final simple = codes[key];
    if (simple != null) {
      final out = await _osascript(
        'tell application "System Events" to key code $simple',
      );
      return out.startsWith('[错误]') ? out : '[ok] key $arg';
    }
    // 组合键：cmd+c / ctrl+shift+s / option+tab ...
    final parts = key.split('+');
    final mods = <String>[];
    String? letter;
    for (final p in parts) {
      switch (p) {
        case 'cmd' || 'command':
          mods.add('command down');
        case 'ctrl' || 'control':
          mods.add('control down');
        case 'alt' || 'option':
          mods.add('option down');
        case 'shift':
          mods.add('shift down');
        default:
          letter = p;
      }
    }
    if (letter == null || mods.isEmpty) {
      return '[错误] 不支持的按键：$arg（可用 enter/tab/escape/space/up/down/left/right 或 cmd+c 等组合）';
    }
    final out = await _osascript(
      'tell application "System Events" to keystroke "$letter" using {${mods.join(', ')}}',
    );
    return out.startsWith('[错误]') ? out : '[ok] key $arg';
  }

  static Future<String> _macosOpen(String arg) async {
    final b64 = base64Encode(utf8.encode(arg.trim()));
    final script = '''
set t to do shell script "echo $b64 | base64 --decode"
do shell script "open " & quoted form of t
''';
    final out = await _osascript(script);
    return out.startsWith('[错误]') ? out : '[ok] opened $arg';
  }

  static Future<String> _macosScroll(String arg) async {
    final m = RegExp(
      r'^\s*(\d+)\s*[,，]\s*(\d+)\s*[,，]\s*(-?\d+)\s*$',
    ).firstMatch(arg.trim());
    if (m == null) return '[错误] desktop_scroll 参数应为 "x,y,delta"';
    final delta = int.parse(m.group(3)!);
    final code = delta >= 0 ? 121 : 116; // PageDown / PageUp
    final out = await _osascript(
      'tell application "System Events" to key code $code',
    );
    return out.startsWith('[错误]') ? out : '[ok] scrolled $delta';
  }

  static Future<String> _macosWait(String arg) async {
    final n = int.tryParse(arg.trim());
    if (n == null) return '[错误] desktop_wait 参数应为毫秒数字';
    final ms = n.clamp(0, 10000);
    final sec = (ms / 1000).toStringAsFixed(3);
    final out = await _osascript('do shell script "sleep $sec"');
    return out.startsWith('[错误]') ? out : '[ok] waited ${ms}ms';
  }

  static Future<String> _macosOcr() async {
    final tmp = File(
      '${Directory.systemTemp.path}/auwki_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    try {
      final shot = await Process.run('screencapture', ['-x', tmp.path]);
      if (shot.exitCode != 0) return '[错误] 截屏失败\n${shot.stderr}';
      final r = await Process.run('tesseract', [tmp.path, 'stdout', 'tsv']);
      if (r.exitCode != 0) {
        return '[错误] OCR 失败：请先安装 tesseract（brew install tesseract）';
      }
      final lines = _parseTesseractTsv((r.stdout as String).trim());
      return lines.isEmpty
          ? '[错误] OCR 无结果'
          : 'SCREEN OCR macOS\n${lines.join('\n')}';
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  // ───────────────────────── Linux ─────────────────────────

  static Future<String> _linux(String tool, String arg) async {
    switch (tool) {
      case 'desktop_dump':
        return _linuxDump();
      case 'desktop_click':
        return _linuxClick(arg);
      case 'desktop_type':
        return _linuxType(arg);
      case 'desktop_key':
        return _linuxKey(arg);
      case 'desktop_open':
        return _linuxOpen(arg);
      case 'desktop_scroll':
        return _linuxScroll(arg);
      case 'desktop_wait':
        return _linuxWait(arg);
      case 'desktop_ocr':
        return _linuxOcr();
      default:
        return I18n.t('agent.error.platform_unsupported', {'tool': tool});
    }
  }

  static Future<String> _runSh(String script) async {
    try {
      final r = await Process.run('/bin/sh', ['-c', script]);
      if (r.exitCode != 0) {
        return '[错误] 桌面操作失败\n${r.stderr}';
      }
      return (r.stdout as String).trim();
    } catch (e) {
      return '[错误] 桌面操作失败\n$e';
    }
  }

  static Future<String> _linuxDump() async {
    final py = '''
import sys
try:
    import pyatspi
except Exception:
    print("[错误] 需要安装 python3-pyatspi（GNOME/KDE 辅助功能栈）")
    sys.exit(1)
out = []
try:
    desktop = pyatspi.Registry.getDesktop(0)
    def walk(node, depth):
        if len(out) >= 200:
            return
        try:
            name = (node.name or "").strip()
            role = node.getRoleName()
            ext = node.getExtents(0)
            if name and ext.width > 0 and ext.height > 0:
                out.append(f'{len(out)} {role} [{name[:60]}] ({int(ext.x)},{int(ext.y)} {int(ext.width)}x{int(ext.height)})')
            for i in range(node.getChildCount()):
                walk(node.getChildAtIndex(i), depth + 1)
        except Exception:
            pass
    for i in range(desktop.getChildCount()):
        walk(desktop.getChildAtIndex(i), 0)
except Exception as e:
    print("[错误] AT-SPI 扫描失败: %s" % e)
    sys.exit(1)
print("SCREEN linux")
print("\\n".join(out))
''';
    final tmp = File(
      '${Directory.systemTemp.path}/auwki_desktop_dump_${DateTime.now().microsecondsSinceEpoch}.py',
    );
    try {
      await tmp.writeAsString(py);
      final r = await Process.run('python3', [tmp.path]);
      if (r.exitCode != 0) {
        return '${r.stdout}\n${r.stderr}'.trim();
      }
      return (r.stdout as String).trim();
    } catch (e) {
      return '[错误] 桌面扫描失败\n$e';
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  static Future<String> _linuxClick(String arg) async {
    final m = RegExp(r'^\s*(\d+)\s*[,，]\s*(\d+)\s*$').firstMatch(arg.trim());
    if (m == null) return '[错误] desktop_click 参数应为 "x,y"';
    final x = int.parse(m.group(1)!);
    final y = int.parse(m.group(2)!);
    final out = await _runSh('xdotool mousemove $x $y click 1');
    return out.startsWith('[错误]') ? out : '[ok] clicked ($x,$y)';
  }

  static Future<String> _linuxType(String arg) async {
    final b64 = base64Encode(utf8.encode(arg));
    final out = await _runSh(
      'TXT=\$(echo $b64 | base64 -d); xdotool type --delay 50 "\$TXT"',
    );
    return out.startsWith('[错误]') ? out : '[ok] typed ${arg.length} chars';
  }

  static Future<String> _linuxKey(String arg) async {
    final b64 = base64Encode(utf8.encode(arg));
    final out = await _runSh(
      'KEY=\$(echo $b64 | base64 -d); xdotool key --clearmodifiers "\$KEY"',
    );
    return out.startsWith('[错误]') ? out : '[ok] key $arg';
  }

  static Future<String> _linuxOpen(String arg) async {
    final b64 = base64Encode(utf8.encode(arg.trim()));
    final out = await _runSh(
      'T=\$(echo $b64 | base64 -d); xdg-open "\$T"',
    );
    return out.startsWith('[错误]') ? out : '[ok] opened $arg';
  }

  static Future<String> _linuxScroll(String arg) async {
    final m = RegExp(
      r'^\s*(\d+)\s*[,，]\s*(\d+)\s*[,，]\s*(-?\d+)\s*$',
    ).firstMatch(arg.trim());
    if (m == null) return '[错误] desktop_scroll 参数应为 "x,y,delta"';
    final x = int.parse(m.group(1)!);
    final y = int.parse(m.group(2)!);
    final delta = int.parse(m.group(3)!);
    final btn = delta >= 0 ? 4 : 5;
    final out = await _runSh('xdotool mousemove $x $y click $btn');
    return out.startsWith('[错误]') ? out : '[ok] scrolled ($x,$y,$delta)';
  }

  static Future<String> _linuxWait(String arg) async {
    final n = int.tryParse(arg.trim());
    if (n == null) return '[错误] desktop_wait 参数应为毫秒数字';
    final ms = n.clamp(0, 10000);
    final sec = (ms / 1000).toStringAsFixed(3);
    final out = await _runSh('sleep $sec');
    return out.startsWith('[错误]') ? out : '[ok] waited ${ms}ms';
  }

  static Future<String> _linuxCapture(String file) async {
    for (final cmd in [
      'import -window root "$file"',
      'scrot -z "$file"',
      'gnome-screenshot -f "$file"',
    ]) {
      final r = await Process.run('/bin/sh', ['-c', cmd]);
      if (r.exitCode == 0 && File(file).existsSync()) return file;
    }
    return '[错误] 无法截屏（需要 imagemagick / scrot / gnome-screenshot）';
  }

  static Future<String> _linuxOcr() async {
    final tmp = File(
      '${Directory.systemTemp.path}/auwki_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    try {
      final shot = await _linuxCapture(tmp.path);
      if (shot.startsWith('[错误]')) return shot;
      final r = await Process.run('tesseract', [tmp.path, 'stdout', 'tsv']);
      if (r.exitCode != 0) {
        return '[错误] OCR 失败：请先安装 tesseract-ocr';
      }
      final lines = _parseTesseractTsv((r.stdout as String).trim());
      return lines.isEmpty
          ? '[错误] OCR 无结果'
          : 'SCREEN OCR linux\n${lines.join('\n')}';
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  /// 解析 tesseract TSV 输出为与 desktop_dump 一致的文本地图。
  static List<String> _parseTesseractTsv(String out) {
    final rows = out.split('\n');
    final lines = <String>[];
    for (final row in rows) {
      if (lines.length >= 200) break;
      final cols = row.split('\t');
      if (cols.length < 12 || cols[0] != '5') continue;
      final text = cols[11].trim();
      if (text.isEmpty) continue;
      lines.add(
        '${lines.length} ocr "$text" (${cols[6]},${cols[7]} ${cols[8]}x${cols[9]})',
      );
    }
    return lines;
  }
}
