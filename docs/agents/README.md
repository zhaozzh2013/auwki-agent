# AUWKI Agent 供应商支持表

本表为 `lib/services/ai_providers.dart` 中 `kProviders` 内置的全部供应商配置。应用同时实现 Anthropic Messages 与 OpenAI Chat Completions 两种流式协议，切换供应商只需在设置中选择并填写 API Key。

## 内置供应商

| 供应商 | 接口风格 | Base URL | 默认模型 | 可选模型 |
| --- | --- | --- | --- | --- |
| Claude (Anthropic) | Anthropic Messages | `https://api.anthropic.com` | claude-sonnet-4-5 | claude-opus-4-6、claude-sonnet-4-5、claude-haiku-4-5 |
| MiniMax | Anthropic 兼容 | `https://api.minimaxi.com/anthropic` | MiniMax-M3 | MiniMax-M3 (1M ctx)、MiniMax-M2.7 Highspeed、MiniMax-M2.5 Highspeed |
| ChatGPT (OpenAI) | OpenAI Chat Completions | `https://api.openai.com/v1` | gpt-4o-mini | gpt-4o、gpt-4o-mini、o1-mini |
| DeepSeek | OpenAI 兼容 | `https://api.deepseek.com` | deepseek-v4-flash | deepseek-v4-flash、deepseek-v4-pro |

## 官方文档

- Anthropic: <https://docs.anthropic.com/>
- MiniMax 平台: <https://platform.minimaxi.com/>
- OpenAI: <https://platform.openai.com/docs/>
- DeepSeek: <https://api-docs.deepseek.com/>

## 说明

- API Key 只保存在本地应用支持目录的 `settings.json` 中，不会上传服务器。
- 设置中所有供应商都可以修改 Base URL，可用于自建代理、网关或中转服务。
- 接入新供应商时按接口风格适配即可：Anthropic 风格走 `/v1/messages`，OpenAI 风格走 `/chat/completions`。
- 添加新的内置供应商需要修改 `lib/services/ai_providers.dart` 中的 `kProviders` 列表（ProviderKind、ApiStyle、模型清单、Base URL）。