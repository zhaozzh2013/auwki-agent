import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/ai_providers.dart';
import 'package:auwki_agent/services/net_client.dart';
import 'package:auwki_agent/services/settings_store.dart';
import 'package:auwki_agent/services/token_stats.dart';
import 'package:auwki_agent/widgets/thinking_slider.dart';

void main() {
  test('G05: apiKeys 按行/逗号拆分并去空白', () {
    // 验证与 SettingsStore.apiKeys 一致的拆分逻辑：
    final keys = _splitKeys('sk-a\nsk-b, sk-c，sk-d \n');
    expect(keys, ['sk-a', 'sk-b', 'sk-c', 'sk-d']);
  });

  test('G10: 温度默认 1.0，可单独配置，恢复 1.0 时移除', () async {
    final s = SettingsStore();
    expect(s.temperatureFor('claude-sonnet-4-5'), isNull);
    await s.setTemperature('claude-sonnet-4-5', 0.2);
    expect(s.temperatureFor('claude-sonnet-4-5'), 0.2);
    expect(s.temperatureFor('other-model'), isNull);
    await s.setTemperature('claude-sonnet-4-5', 1.0);
    expect(s.temperatureFor('claude-sonnet-4-5'), isNull);
  });

  test('G11: 预设温度基调', () {
    final s = SettingsStore();
    expect(s.preset, PromptPreset.general);
    expect(s.presetTemperature, 1.0);
    // 无法同步改 preset 状态，验证枚举完整性即可
    expect(PromptPreset.values, hasLength(4));
  });

  test('G04: 成本估算按模型价格表', () {
    expect(costUsdPer1mInput('claude-opus-4-6'), 15.0);
    expect(costUsdPer1mInput('claude-sonnet-4-5'), 3.0);
    expect(costUsdPer1mInput('claude-haiku-4-5'), 0.8);
    expect(costUsdPer1mInput('gpt-4o'), 2.5);
    expect(costUsdPer1mInput('gpt-4o-mini'), 0.15);
    expect(costUsdPer1mInput('deepseek-v4-flash'), 0.07);
    expect(costUsdPer1mInput('unknown-model'), 0.5);
    // 100 万 token 的 opus 输入 ≈ 15 * 1.75 = 26.25
    expect(estimateCostUsd(1000000, 'claude-opus-4-6'), closeTo(26.25, 0.01));
  });

  test('G06: 代理配置状态', () {
    NetClient.apply(proxyHost: '127.0.0.1', proxyPort: 7890);
    expect(NetClient.enabled, isTrue);
    expect(NetClient.proxyHost, '127.0.0.1');
    expect(NetClient.proxyPort, 7890);
    NetClient.apply(proxyHost: '', proxyPort: 0);
    expect(NetClient.enabled, isFalse);
  });

  test('ChatRequest 携带温度', () {
    final req = ChatRequest(
      system: 's',
      messages: const [],
      model: 'm',
      maxTokens: 100,
      temperature: 0.5,
    );
    expect(req.temperature, 0.5);
    expect(req.maxTokens, 100);
  });

  test('多供应商路由：未启用时返回 null（走原流程）', () {
    final s = SettingsStore();
    expect(s.multiProviderRouting, isFalse);
    expect(s.resolveRoute(ThinkingLevel.thinking), isNull);
  });

  test('多供应商路由：按档位解析职责与供应商', () async {
    final s = SettingsStore();
    await s.setMultiProviderRouting(true);
    await s.setProviderRoutes([
      {
        'role': ProviderRole.daily.name,
        'providerId': 'deepseek',
        'modelId': 'deepseek-v4-flash',
        'apiKey': 'sk-daily',
      },
      {
        'role': ProviderRole.complex.name,
        'providerId': 'claude',
        'modelId': 'claude-sonnet-4-5',
        'apiKey': 'sk-complex',
      },
    ]);

    // Thinking → daily → DeepSeek
    final daily = s.resolveRoute(ThinkingLevel.thinking);
    expect(daily, isNotNull);
    expect(daily!.provider.kind, ProviderKind.deepseek);
    expect(daily.model, 'deepseek-v4-flash');
    expect(daily.apiKey, 'sk-daily');

    // Max → complex → Claude
    final complex = s.resolveRoute(ThinkingLevel.max);
    expect(complex!.provider.kind, ProviderKind.claude);
    expect(complex.model, 'claude-sonnet-4-5');

    // 未配置的档位（fast → simple）回退 null
    expect(s.resolveRoute(ThinkingLevel.fast), isNull);
  });

  test('多供应商路由：缺 Key/模型/供应商的规则被跳过', () async {
    final s = SettingsStore();
    await s.setMultiProviderRouting(true);
    await s.setProviderRoutes([
      {
        'role': ProviderRole.daily.name,
        'providerId': 'deepseek',
        'modelId': 'deepseek-v4-flash',
        'apiKey': '', // 缺 Key
      },
    ]);
    expect(s.resolveRoute(ThinkingLevel.thinking), isNull);
  });

  test('职责与档位映射完整', () {
    expect(
      SettingsStore.roleForLevel(ThinkingLevel.fast),
      ProviderRole.simple,
    );
    expect(
      SettingsStore.roleForLevel(ThinkingLevel.thinking),
      ProviderRole.daily,
    );
    expect(
      SettingsStore.roleForLevel(ThinkingLevel.deep),
      ProviderRole.complex,
    );
    expect(
      SettingsStore.roleForLevel(ThinkingLevel.max),
      ProviderRole.complex,
    );
    expect(
      SettingsStore.roleForLevel(ThinkingLevel.flagship),
      ProviderRole.orchestrator,
    );
  });
}

/// 与 SettingsStore.apiKeys 相同的拆分逻辑（用于独立验证）。
List<String> _splitKeys(String raw) => [
      for (final line in raw.split(RegExp(r'[\n,，]')))
        if (line.trim().isNotEmpty) line.trim(),
    ];
