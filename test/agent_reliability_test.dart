import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/i18n/strings.dart';
import 'package:auwki_agent/services/agent.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('agent_reliability_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  AgentToolCall call(String tool, String args) =>
      AgentToolCall(tool: tool, args: args);

  test('replacefile 精确匹配', () async {
    final f = File('${tmp.path}/a.txt')
      ..writeAsStringSync('hello\nworld\n');
    final r = await AgentRunner.execute(
      call('replacefile', 'a.txt|||world|||AUWKI'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue);
    expect(f.readAsStringSync(), 'hello\nAUWKI\n');
  });

  test('replacefile 容忍 \\r\\n 与 \\n 混用', () async {
    final f = File('${tmp.path}/a.txt')
      ..writeAsStringSync('line1\r\nline2\r\nline3\r\n');
    final r = await AgentRunner.execute(
      call('replacefile', 'a.txt|||line2|||CHANGED'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(f.readAsStringSync(), 'line1\r\nCHANGED\r\nline3\r\n');
  });

  test('replacefile 容忍行首空白差异并保留缩进', () async {
    final f = File('${tmp.path}/a.txt')
      ..writeAsStringSync('  foo\n  bar\n  baz\n');
    // 模型拿到的 old 文本没有缩进，也能匹配成功，且首行缩进保留。
    final r = await AgentRunner.execute(
      call('replacefile', 'a.txt|||bar|||BAR'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(f.readAsStringSync(), '  foo\n  BAR\n  baz\n');
  });

  test('replacefile 找不到时返回错误且不修改文件', () async {
    final f = File('${tmp.path}/a.txt')..writeAsStringSync('abc');
    final r = await AgentRunner.execute(
      call('replacefile', 'a.txt|||xyz|||qwe'),
      cwd: tmp.path,
    );
    expect(
      r.output,
      I18n.t('agent.error.replace_missing', {
        'path': f.path.replaceAll('\\', '/'),
      }),
    );
    expect(f.readAsStringSync(), 'abc');
  });

  test('writefile 默认拒绝覆盖已存在文件', () async {
    File('${tmp.path}/a.txt').writeAsStringSync('old');
    final r = await AgentRunner.execute(
      call('writefile', 'a.txt|||new'),
      cwd: tmp.path,
    );
    expect(
      r.output,
      I18n.t('agent.error.file_exists', {
        'path': '${tmp.path}/a.txt'.replaceAll('\\', '/'),
      }),
    );
    expect(File('${tmp.path}/a.txt').readAsStringSync(), 'old');
  });

  test('writefile 带 overwrite 参数可覆盖', () async {
    File('${tmp.path}/a.txt').writeAsStringSync('old');
    final r = await AgentRunner.execute(
      call('writefile', 'a.txt|||new|||overwrite'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(File('${tmp.path}/a.txt').readAsStringSync(), 'new');
  });

  test('writefile overwrite 参数大小写不敏感', () async {
    File('${tmp.path}/a.txt').writeAsStringSync('old');
    final r = await AgentRunner.execute(
      call('writefile', 'a.txt|||new|||Overwrite'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(File('${tmp.path}/a.txt').readAsStringSync(), 'new');
  });

  test('解析：容忍行首列表符号与工具名大小写', () {
    final calls = AgentRunner.parse('''
[正式输出]
- Webfetch("https://example.com")
* ListFiles(".")
WeBSEARCH("关键词")
[输出结束]
''');
    expect(
      calls.map((c) => c.tool).toList(),
      ['webfetch', 'listfiles', 'websearch'],
    );
  });

  test('listfiles 输出相对路径', () async {
    Directory('${tmp.path}/sub').createSync();
    File('${tmp.path}/sub/x.txt').writeAsStringSync('x');
    final r = await AgentRunner.execute(
      call('listfiles', '.'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(r.output, contains('sub/'));
    expect(r.output, isNot(contains('${tmp.path}/sub')));
  });

  test('F09：写入含勒索模式的脚本被拦截', () async {
    final r = await AgentRunner.execute(
      call(
        'writefile',
        'evil.ps1|||'
            'foreach (\$f in Get-ChildItem) { '
            'Rename-Item \$f (\$f.Name + ".encrypted") }\n'
            'Write-Host "send bitcoin to wallet to decrypt"',
      ),
      cwd: tmp.path,
    );
    expect(
      r.output,
      contains(I18n.t('agent.error.content_blocked')),
    );
    expect(File('${tmp.path}/evil.ps1').existsSync(), isFalse);
  });

  test('F09：键盘记录钩子代码被拦截', () async {
    final r = await AgentRunner.execute(
      call(
        'writefile',
        'keylog.py|||'
            'import ctypes\n'
            'hook = ctypes.WINFUNCTYPE(ctypes.c_long, ctypes.c_int, ctypes.c_int, ctypes.POINTER(ctypes.c_void_p))(\n'
            '    lambda code, wparam, lparam: 0)\n'
            'ctypes.windll.user32.SetWindowsHookExW(13, hook, None, 0)  # WH_KEYBOARD_LL',
      ),
      cwd: tmp.path,
    );
    expect(r.output, contains(I18n.t('agent.error.content_blocked')));
  });

  test('F09：正常代码不被拦截', () async {
    final r = await AgentRunner.execute(
      call(
        'writefile',
        'normal.py|||print("hello world")\nfor i in range(10):\n    print(i)',
      ),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue, reason: r.output);
    expect(File('${tmp.path}/normal.py').existsSync(), isTrue);
  });
}
