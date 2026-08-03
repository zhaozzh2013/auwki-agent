import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/browser_service.dart';

void main() {
  test('解析 Netscape cookies.txt', () {
    const content =
        '# Netscape HTTP Cookie File\n'
        '.example.com\tTRUE\t/\tFALSE\t0\tsid\tabc123\n'
        '#HttpOnly_.example.org\tTRUE\t/\tTRUE\t2000000000\tuid\t42\n';
    final cookies = BrowserService.parseCookieFile(content);
    expect(cookies, hasLength(2));

    expect(cookies[0].domain, '.example.com');
    expect(cookies[0].name, 'sid');
    expect(cookies[0].value, 'abc123');
    expect(cookies[0].secure, false);

    expect(cookies[1].domain, '.example.org');
    expect(cookies[1].name, 'uid');
    expect(cookies[1].value, '42');
    expect(cookies[1].secure, true);
    expect(cookies[1].expires, isNotNull);
  });

  test('解析 JSON 数组 Cookie', () {
    const json =
        '[{"domain":".example.com","name":"theme","value":"dark","path":"/","secure":true,"httpOnly":false,"expirationDate":4102444800}]';
    final cookies = BrowserService.parseCookieFile(json);
    expect(cookies, hasLength(1));
    expect(cookies[0].domain, '.example.com');
    expect(cookies[0].name, 'theme');
    expect(cookies[0].value, 'dark');
    expect(cookies[0].secure, true);
    expect(cookies[0].expires, isNotNull);
  });

  test('无效内容返回空列表', () {
    expect(BrowserService.parseCookieFile('随便什么文本'), isEmpty);
    expect(BrowserService.parseCookieFile(''), isEmpty);
  });
}
