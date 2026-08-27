import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/diff_preview.dart';

void main() {
  test('A06: unified diff marks added and removed lines', () {
    final d = DiffPreview.unified(
      'a\nb\nc',
      'a\nB\nc\nd',
      path: 'x.txt',
    );
    expect(d, contains('--- x.txt'));
    expect(d, contains('+ B'));
    expect(d, contains('- b'));
    expect(d, contains('+ d'));
  });

  test('A06: new file preview shows only additions', () {
    final d = DiffPreview.unified(null, 'hello\nworld');
    expect(d, contains('+ hello'));
    expect(d, contains('+ world'));
  });

  test('A06: large files degrade to summary', () {
    final old = List.generate(600, (i) => 'line$i').join('\n');
    final d = DiffPreview.unified(old, old);
    expect(d, contains('600 -> 600'));
  });
}
