import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// 全局网络客户端工厂（G06 代理支持）。
///
/// 设置里配置代理后，所有 AI 请求与网页抓取都走代理。
/// 未配置时返回默认客户端。
class NetClient {
  NetClient._();

  static String? _proxyHost;
  static int _proxyPort = 0;
  static http.Client? _cached;

  /// 应用代理配置；host 为空或 port<=0 表示关闭。
  static void apply({String? proxyHost, int proxyPort = 0}) {
    final host = proxyHost?.trim();
    final nextHost = (host == null || host.isEmpty) ? null : host;
    if (nextHost == _proxyHost && proxyPort == _proxyPort) return;
    _proxyHost = nextHost;
    _proxyPort = proxyPort;
    _cached = null;
  }

  static bool get enabled => _proxyHost != null && _proxyPort > 0;

  static String? get proxyHost => _proxyHost;
  static int get proxyPort => _proxyPort;

  /// 构建（并缓存）一个符合当前代理配置的 http.Client。
  static http.Client build() {
    final cached = _cached;
    if (cached != null) return cached;
    final host = _proxyHost;
    if (host == null || _proxyPort <= 0) {
      _cached = http.Client();
      return _cached!;
    }
    final inner = HttpClient()
      ..findProxy = (_) => 'PROXY $host:$_proxyPort';
    _cached = IOClient(inner);
    return _cached!;
  }
}
