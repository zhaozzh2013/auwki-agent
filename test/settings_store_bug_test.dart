import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/ai_providers.dart';
import 'package:auwki_agent/services/settings_store.dart';

import 'helpers.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = mockPathProvider(hermetic: true);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('restoreFrom 恢复预设/温度/代理（不丢配置）', () async {
    final s = SettingsStore();
    await s.setPreset(PromptPreset.coding);
    await s.setTemperature('gpt-4o', 0.7);
    await s.setProxy('127.0.0.1', 7897);
    final export = s.toExportMap();

    final s2 = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await s2.restoreFrom(export);

    expect(s2.preset, PromptPreset.coding);
    expect(s2.temperatureFor('gpt-4o'), 0.7);
    expect(s2.proxyHost, '127.0.0.1');
    expect(s2.proxyPort, 7897);
  });

  test('删除自定义供应商后相关路由一并清除', () async {
    final s = SettingsStore();
    await s.addCustomProvider(
      name: 'X',
      baseUrl: 'https://x.example.com',
      apiStyle: ApiStyle.openai,
      models: ['m1'],
    );
    final id = s.customProviders.first['id'] as String;
    await s.setProviderRoutes([
      {
        'role': 'daily',
        'providerId': id,
        'modelId': 'm1',
        'apiKey': 'k',
      },
    ]);
    expect(s.providerRoutes, hasLength(1));
    await s.removeCustomProvider(id);
    expect(s.providerRoutes, isEmpty);
  });

  test('并发保存不丢失更新', () async {
    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await Future.wait([
      s.setCostMode(CostMode.poor),
      s.setPreset(PromptPreset.translation),
      s.setEnterToSend(false),
    ]);

    final s2 = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s2.costMode, CostMode.poor);
    expect(s2.preset, PromptPreset.translation);
    expect(s2.enterToSend, isFalse);
  });
}
