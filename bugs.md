# bugs

## ✅ 已修复

- ✅ 当对话状态为置顶的时候，右键菜单无效。
  → 把置顶/文件夹/分组头挪到 ReorderableListView 外层 Column，普通 ListView 渲染，不再被它的拖拽包装吞掉右键事件。

- ✅ 当模式为 PLAN，AI 询问是否进入 WORK 模式时无法切换。
  → 按 `prompts.dart` PLAN 模式写的协议：**当 AI 在回复开头写 `change_model(work)` 时，强制切换到 WORK**。在 `didUpdateWidget` 里正则匹配 `change_model(work)`（不区分大小写），命中即调 `widget.onModeChanged(WorkMode.work)`，并把 `change_model(work)` 字符串从可见文本里剥掉。用 `_autoSwitchedFor` 防止同一消息重复触发。

- ✅ Enter 默认为换行而非确认。
  → 添加「回车发送」设置项（设置 → 回车发送 → Enter 发送 / Enter 换行），默认「Enter 发送」。在 chat_input 用 `Focus.onKeyEvent` 拦截 Enter + Shift 组合，按设置走。键盘右下角的 send 按钮也同步切换 textInputAction。
