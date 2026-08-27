import '../models/models.dart';

/// 功能演示对话：本地构建一条覆盖全部功能的示例对话
/// （Markdown 渲染、代码块复制、附件、工具气泡、收藏、标签、摘要）。
class DemoConversation {
  DemoConversation._();

  static const String id = 'c_demo_features';

  static Conversation build() {
    final now = DateTime.now();
    String mid(int n) => 'demo_m_$n';
    return Conversation(
      id: id,
      title: '功能演示',
      tags: const ['演示'],
      summary: '这是一条本地生成的演示对话：包含 Python 快速排序讲解（Markdown + 代码块）、'
          '带附件（需求文档）、AI 用工具创建测试文件、命令执行失败与网页搜索的气泡展示。'
          '你可以对任意消息试试：复制、收藏、引用、翻译、朗读、续写、重写。',
      messages: [
        Message(
          id: mid(1),
          sender: Sender.user,
          text: '帮我用 Python 写一个快速排序，并解释它的复杂度',
          createdAt: now.subtract(const Duration(minutes: 30)),
        ),
        Message(
          id: mid(2),
          sender: Sender.assistant,
          text: '''# 快速排序（Quick Sort）

## 代码实现

```python
def quicksort(arr):
    if len(arr) <= 1:
        return arr
    pivot = arr[len(arr) // 2]
    left = [x for x in arr if x < pivot]
    mid = [x for x in arr if x == pivot]
    right = [x for x in arr if x > pivot]
    return quicksort(left) + mid + quicksort(right)
```

## 复杂度分析

| 情况 | 时间复杂度 | 空间复杂度 |
|---|---|---|
| 平均 | O(n log n) | O(log n) |
| 最坏 | O(n²) | O(n) |

## 关键点

- **分治法**：每次选一个基准（pivot）把数组分成两半
- **稳定性**：上面的写法是*不稳定*的，相等元素顺序可能变化
- 最坏情况出现在每次基准都选到极值时（如已排序数组）

> 提示：工程上常用随机选基准来规避最坏情况。

可以继续问我：**迭代版**、**三路切分** 或 **快速选择（Top-K）**。''',
          favorite: true,
          createdAt: now.subtract(const Duration(minutes: 29)),
        ),
        Message(
          id: mid(3),
          sender: Sender.user,
          text: '根据附件里的需求，给 quicksort 写一组单元测试',
          attachments: [
            Attachment(
              name: '需求说明.txt',
              size: 87,
              mimeType: 'text/plain',
              content: '要求：\n1. 支持空数组\n2. 支持含重复元素\n'
                  '3. 支持负数\n4. 不修改原数组',
            ),
          ],
          createdAt: now.subtract(const Duration(minutes: 25)),
        ),
        Message(
          id: mid(4),
          sender: Sender.tool,
          text: '',
          toolName: 'readfile',
          toolArgs: '需求说明.txt',
          toolResult: '1. 支持空数组\n2. 支持含重复元素\n3. 支持负数\n4. 不修改原数组',
          toolOk: true,
          createdAt: now.subtract(const Duration(minutes: 24)),
        ),
        Message(
          id: mid(5),
          sender: Sender.tool,
          text: '',
          toolName: 'writefile',
          toolArgs: 'test_quicksort.py|||import pytest\n\nfrom quicksort import quicksort\n\ndef test_empty():\n    assert quicksort([]) == []\n\ndef test_duplicates():\n    assert quicksort([3,1,3,2]) == [1,2,3,3]\n\ndef test_negative():\n    assert quicksort([-1,5,-3]) == [-3,-1,5]\n\ndef test_original_unchanged():\n    a = [2,1]\n    quicksort(a)\n    assert a == [2,1]',
          toolResult: '[完成] 已写入 test_quicksort.py',
          toolOk: true,
          createdAt: now.subtract(const Duration(minutes: 23)),
        ),
        Message(
          id: mid(6),
          sender: Sender.assistant,
          text: '''测试文件 `test_quicksort.py` 已创建，覆盖了你的全部 4 条需求。

- ✅ 空数组
- ✅ 重复元素
- ✅ 负数
- ✅ 不修改原数组

运行验证：

```bash
pytest test_quicksort.py -v
```''',
          createdAt: now.subtract(const Duration(minutes: 22)),
        ),
        Message(
          id: mid(7),
          sender: Sender.user,
          text: '跑一下测试看看',
          createdAt: now.subtract(const Duration(minutes: 20)),
        ),
        Message(
          id: mid(8),
          sender: Sender.tool,
          text: '',
          toolName: 'command',
          toolArgs: 'pytest test_quicksort.py -v',
          toolResult: '[错误] 命令执行超时（120 秒），已强制终止: pytest test_quicksort.py',
          toolOk: false,
          createdAt: now.subtract(const Duration(minutes: 19)),
        ),
        Message(
          id: mid(9),
          sender: Sender.assistant,
          text: '测试命令超时被终止了——通常是因为当前环境没装 pytest 或依赖初始化慢。\n\n'
              '建议依次排查：\n\n1. `pip install pytest`\n2. 确认 `quicksort.py` 在同一目录\n3. 再跑 `pytest test_quicksort.py -v`',
          createdAt: now.subtract(const Duration(minutes: 18)),
        ),
        Message(
          id: mid(10),
          sender: Sender.user,
          text: '顺便帮我搜一下：快速排序最坏情况的优化方案',
          createdAt: now.subtract(const Duration(minutes: 15)),
        ),
        Message(
          id: mid(11),
          sender: Sender.tool,
          text: '',
          toolName: 'websearch',
          toolArgs: '快速排序 最坏情况 优化',
          toolResult: '- 三路快排（3-way partition）\n  https://example.com/3way\n  '
              '处理大量重复元素时把 O(n log n) 降到接近 O(n)\n'
              '- 随机化基准（Randomized pivot）\n  https://example.com/random-pivot\n  '
              '避免已排序输入触发最坏情况\n'
              '- 尾递归优化（Tail recursion）\n  https://example.com/tail\n  降低栈深度',
          toolOk: true,
          createdAt: now.subtract(const Duration(minutes: 14)),
        ),
        Message(
          id: mid(12),
          sender: Sender.assistant,
          text: '''查到三种主流优化方案：

1. **三路快排**：大量重复元素场景下从 O(n log n) 降到接近 O(n)
2. **随机化基准**：避免已排序/接近有序输入命中最坏情况
3. **尾递归优化**：只递归短的一侧，降低调用栈深度

---

本对话是 **AUWKI 功能演示**：\n\n- **Markdown 渲染**：标题 / 表格 / 引用 / 列表 / 加粗 / 行内代码\n- **代码块**：右上角可一键复制\n- **附件**：查看第 3 条用户消息的附件气泡\n- **工具气泡**：readfile / writefile 成功、command 失败、websearch 成功\n- **收藏**：第 2 条 AI 回复已打星标（Ctrl+K → 收藏夹）\n- **标签与摘要**：本对话已打「演示」标签并预填摘要\n- **气泡操作**：对任意消息悬停试试 收藏 / 引用 / 翻译 / 朗读 / 续写 / 重写''',
          createdAt: now.subtract(const Duration(minutes: 13)),
        ),
      ],
    );
  }
}
