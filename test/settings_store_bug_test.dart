import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
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

  test('损坏的 settings.json 不崩溃：默认值 + 损坏文件被隔离', () async {
    final settingsFile = File('${dir.path}/support/settings.json');
    await settingsFile.create(recursive: true);
    await settingsFile.writeAsString('{oops not json');

    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 全部字段回默认：preset 默认 general、主题默认 dark
    expect(s.preset, PromptPreset.general);
    expect(s.theme, AppTheme.system); // 默认跟随系统
    // 损坏文件被重命名隔离，settings.json 不再是指向坏数据的文件
    expect(await settingsFile.exists(), isFalse);
    final leftovers = Directory('${dir.path}/support')
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.contains('settings.json.broken-'));
    expect(leftovers, isNotEmpty);
  });

  test('顶层不是 JSON 对象（数组）也安全隔离', () async {
    final settingsFile = File('${dir.path}/support/settings.json');
    await settingsFile.create(recursive: true);
    await settingsFile.writeAsString('[1,2,3]');

    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.isReady, isTrue);
    expect(s.debugMode, isFalse);
  });

  test('单字段坏类型只重置该字段，不影响其余字段', () async {
    final settingsFile = File('${dir.path}/support/settings.json');
    await settingsFile.create(recursive: true);
    await settingsFile.writeAsString(jsonEncode({
      'provider': 'openai',
      'model': 'gpt-4o-mini',
      'theme': 'light',
      'cornerRadius': 'not-a-number', // 坏类型
      'retentionDays': 30,
      'uiFont': 'mono',
    }));

    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s.theme, AppTheme.light); // 正常字段生效
    expect(s.retentionDays, 30);
    expect(s.uiFont, UiFont.mono);
    expect(s.cornerRadius, 1.0); // 坏字段回默认
  });

  test('恢复备份（导出不含 Key）不丢失现有 API Key', () async {
    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await s.setApiKey('sk-existing');
    final export = s.toExportMap();
    expect(export.containsKey('apiKey'), isFalse); // 隐私导出

    await s.restoreFrom(export);
    expect(s.apiKey, 'sk-existing'); // 备份无 Key 时保留现有

    // 显式含 apiKey 的备份则恢复
    final withKey = Map<String, dynamic>.from(export)..['apiKey'] = 'sk-new';
    await s.restoreFrom(withKey);
    expect(s.apiKey, 'sk-new');
  });

  test('模型温度显式保存 1.0 不被当作未配置', () async {
    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await s.setPreset(PromptPreset.coding);
    await s.setTemperature('gpt-4o-mini', 1.0);
    expect(s.temperatureFor('gpt-4o-mini'), 1.0); // 显式 1.0 生效

    final s2 = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s2.temperatureFor('gpt-4o-mini'), 1.0); // 持久化

    await s2.resetModelTemperature('gpt-4o-mini');
    expect(s2.temperatureFor('gpt-4o-mini'), isNull); // 移除回退预设
  });

  test('locale 单段语言不带尾下划线', () async {
    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await s.setLocale(const Locale('zh'));
    final saved = jsonDecode(File('${dir.path}/support/settings.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(saved['locale'], 'zh'); // 而非 'zh_'
  });

  test('shortcutOverrides 非字符串值被忽略而非转成 "null"', () async {
    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await s.setShortcutOverride('new_chat', 'ctrl+n');
    final export = s.toExportMap();
    export['shortcutOverrides'] = {
      'new_chat': 'ctrl+n',
      'bad': 123,
      'nullish': null,
    };
    await s.restoreFrom(export);
    expect(s.shortcutOverride('new_chat'), 'ctrl+n');
    expect(s.shortcutOverride('bad'), isNull); // 非字符串忽略
    expect(s.shortcutOverride('nullish'), isNull);
  });

  test('保存为原子写：无 .tmp 残留且 JSON 合法', () async {
    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await s.setCostMode(CostMode.poor);
    await s.setTheme(AppTheme.light);
    await s.setEnterToSend(false);

    final leftovers = Directory('${dir.path}/support')
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.endsWith('.tmp'));
    expect(leftovers, isEmpty);
    final raw = File('${dir.path}/support/settings.json').readAsStringSync();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    expect(decoded['costMode'], 'poor');
    expect(decoded['theme'], 'light');
    expect(decoded['enterToSend'], false);
    expect(decoded['schemaVersion'], 2);
  });

  test('uiZoom 界面缩放：clamp 持久化', () async {
    final s = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.uiZoom, 1.0); // 默认不缩放
    await s.setUiZoom(1.5);
    expect(s.uiZoom, 1.5);
    await s.setUiZoom(9.0); // 超出范围被钳制
    expect(s.uiZoom, 2.0);
    await s.setUiZoom(0.1);
    expect(s.uiZoom, 0.75);

    final s2 = SettingsStore();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(s2.uiZoom, 0.75); // 持久化生效
  });
}
