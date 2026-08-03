import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在 widget 测试中模拟 path_provider，让设置/聊天存储能正常读写临时目录。
/// 返回临时数据目录，测试结束后由调用方删除。
Directory mockPathProvider() {
  final dir = Directory.systemTemp.createTempSync('auwki_test_data');
  TestWidgetsFlutterBinding.ensureInitialized();
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
