import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/browser_service.dart';

/// 外部浏览器模式（非 Windows 平台）回归测试。
/// 该测试在 Linux 测试机上运行，Platform.isWindows 为 false，
/// 因此 createSession 必须走外部浏览器模式而不是 WebView2 初始化。
void main() {
  tearDown(() async {
    for (final s in BrowserService.instance.sessions.toList()) {
      await BrowserService.instance.closeSession(s);
    }
  });

  test('非 Windows 平台创建外部浏览器会话且导航可用', () async {
    final s = await BrowserService.instance
        .createSession(url: 'https://example.com');
    expect(s, isNotNull);
    expect(s!.isExternal, isTrue,
        reason: '非 Windows 平台必须是外部浏览器模式');
    expect(s.url, 'https://example.com');
    expect(s.controller, isNull);

    // 导航：规范化 URL 并更新会话状态，不抛异常。
    await BrowserService.instance.navigate(s, 'flutter.dev');
    expect(s.url, 'https://flutter.dev');

    // WebView2 专属操作在外部模式下安全 no-op。
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

  test('外部模式刷新=重新在系统浏览器打开（不抛异常）', () async {
    final s = await BrowserService.instance.createSession();
    expect(s!.isExternal, isTrue);
    await BrowserService.instance.refresh(s);
    await BrowserService.instance.stop(s);
    await BrowserService.instance.closeSession(s);
  });
}