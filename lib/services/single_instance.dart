import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 单实例锁（E04）：
/// - 通过锁文件 + PID 存活检查判断是否已有实例；
/// - 后启动的实例写入 activate.flag 后退出；
/// - 首个实例轮询 flag，收到后置 activationRequested 供 UI 提示。
class SingleInstance {
  SingleInstance._();

  static final ValueNotifier<bool> activationRequested = ValueNotifier(false);
  static bool _active = false;
  static Timer? _watcher;

  /// 尝试获取单实例锁。返回 true 表示当前是唯一实例。
  /// [lockDir] 与 [isAlive] 仅供测试注入。
  static Future<bool> acquire({
    Directory? lockDir,
    Future<bool> Function(int pid)? isAlive,
  }) async {
    try {
      final dir = lockDir ?? await getApplicationSupportDirectory();
      final lock = File('${dir.path}/app.lock');
      final flag = File('${dir.path}/activate.flag');
      if (await lock.exists()) {
        final pidStr = (await lock.readAsString()).trim();
        final pid = int.tryParse(pidStr);
        final alive =
            pid != null && await (isAlive ?? _isProcessAlive)(pid);
        if (alive) {
          // 已有实例在运行：请求对方激活后退出。
          try {
            await flag.writeAsString('activate');
          } catch (_) {}
          return false;
        }
        // 锁文件里的进程不存在 → 陈旧锁，接管。
      }
      await lock.writeAsString('$pid');
      _active = true;
      _startWatcher(flag);
      return true;
    } catch (_) {
      // 无法检测时放行，避免单实例逻辑阻塞启动。
      return true;
    }
  }

  static void _startWatcher(File flag) {
    _watcher?.cancel();
    _watcher = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_active) return;
      try {
        if (await flag.exists()) {
          await flag.delete();
          activationRequested.value = true;
        }
      } catch (_) {}
    });
  }

  static Future<bool> _isProcessAlive(int pid) async {
    try {
      if (Platform.isWindows) {
        final r = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH']);
        return r.exitCode == 0 && (r.stdout as String).contains('$pid');
      }
      final r = await Process.run('kill', ['-0', '$pid']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
