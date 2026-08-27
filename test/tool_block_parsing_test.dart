import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/agent.dart';

String _cssSample() => '''
@font-face {
  font-family: "Inter";
  src: url("Inter.woff2") format("woff2");
}
body {
  font-family: "Inter", sans-serif;
  background: linear-gradient(90deg, #111 0%, #222 100%);
  content: "→";
}
@media (max-width: 600px) {
  .a::before { content: ")" ; }
}
''';

void main() {
  test('CSS 长内容含引号/括号/换行可完整解析', () {
    final css = _cssSample();
    final block = '[正式输出]\nwritefile("css/style.css|||$css")\n[输出结束]';
    final calls = AgentRunner.parse(block);
    expect(calls.length, 1, reason: '工具块应解析出 1 个调用');
    expect(calls.first.tool, 'writefile');
    expect(calls.first.args, contains('css/style.css|||'));
    // 若解析器在 url("...") 或 content: ")" 处提前截断，这里会失败。
    expect(calls.first.args, contains('format("woff2")'));
    expect(calls.first.args, contains('content: ")"'));
    expect(calls.first.args.trim(), endsWith('}'));
  });

  test('内容含 ||| 也能写入完整文本', () async {
    final tmp = Directory.systemTemp.createTempSync('auwki_parse_pp');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final r = await AgentRunner.execute(
      AgentToolCall(tool: 'writefile', args: 'a.txt|||line1|||line2'),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue);
    expect(File('${tmp.path}/a.txt').readAsStringSync(), 'line1|||line2');
  });

  test('writefile overwrite 标志不会被内容里的 ||| 干扰', () async {
    final tmp = Directory.systemTemp.createTempSync('auwki_parse_ow');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final f = File('${tmp.path}/x.txt')..writeAsStringSync('old');
    final r = await AgentRunner.execute(
      AgentToolCall(
        tool: 'writefile',
        args: 'x.txt|||a|||b|||overwrite',
      ),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue);
    expect(f.readAsStringSync(), 'a|||b');
  });

  test('base64 内容可解码写入', () async {
    final tmp = Directory.systemTemp.createTempSync('auwki_parse_b64');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final css = _cssSample();
    final encoded = base64Encode(utf8.encode(css));
    final r = await AgentRunner.execute(
      AgentToolCall(
        tool: 'writefile',
        args: 'style.css|||base64:$encoded',
      ),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue);
    expect(File('${tmp.path}/style.css').readAsStringSync(), css);
  });

  test('replacefile 含引号/换行内容可执行', () async {
    final tmp = Directory.systemTemp.createTempSync('auwki_parse_rp');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final f = File('${tmp.path}/r.txt')
      ..writeAsStringSync('old "quoted"\nline');
    final r = await AgentRunner.execute(
      AgentToolCall(
        tool: 'replacefile',
        args: 'r.txt|||old "quoted"\nline|||new "quoted"\nline',
      ),
      cwd: tmp.path,
    );
    expect(r.ok, isTrue);
    expect(f.readAsStringSync(), 'new "quoted"\nline');
  });
}
