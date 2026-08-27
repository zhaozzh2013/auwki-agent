import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/single_instance.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('single_instance_test');
    SingleInstance.activationRequested.value = false;
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('首次获取锁成功', () async {
    final ok = await SingleInstance.acquire(
      lockDir: tmp,
      isAlive: (_) async => false,
    );
    expect(ok, isTrue);
    expect(File('${tmp.path}/app.lock').existsSync(), isTrue);
  });

  test('已有存活实例时返回 false 并写激活标记', () async {
    await SingleInstance.acquire(
      lockDir: tmp,
      isAlive: (_) async => false,
    );
    final ok = await SingleInstance.acquire(
      lockDir: tmp,
      isAlive: (pid) async => pid == pid, // 模拟存活
    );
    expect(ok, isFalse);
    expect(File('${tmp.path}/activate.flag').existsSync(), isTrue);
  });

  test('陈旧锁（进程不存在）被接管', () async {
    File('${tmp.path}/app.lock').writeAsStringSync('99999999');
    final ok = await SingleInstance.acquire(
      lockDir: tmp,
      isAlive: (_) async => false,
    );
    expect(ok, isTrue);
    expect(File('${tmp.path}/app.lock').readAsStringSync().trim(), isNotEmpty);
  });
}
