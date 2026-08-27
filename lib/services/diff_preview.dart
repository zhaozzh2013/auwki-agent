/// 简单行级 diff 预览（A06）：生成 +/- 文本供确认弹窗展示。
class DiffPreview {
  DiffPreview._();

  /// 基于 LCS 的行级 diff，返回带 +/- 前缀的文本。
  static String unified(String? oldText, String? newText, {String path = ''}) {
    final a = (oldText ?? '').split('\n');
    final b = (newText ?? '').split('\n');
    final buf = StringBuffer();
    if (path.isNotEmpty) {
      buf.writeln('--- $path');
      buf.writeln('+++ $path (new)');
    }
    final m = a.length;
    final n = b.length;
    if (m > 500 || n > 500) {
      // 大文件只给概要，避免弹窗卡顿。
      if (m == 0) {
        buf.writeln('+ ${b.join('\n+ ')}');
      } else if (n == 0) {
        buf.writeln('- ${a.join('\n- ')}');
      } else {
        buf.writeln('... ${a.length} -> ${b.length} lines ...');
      }
      return buf.toString().trimRight();
    }
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        dp[i][j] = a[i - 1] == b[j - 1]
            ? dp[i - 1][j - 1] + 1
            : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
      }
    }
    void walk(int i, int j) {
      if (i == 0 && j == 0) return;
      if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
        walk(i - 1, j - 1);
        buf.writeln('  ${a[i - 1]}');
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        walk(i, j - 1);
        buf.writeln('+ ${b[j - 1]}');
      } else {
        walk(i - 1, j);
        buf.writeln('- ${a[i - 1]}');
      }
    }

    walk(m, n);
    return buf.toString().trimRight();
  }
}
