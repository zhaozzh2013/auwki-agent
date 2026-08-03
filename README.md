# AUWKI Agent

![License](https://img.shields.io/github/license/zhaozzh2013/auwki-agent)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Web%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-02569B)
![Status](https://img.shields.io/badge/status-active--development-orange)

**AUWKI Agent** 是使用 Flutter 框架打造的现代化本地 AI 对话桌面应用。**节省 Token**、**跨平台**、**易于使用** 是其显著性特点。

**AUWKI Agent** 支持多家 LLM 供应商、5 档思考强度、WORK / PLAN 双模式运行模式、工具调用（联网搜索、网页抓取、Shell 执行）和多 Agent 协作框架。

***AUWKI AGENT**同时支持OpenAI/Anthropic 的 API 格式。

*需要注意的是，**AUWKI AGENT**不适合日常对话使用。

---

##  特性

###  多供应商 LLM 支持

通过 UI 或 API 即可配置切换 4 家主流 LLM 服务（按官方文档实现）：

| 供应商 | 接口 | 模型 |
|---|---|---|
| **Claude** (Anthropic) | Native Anthropic | Claude Opus 4.6 / Sonnet 4.5 / Haiku 4.5 |
| **MiniMax** | Anthropic 兼容 | MiniMax-M3 (1M ctx) / M2.7 / M2.5 |
| **ChatGPT** (OpenAI) | OpenAI | GPT-4o / 4o-mini / o1-mini |
| **DeepSeek** | OpenAI 兼容 | DeepSeek V4 Flash / Pro |

这里没有写全所有的供应商，若您想要查看所有支持的供应商，请您查看[供应商查询表](docs/agents/README.md)

API Key 保存在本地 `settings.json`，不会上传服务器。

**除此之外，我们正在考虑在下次更新中支持自定义供应商。感谢理解！*
###  双模式 / 五档思考

 **WORK 模式**：直接执行任务、产出可用结果。
 
 **PLAN 模式**：先方案后执行。
 
 **5 档思考强度**：Fast → Thinking → Deep → Max → Flagship，对应不同深度与字数约束。

###  Agent 工具调用

LLM 可以在正式输出中使用 `[正式输出] tool("args") [输出结束]` 块调用：

- `webfetch("url")` — 抓取网页正文
- `websearch("query")` — 通过 SearXNG 公共实例搜索
- `command("shell")` — 执行 Shell 命令

工具调用在 UI 中以**独立气泡**呈现（图标 + 类型 + 状态徽章），不污染主回复流。

###  完整对话体验

- 侧边栏：置顶 / 文件夹 / 时间分组，长按拖拽重排序
- Markdown 渲染（标题、代码块、引用、表格）
- 选中高亮配色（深 / 浅色模式各一套）
- 附件上传 → 文本内容嵌入到 AI 上下文中
- 多语言 i18n（中 / 英）
- 深 / 浅色主题切换

### 🛠 跨平台支持

| 系统 | 状态 |
|---|---|
| **Linux** | ✅ 完整支持 |
| **Web** | ✅ 完整支持 |
| **Android** | 🟡 桌面 API 可用，移动端 UI 待适配 |
| **Windows** | ✅ 完整支持 |
| **macOS** | ⏳ 待编译支持 |
| **iOS** | ⏳ 待编译支持 |


---

## 🚀 快速开始

Realse中提供了Windows的预编译版本，你可直接下载。

### 环境要求

**AUWKI Agent** 是 Flutter 应用，所以您需要先安装 Flutter。


- **Flutter SDK 3.44+**，对应 Dart 3.12+
- **Web**：任意现代浏览器，不需要额外依赖

*这里不再阐述如何安装Flutter，如有需要，请自行查询[Flutter官方安装文档](https://docs.flutter.cn/install)。

*这里使用linux命令做演示。

### 源码运行

拉取代码：

```bash
git clone https://github.com/zhaozzh2013/auwki-agent.git
cd auwki-agent/auwki_agent
flutter pub get
```


### 编译 Release

```bash
flutter build linux --release
# 产物：build/linux/x64/release/bundle/auwki_agent

flutter build windows --release
#产物：build/windows/x64/runner/release

flutter build web --release
# 产物：build/web/
```

### 部署到 GitHub Pages

如果您有自己的 Github Pages 仓库，你可以使用下方命令一键部署：

```bash
cd /tmp && rm -rf gh-pages-tmp
git clone --depth 1 https://github.com/$USER/$USER.github.io.git gh-pages-tmp
cd gh-pages-tmp
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -r $REPO/auwki_agent/build/web/* .
git add -A && git commit -m "Deploy: $(date +%Y%m%d-%H%M%S)"
git push origin HEAD:main --force
```

---

## ⚙️ 配置

首次启动后，点击左上角 **菜单按钮** → **设置**：

1. 选择 **供应商**（Claude、MiniMax、ChatGPT、DeepSeek）
2. 选择 **模型**
3. 填写 **API Key**
4. 选择 **语言**（中文 / English）和 **主题**（深色 / 浅色）
5. 配置 **回车发送**（默认 Enter 发送，Shift+Enter 换行）
6. 配置自动持久化到 `~/.local/share/auwki_agent/settings.json`，下次启动自动恢复

这里**所有配置都存在本地**，您的 API Key 不会上传到任何服务器。

---

## 🏗 架构

**AUWKI Agent** 采用经典的 Flutter 分层：

```
lib/
├── main.dart                  应用入口，主题装配
├── app_state.dart             ChatStore + SettingsStore (InheritedWidget)
├── theme.dart                 AppPalette（ThemeExtension），深 / 浅色两套
├── work_mode.dart             WorkMode 枚举（WORK / PLAN）
├── models/                    数据模型：Conversation / Folder / Message / Attachment
├── state/chat_store.dart      对话与文件夹的状态管理（ChangeNotifier）
├── services/
│   ├── ai_providers.dart      AiClient 抽象 + 4 个 ProviderConfig
│   │                          Anthropic / OpenAI 两种 SSE 流式协议解析
│   ├── agent.dart              AgentRunner：tool 调用解析 + 执行
│   │                          支持 webfetch / websearch / command
│   ├── prompts.dart            不同模式 / 档位的系统提示词
│   └── settings_store.dart    设置 + 用户信息的 JSON 文件持久化
├── i18n/strings.dart           中英双语文案
└── widgets/
    ├── sidebar.dart           自定义滚动布局、文件夹 / 置顶 / 长按拖拽
    ├── chat_input.dart        输入框、键位拦截、SSE 流式接收
    ├── thinking_slider.dart    5 档思考强度滑杆
    ├── brand_logo.dart        自绘鲸鱼图标
    └── dialogs/              头像 / 设置 / 重命名 / 删除 等对话框
```

### 数据流

**AUWKI Agent** 的对话流程大致是这样：

```
User → ChatInput → ChatStore.addMessage（写入用户消息）
                    ↓
                  Provider API（SSE 流式）
                    ↓
                  ChatInput 持续把 chunk 写回 ChatStore
                    ↓
                  流式结束后解析 [正式输出]...[输出结束] 块
                    ↓
                  AgentRunner.execute：webfetch / websearch / command
                    ↓
                  把 tool 结果回灌给 AI → 下一轮继续生成（最多 3 轮）
                    ↓
                  最终气泡 + 独立 tool 气泡在 ListView 中显示
```


---

## 🤝 贡献

欢迎 PR / Issue。

请注意：仓库根目录下面有一层 `auwki_agent/` 子目录，所有 `flutter` 命令都要在子目录里执行：

```bash
cd auwki_agent
flutter pub get
flutter test
flutter run ...
```

请不要再根目录直接 `flutter run`，会找不到 `pubspec.yaml`。

请不要在提交时直接提交`auwki_agent/` 子目录的文件。

---

## 📄 License

MIT License —— 详见 [LICENSE](LICENSE) 文件。

---

## 🙏 致谢

**AUWKI Agent** 的灵感来自这些项目：

- OPENAGENT
- Flutter 框架与开源生态

API 调用严格按官方文档实现：

- **Anthropic API** ([docs](https://docs.anthropic.com/))
- **OpenAI Chat API** ([docs](https://platform.openai.com/docs/))
- **DeepSeek API** ([docs](https://api-docs.deepseek.com/))
- **MiniMax Anthropic 兼容接口** ([docs](https://platform.minimaxi.com/))

- Flutter 框架及开源生态

## 免责声明

本项目（包括项目全部源码，国际化支持。）全部使用Minimax M3生成，无法保证代码质量以及代码有效性。  

截至代码上传到Github，代码已经没有任何干扰使用的bug，你可以正常使用其功能。
