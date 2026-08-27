import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';

  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';

  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/docs';
}

/// 在 widget 测试中模拟 path_provider，让设置/聊天存储能正常读写临时目录。
/// 返回临时数据目录，测试结束后由调用方删除。
Directory mockPathProvider({bool hermetic = false}) {
  final dir = Directory.systemTemp.createTempSync('auwki_test_data');
  TestWidgetsFlutterBinding.ensureInitialized();
  // 直接替换平台实现，确保不读真实 AppData。
  if (hermetic) {
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
  }
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationSupportPath':
        return '${dir.path}/support';
      case 'getTemporaryDirectory':
        return '${dir.path}/tmp';
      case 'getApplicationDocumentsPath':
        return '${dir.path}/docs';
      default:
        return null;
    }
  });
  return dir;
}
