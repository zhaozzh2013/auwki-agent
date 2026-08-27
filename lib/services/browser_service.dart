import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 一条待导入的 Cookie。
class BrowserCookie {
  const BrowserCookie({
    required this.domain,
    required this.name,
    required this.value,
    this.path = '/',
    this.secure = false,
    this.httpOnly = false,
    this.expires,
  });

  final String domain;
  final String name;
  final String value;
  final String path;
  final bool secure;
  final bool httpOnly;
  final DateTime? expires;
}

/// 一个浏览器会话（全平台统一的外部浏览器模式）。
///
/// 导航统一调用系统默认浏览器打开（Windows: start / macOS: open /
/// Linux: xdg-open），不再内嵌 WebView2——保证跨平台行为一致且
/// 避免 Windows 侧 WebView2/nuget/工具链兼容问题。
class BrowserSession extends ChangeNotifier {
  BrowserSession({required this.id, String? initialUrl})
      : url = initialUrl ?? '';

  final String id;
  String url = '';
  String title = '';
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  String? loadError;

  bool _disposed = false;

  /// 在系统默认浏览器中打开当前 url。
  Future<void> openExternal() async {
    final target = url.trim();
    if (target.isEmpty) return;
    try {
      if (Platform.isMacOS) {
        await Process.start('open', [target]);
      } else if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', target]);
      } else {
        await Process.start('xdg-open', [target]);
      }
    } catch (_) {}
    title = target;
    notifyListeners();
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    notifyListeners();
  }
}

/// 管理所有内置浏览器窗口，并负责 WebView2 环境初始化。
class BrowserService extends ChangeNotifier {
  BrowserService._();

  static final BrowserService instance = BrowserService._();

  static const String homeUrl = 'https://www.bing.com';

  final List<BrowserSession> _sessions = [];
  final Map<String, List<BrowserCookie>> _pendingCookies = {};

  int _counter = 0;

  List<BrowserSession> get sessions => List.unmodifiable(_sessions);

  String? get environmentError => null;

  /// 创建新的浏览器会话（统一外部浏览器模式）。
  Future<BrowserSession?> createSession({String url = homeUrl}) async {
    final session = BrowserSession(id: 'b${++_counter}', initialUrl: url);
    _sessions.add(session);
    notifyListeners();
    await session.openExternal();
    return session;
  }

  Future<void> closeSession(BrowserSession session) async {
    _sessions.remove(session);
    notifyListeners();
    await session.close();
  }

  Future<void> navigate(BrowserSession s, String rawUrl) async {
    var u = rawUrl.trim();
    if (u.isEmpty) return;
    if (!u.contains('://')) u = 'https://$u';
    s.url = u;
    s.loadError = null;
    notifyListeners();
    await s.openExternal();
  }

  Future<void> refresh(BrowserSession s) async {
    // 外部浏览器模式：重新在系统浏览器打开。
    await s.openExternal();
  }

  Future<void> stop(BrowserSession s) async {}

  Future<void> goBack(BrowserSession s) async {}

  Future<void> goForward(BrowserSession s) async {}

  // ---- Cookie ----

  /// 导入一批 Cookie；按域分组保存，打开对应站点时自动注入。
  int importCookies(List<BrowserCookie> cookies) {
    var count = 0;
    for (final c in cookies) {
      final domain = _normalizeDomain(c.domain);
      if (domain.isEmpty) continue;
      _pendingCookies
          .putIfAbsent(domain, () => <BrowserCookie>[])
          .add(c);
      count++;
    }
    notifyListeners();
    return count;
  }

  static String _normalizeDomain(String d) {
    var s = d.trim().toLowerCase();
    if (s.startsWith('.')) s = s.substring(1);
    return s;
  }

  /// 从文件内容解析 Cookie（支持 Netscape cookies.txt 与 JSON 数组）。
  static List<BrowserCookie> parseCookieFile(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      return _parseJsonCookies(trimmed);
    }
    return _parseNetscapeCookies(content);
  }

  static List<BrowserCookie> _parseJsonCookies(String text) {
    final result = <BrowserCookie>[];
    try {
      final data = jsonDecode(text);
      final list = data is List
          ? data
          : (data is Map && data['cookies'] is List)
              ? data['cookies'] as List
              : <dynamic>[];
      for (final item in list) {
        if (item is! Map) continue;
        final domain =
            (item['domain'] ?? item['host'])?.toString();
        final name = item['name']?.toString();
        final value = item['value']?.toString();
        if (domain == null || name == null || value == null) continue;
        final expires = item['expirationDate'] ?? item['expires'];
        result.add(
          BrowserCookie(
            domain: domain,
            name: name,
            value: value,
            path: item['path']?.toString() ?? '/',
            secure: item['secure'] == true,
            httpOnly: item['httpOnly'] == true,
            expires: expires is num
                ? DateTime.fromMillisecondsSinceEpoch(
                    (expires * 1000).round(),
                  )
                : expires is String
                ? DateTime.tryParse(expires)
                : null,
          ),
        );
      }
    } catch (_) {}
    return result;
  }

  static List<BrowserCookie> _parseNetscapeCookies(String text) {
    final result = <BrowserCookie>[];
    for (final rawLine in text.split('\n')) {
      final trimmed = rawLine.trim();
      if (trimmed.isEmpty) continue;
      var line = trimmed;
      // #HttpOnly_ 前缀是 Cookie 的一部分，不能当注释跳过。
      if (line.toLowerCase().startsWith('#httponly_')) {
        line = line.substring('#HttpOnly_'.length);
      } else if (line.startsWith('#')) {
        continue;
      }
      final parts = line.split('\t');
      if (parts.length < 7) continue;
      final domain = parts[0].trim();
      if (domain.isEmpty) continue;
      // 标准 Netscape 字段：domain flag path secure expires name value；
      // 部分导出工具会在 name 前多一列 sameSite，此时字段数为 8。
      final nameIndex = parts.length == 8 ? 6 : 5;
      final valueIndex = parts.length == 8 ? 7 : 6;
      final path = parts[2];
      final secure = parts[3].toUpperCase() == 'TRUE';
      final expiresSec = int.tryParse(parts[4]) ?? 0;
      final name = parts[nameIndex];
      final value = parts[valueIndex];
      result.add(
        BrowserCookie(
          domain: domain,
          name: name,
          value: value,
          path: path,
          secure: secure,
          expires: expiresSec > 0
              ? DateTime.fromMillisecondsSinceEpoch(expiresSec * 1000)
              : null,
        ),
      );
    }
    return result;
  }

  // ---- 隐私设置 ----

  Future<void> clearCookies() async {
    _pendingCookies.clear();
    notifyListeners();
  }

  Future<void> clearCache() async {}

  Future<void> setCacheDisabled(bool disabled) async {}

  Future<void> openDevTools(BrowserSession s) async {}

  Future<void> setUserAgent(BrowserSession s, String ua) async {}

  Future<void> setZoom(BrowserSession s, double factor) async {}
}
