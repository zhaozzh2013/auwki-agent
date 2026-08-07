import 'package:flutter_test/flutter_test.dart';

import 'package:auwki_agent/services/ai_providers.dart';

void main() {
  test('providerFromSeed 生成自定义供应商配置', () {
    final cfg = providerFromSeed(
      const CustomProviderSeed(
        id: 'custom_1',
        name: '我的模型',
        baseUrl: 'https://api.example.com/v1',
        apiStyle: ApiStyle.openai,
        models: ['model-a', 'model-b'],
      ),
    );
    expect(cfg.kind, ProviderKind.custom);
    expect(cfg.label, '我的模型');
    expect(cfg.baseUrl, 'https://api.example.com/v1');
    expect(cfg.apiStyle, ApiStyle.openai);
    expect(cfg.models.map((m) => m.id).toList(), ['model-a', 'model-b']);
    expect(cfg.defaultModel, 'model-a');
  });
}
