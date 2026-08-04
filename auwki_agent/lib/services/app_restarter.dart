import 'dart:io';

/// 应用重启工具：启动当前可执行文件的新实例后退出旧进程。
class AppRestarter {
  AppRestarter._();

  /// 重启应用。发布版会启动 exe；开发版也尝试启动当前调试可执行文件。
  static Future<void> restart() async {
    final exe = Platform.resolvedExecutable;
    await Process.start(exe, []);
    exit(0);
  }
}
