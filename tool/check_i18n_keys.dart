import 'package:auwki_agent/i18n/strings_en.dart';
import 'package:auwki_agent/i18n/strings_ja.dart';
import 'package:auwki_agent/i18n/strings_zh.dart';

void main() {
  final zh = kStringsZh, ja = kStringsJa, en = kStringsEn;
  final missingInJa = zh.keys.where((k) => !ja.containsKey(k)).toList()..sort();
  final missingInEn = zh.keys.where((k) => !en.containsKey(k)).toList()..sort();
  final extraInJa = ja.keys.where((k) => !zh.containsKey(k)).toList()..sort();
  print('zh keys: ${zh.length}, en keys: ${en.length}, ja keys: ${ja.length}');
  print('--- ja 缺失 (zh 有 ja 无): ${missingInJa.length} ---');
  for (final k in missingInJa) {
    print('  $k => ${zh[k]}');
  }
  print('--- en 缺失: ${missingInEn.length} ---');
  for (final k in missingInEn) {
    print('  $k => ${zh[k]}');
  }
  print('--- ja 多余: ${extraInJa.length} ---');
  for (final k in extraInJa) {
    print('  $k => ${ja[k]}');
  }
}
