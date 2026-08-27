import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/browser_service.dart';

/// 外部浏览器模式回归测试：全平台统一走系统浏览器打开，
/// 会话创建/导航/WebView2 专属操作（no-op）均可用。
void main() {
  tearDown(() async {
    for (final s in BrowserService.instance.sessions.toList()) {
      await BrowserService.instance.closeSession(s);
    }
  });

  test('创建浏览器会话且导航可用', () async {
    final s = await BrowserService.instance
        .createSession(url: 'https://example.com');
    expect(s, isNotNull);
    expect(s!.url, 'https://example.com');

    // 导航：规范化 URL 并更新会话状态，不抛异常。
    await BrowserService.instance.navigate(s, 'flutter.dev');
    expect(s.url, 'https://flutter.dev');

    // WebView2 专属操作安全 no-op。
    await BrowserService.instance.goBack(s);
    await BrowserService.instance.goForward(s);
    await BrowserService.instance.setZoom(s, 1.5);
    await BrowserService.instance.setUserAgent(s, 'test');
    await BrowserService.instance.openDevTools(s);
    await BrowserService.instance.clearCache();
    await BrowserService.instance.clearCookies();

    await BrowserService.instance.closeSession(s);
    expect(BrowserService.instance.sessions, isEmpty);
  });

  test('刷新=重新在系统浏览器打开（不抛异常）', () async {
    final s = await BrowserService.instance.createSession();
    expect(s, isNotNull);
    await BrowserService.instance.refresh(s!);
    await BrowserService.instance.stop(s);
    await BrowserService.instance.closeSession(s);
  });
}