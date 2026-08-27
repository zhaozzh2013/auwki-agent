# AUWKI Agent

[中文](../README.md) English


![License](https://img.shields.io/github/license/zhaozzh2013/auwki-agent)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20Web%20%7C%20Android-blue)
![Flutter](https://img.shields.io/badge/Flutter-3.44%2B-02569B)
![Status](https://img.shields.io/badge/status-active--development-orange)

**AUWKI Agent** is a modern, local-first AI chat desktop app built with Flutter. **Token-saving**, **cross-platform**, and **easy to use** are its defining characteristics.

**AUWKI Agent** supports multiple LLM providers, 5 levels of thinking intensity, WORK / PLAN dual modes, tool calling (web search, web fetch, shell commands) and a multi-agent collaboration framework.

***AUWKI AGENT** also supports both the OpenAI and Anthropic API formats.

*Please note that **AUWKI AGENT** is not intended for everyday small-talk use.

---

## Features

### Multi-provider LLM support

Switch between 4 major LLM services through the UI or API (implemented according to official docs):

| Provider | API | Models |
|---|---|---|
| **Claude** (Anthropic) | Native Anthropic | Claude Opus 4.6 / Sonnet 4.5 / Haiku 4.5 |
| **MiniMax** | Anthropic compatible | MiniMax-M3 (1M ctx) / M2.7 / M2.5 |
| **ChatGPT** (OpenAI) | OpenAI | GPT-4o / 4o-mini / o1-mini |
| **DeepSeek** | OpenAI compatible | DeepSeek V4 Flash / Pro |

This table does not cover every provider. For the full provider list, see the [provider reference](agents/README.md).

Your API key is stored locally in `settings.json` and is never uploaded to any server.

**We are also considering custom provider support in a future update. Thanks for your understanding!*

### Dual modes / 5 thinking levels

 **WORK mode**: executes tasks directly and produces usable results.

 **PLAN mode**: plans first, then executes.

 **5 thinking levels**: Fast → Thinking → Deep → Max → Flagship, each with different depth and length constraints.

### Agent tool calling

The LLM can call tools inside a `[正式输出] tool("args") [输出结束]` block:

- `webfetch("url")` — fetch web page content
- `websearch("query")` — search via public SearXNG instances
- `command("shell")` — run shell commands

Tool calls are shown in the UI as **independent bubbles** (icon + type + status badge) so they never pollute the main reply stream.

### Complete chat experience

- Sidebar: pin / folders / time grouping, long-press drag to reorder
- Markdown rendering (headings, code blocks, quotes, tables)
- Selection highlight colors (one set for dark / light mode)
- Attachment upload → text content is embedded into the AI context
- i18n (Chinese / English)
- Dark / light theme switching
- Conversation workspace: every conversation gets its own directory (default `app-dir/conversations/date/conversation-hash/workspace`); you can pick a custom directory when creating a conversation. All file operations, commands, and Git actions are scoped to that directory
- Git panel: stage / commit / revert / history; when the current directory is not a repository, a "Create repository" button appears to run `git init` in one click

### 🛠 Cross-platform support

| Platform | Status |
|---|---|
| **Windows** | ✅ Full support (embedded WebView2 browser, TTS, screenshots) |
| **Linux** | ✅ Full support (browser panel opens pages in system browser) |
| **macOS** | 🟡 Code ready, pending verification on a Mac (requires Xcode) |
| **Android** | 🟡 Planned (workspace not created yet; desktop features need trimming) |
| **Web** | ❌ Not supported yet (depends on dart:io / sqlite3 ffi, fails to compile) |
| **iOS** | ❌ Not supported |


---

## 🚀 Quick start

Prebuilt Windows and Linux versions are available in Releases: Windows — a portable zip and a Setup.exe installer; Linux — rpm and deb packages.
*An AUR package is planned within the next few weeks; please stay tuned.

### Requirements

**AUWKI Agent** is a Flutter app, so you need Flutter installed first.

- **Flutter SDK 3.44+**, with Dart 3.12+
- **Web**: any modern browser, no extra dependencies

*This document does not cover installing Flutter; see the [official Flutter install docs](https://docs.flutter.dev/get-started/install) if needed.

*Linux commands are used below for demonstration.

### Run from source

Clone the repository:

```bash
git clone https://github.com/zhaozzh2013/auwki-agent.git
cd auwki-agent/auwki_agent
flutter pub get
```


### Build a release

```bash
flutter build linux --release
# Output: build/linux/x64/release/bundle/auwki_agent

flutter build windows --release
# Output: build/windows/x64/runner/release

flutter build web --release
# Output: build/web/
```

### Deploy to GitHub Pages

If you have your own GitHub Pages repository, deploy with the command below:

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

## ⚙️ Configuration

After first launch, click the **menu button** in the top-left → **Settings**:

1. Choose a **provider** (Claude, MiniMax, ChatGPT, DeepSeek)
2. Choose a **model**
3. Enter your **API Key**
4. Choose a **language** (中文 / English) and **theme** (dark / light)
5. Configure **Enter-to-send** (default: Enter sends, Shift+Enter adds a newline)
6. Settings persist automatically to `~/.local/share/auwki_agent/settings.json` and restore on next launch

**All configuration stays local**; your API key is never uploaded to any server.

---

## 🏗 Architecture

**AUWKI Agent** follows a classic Flutter layered structure:

```
lib/
├── main.dart                  App entry point, theme assembly
├── app_state.dart             ChatStore + SettingsStore (InheritedWidget)
├── theme.dart                 AppPalette (ThemeExtension), dark / light
├── work_mode.dart             WorkMode enum (WORK / PLAN)
├── models/                    Data models: Conversation / Folder / Message / Attachment
├── state/chat_store.dart      Conversation & folder state management (ChangeNotifier)
├── services/
│   ├── ai_providers.dart      AiClient abstraction + 4 ProviderConfigs
│   │                          Anthropic / OpenAI SSE streaming protocol parsing
│   ├── agent.dart             AgentRunner: tool call parsing + execution
│   │                          supports webfetch / websearch / command
│   ├── prompts.dart           System prompts for modes / thinking levels
│   └── settings_store.dart    Settings + user profile persisted as JSON
├── i18n/strings.dart          Chinese / English strings
└── widgets/
    ├── sidebar.dart           Custom scroll layout, folders / pins / drag reorder
    ├── chat_input.dart        Input box, key handling, SSE streaming
    ├── thinking_slider.dart   5-level thinking slider
    ├── brand_logo.dart        Custom whale icon
    └── dialogs/               Avatar / settings / rename / delete dialogs
```

### Data flow

**AUWKI Agent**'s conversation flow looks roughly like this:

```
User → ChatInput → ChatStore.addMessage (writes the user message)
                    ↓
                  Provider API (SSE streaming)
                    ↓
                  ChatInput keeps writing chunks back to ChatStore
                    ↓
                  After streaming, parse [正式输出]...[输出结束] blocks
                    ↓
                  AgentRunner.execute: webfetch / websearch / command
                    ↓
                  Feed tool results back to the AI → continue for another turn (up to 3)
                    ↓
                  Final bubble + independent tool bubbles shown in the ListView
```


---

## 🤝 Contributing

PRs and issues are welcome.

Note: the repository has an `auwki_agent/` subdirectory at the root; all `flutter` commands must be run inside it:

```bash
cd auwki_agent
flutter pub get
flutter test
flutter run ...
```

Do not run `flutter` directly from the repository root, since `pubspec.yaml` is not there.

Please do not directly commit files from the `auwki_agent/` subdirectory.

---

## 📄 License

MIT License — see the [LICENSE](../LICENSE) file for details.

---

## 🙏 Credits

Special thanks to [Rank](https://github.com/rankCH) for providing the Linux prebuilt packages. Feel free to fork their repository as well — it means a lot to us.

**AUWKI Agent** was inspired by:

- OPENAGENT
- The Flutter framework and open-source ecosystem

API calls strictly follow official documentation:

- **Anthropic API** ([docs](https://docs.anthropic.com/))
- **OpenAI Chat API** ([docs](https://platform.openai.com/docs/))
- **DeepSeek API** ([docs](https://api-docs.deepseek.com/))
- **MiniMax Anthropic-compatible API** ([docs](https://platform.minimaxi.com/))

- The Flutter framework and open-source ecosystem

## Disclaimer

This project (including all source code and internationalization support) was entirely generated with MiniMax M3. Code quality and validity cannot be guaranteed.

As of the code's upload to GitHub, there are no known bugs that interfere with normal use.
