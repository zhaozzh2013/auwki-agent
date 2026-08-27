import 'package:flutter/widgets.dart';

import 'strings_en.dart';
import 'strings_ja.dart';
import 'strings_zh.dart';

class I18n {
  I18n._();

  static final ValueNotifier<Locale> locale = ValueNotifier(
    const Locale('zh', 'CN'),
  );

  static const Map<String, Map<String, String>> _strings = {
    'zh_CN': kStringsZh,
    'en_US': kStringsEn,
    'ja_JP': kStringsJa,
  };

  static String t(String key, [Map<String, String>? params]) {
    final loc = '${locale.value.languageCode}_${locale.value.countryCode}';
    final map = _strings[loc] ?? _strings['zh_CN']!;
    var s = map[key] ?? _strings['en_US']![key] ?? key;
    if (params != null) {
      params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    }
    return s;
  }
}
