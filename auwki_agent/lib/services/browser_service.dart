import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_windows/webview_windows.dart';

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

/// 一个独立的内置浏览器窗口（每个会话一个 WebView2 实例）。
class BrowserSession extends ChangeNotifier {
  BrowserSession({required this.id, required this.controller});

  final String id;
  final WebviewController controller;

  String url = '';
  String title = '';
  bool loading = false;
  bool canGoBack = false;
  bool canGoForward = false;
  String? loadError;

  final List<StreamSubscription<dynamic>> _subs = [];
  bool _disposed = false;

  Future<void> attach() async {
    _subs.add(
      controller.url.listen((u) {
        url = u;
        loadError = null;
        notifyListeners();
      }),
    );
    _subs.add(
      controller.title.listen((t) {
        title = t;
        notifyListeners();
      }),
    );
    _subs.add(
      controller.loadingState.listen((s) {
        loading = s == LoadingState.loading;
        notifyListeners();
      }),
    );
    _subs.add(
      controller.historyChanged.listen((h) {
        canGoBack = h.canGoBack;
        canGoForward = h.canGoForward;
        notifyListeners();
      }),
    );
    _subs.add(
      controller.onLoadError.listen((e) {
        loadError = e.name;
        notifyListeners();
      }),
    );
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
    try {
      await controller.dispose();
    } catch (_) {}
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

  Future<void>? _envLock;
  String? _envError;
  int _counter = 0;

  List<BrowserSession> get sessions => List.unmodifiable(_sessions);

  String? get environmentError => _envError;

  /// 初始化 WebView2 环境（整个应用共享一份用户数据目录）。
  Future<String?> ensureEnvironment() {
    final lock = _envLock ??= _initEnvironment();
    return lock.then((_) => _envError);
  }

  Future<void> _initEnvironment() async {
    if (_envError != null) return;
    try {
      final version = await WebviewController.getWebViewVersion();
      if (version == null || version.isEmpty) {
        _envError = 'webview2_missing';
        return;
      }
      final dir = await getApplicationSupportDirectory();
      final profile = '${dir.path}/browser_profile';
      await Directory(profile).create(recursive: true);
      await WebviewController.initializeEnvironment(userDataPath: profile);
    } on PlatformException catch (e) {
      _envError = e.message ?? 'webview2_init_failed';
    } catch (e) {
      _envError = '$e';
    }
  }

  /// 创建新的浏览器窗口（会话）。初始化失败时返回 null。
  Future<BrowserSession?> createSession({String url = homeUrl}) async {
    final err = await ensureEnvironment();
    if (err != null) return null;
    final controller = WebviewController();
    final session = BrowserSession(
      id: 'b${++_counter}',
      controller: controller,
    );
    _sessions.add(session);
    notifyListeners();
    try {
      await controller.initialize();
      await controller.setPopupWindowPolicy(
        WebviewPopupWindowPolicy.sameWindow,
      );
      await controller.setBackgroundColor(const Color(0xFF1E1E1E));
      await session.attach();
      await controller.loadUrl(url);
      session.url = url;
      notifyListeners();
      return session;
    } catch (e) {
      _sessions.remove(session);
      await session.close();
      notifyListeners();
      return null;
    }
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
    s.loadError = null;
    notifyListeners();
    try {
      await s.controller.loadUrl(u);
      await _applyPendingCookies(s, u);
    } catch (_) {}
  }

  Future<void> refresh(BrowserSession s) async {
    try {
      await s.controller.reload();
    } catch (_) {}
  }

  Future<void> stop(BrowserSession s) async {
    try {
      await s.controller.stop();
    } catch (_) {}
  }

  Future<void> goBack(BrowserSession s) async {
    try {
      await s.controller.goBack();
    } catch (_) {}
  }

  Future<void> goForward(BrowserSession s) async {
    try {
      await s.controller.goForward();
    } catch (_) {}
  }

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

  Future<void> _applyPendingCookies(BrowserSession s, String url) async {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null || host.isEmpty) return;
    final matched = <String, List<BrowserCookie>>{};
    for (final entry in _pendingCookies.entries) {
      final domain = entry.key;
      if (host == domain || host.endsWith('.$domain')) {
        matched[domain] = entry.value;
      }
    }
    if (matched.isEmpty) return;
    for (final list in matched.values) {
      for (final c in list) {
        await _injectCookie(s, c);
      }
    }
  }

  Future<void> _injectCookie(BrowserSession s, BrowserCookie c) async {
    try {
      final sb = StringBuffer()
        ..write('${c.name}=${c.value}')
        ..write('; path=${c.path.isEmpty ? '/' : c.path}');
      if (c.secure) sb.write('; secure');
      if (c.expires != null) {
        sb.write('; expires=${c.expires!.toUtc().toIso8601String()}');
      }
      final script = 'document.cookie = ${jsonEncode(sb.toString())};';
      await s.controller.executeScript(script);
    } catch (_) {}
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
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split('\t');
      if (parts.length < 7) continue;
      var domain = parts[0].trim();
      if (domain.toLowerCase().startsWith('#httponly_')) {
        domain = domain.substring(10);
      }
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
    for (final s in _sessions) {
      try {
        await s.controller.clearCookies();
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> clearCache() async {
    for (final s in _sessions) {
      try {
        await s.controller.clearCache();
      } catch (_) {}
    }
  }

  Future<void> setCacheDisabled(bool disabled) async {
    for (final s in _sessions) {
      try {
        await s.controller.setCacheDisabled(disabled);
      } catch (_) {}
    }
  }

  Future<void> openDevTools(BrowserSession s) async {
    try {
      await s.controller.openDevTools();
    } catch (_) {}
  }

  Future<void> setUserAgent(BrowserSession s, String ua) async {
    try {
      await s.controller.setUserAgent(ua);
    } catch (_) {}
  }

  Future<void> setZoom(BrowserSession s, double factor) async {
    try {
      await s.controller.setZoomFactor(factor);
    } catch (_) {}
  }
}
