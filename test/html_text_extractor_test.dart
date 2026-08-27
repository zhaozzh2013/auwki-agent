import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/html_text_extractor.dart';

void main() {
  test('A09: strips nav/scripts and returns body text', () {
    const html = '''
<html><head><title>T</title><script>var x=1;</script></head>
<body><nav>导航链接</nav><h1>标题</h1><p>正文内容 &amp; 更多</p>
<footer>页脚</footer></body></html>
''';
    final text = HtmlTextExtractor.extract(html);
    expect(text, contains('标题'));
    expect(text, contains('正文内容 & 更多'));
    expect(text, isNot(contains('导航链接')));
    expect(text, isNot(contains('页脚')));
    expect(text, isNot(contains('var x')));
  });

  test('A09: decodes numeric entities', () {
    expect(HtmlTextExtractor.extract('<p>&#65;&#66;</p>'), 'AB');
  });
}
