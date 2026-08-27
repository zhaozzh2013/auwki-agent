/// 网页正文提取（A09）：去脚本/样式/导航/页脚后返回纯文本。
class HtmlTextExtractor {
  HtmlTextExtractor._();

  static final List<RegExp> _stripBlocks = [
    RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
    RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
    RegExp(r'<nav[\s\S]*?</nav>', caseSensitive: false),
    RegExp(r'<footer[\s\S]*?</footer>', caseSensitive: false),
    RegExp(r'<header[\s\S]*?</header>', caseSensitive: false),
    RegExp(r'<!--[\s\S]*?-->'),
    RegExp(r'<svg[\s\S]*?</svg>', caseSensitive: false),
  ];

  static String extract(String html) {
    var s = html;
    for (final re in _stripBlocks) {
      s = s.replaceAll(re, ' ');
    }
    // 标题/段落边界换行。
    s = s.replaceAll(
      RegExp(r'</(h[1-6]|p|div|li|tr|br)>', caseSensitive: false),
      '\n',
    );
    s = s.replaceAll(RegExp(r'<[^>]+>'), ' ');
    s = _decodeEntities(s);
    s = s.replaceAll(RegExp(r'[ \t]+'), ' ');
    s = s.replaceAll(RegExp(r'\n\s*\n+'), '\n\n');
    return s.trim();
  }

  static String _decodeEntities(String s) {
    final map = <String, String>{
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&hellip;': '...',
      '&mdash;': '-',
      '&ndash;': '-',
      '&copy;': '(c)',
      '&reg;': '(r)',
    };
    var out = s;
    map.forEach((k, v) => out = out.replaceAll(k, v));
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (Match m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code == null ? '' : String.fromCharCode(code);
    });
    return out;
  }
}
