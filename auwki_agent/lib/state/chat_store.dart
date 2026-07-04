import 'package:flutter/foundation.dart';

import '../i18n/strings.dart';
import '../models/models.dart';

class ChatStore extends ChangeNotifier {
  ChatStore() {
    _seed();
  }

  final List<Conversation> _conversations = [];
  final List<Folder> _folders = [];
  String? _activeId;

  List<Conversation> get conversations => List.unmodifiable(_conversations);
  List<Folder> get folders => List.unmodifiable(_folders);
  String? get activeId => _activeId;

  Conversation? get active =>
      _activeId == null ? null : _byId(_activeId!);

  List<Conversation> get pinned =>
      _conversations.where((c) => c.pinned && c.folderId == null).toList();

  List<Conversation> get topLevel =>
      _conversations.where((c) => !c.pinned && c.folderId == null).toList();

  List<Conversation> inFolder(String folderId) =>
      _conversations.where((c) => c.folderId == folderId).toList();

  Conversation? _byId(String id) =>
      _conversations.where((c) => c.id == id).cast<Conversation?>().firstOrNull;

  Folder? folderById(String id) =>
      _folders.where((f) => f.id == id).cast<Folder?>().firstOrNull;

  void _seed() {
    _folders.add(Folder(id: 'fld_work', name: I18n.t('sidebar.folder')));

    final now = DateTime.now();
    final samples = [
      _Sample(
        title: '期末奖励三选一',
        messages: [
          _msg(Sender.user, '期末考试考得不错，妈妈说可以奖励我三选一：iPhone 17 Pro、Switch 2、PS5 Pro，你觉得我选哪个？'),
          _msg(Sender.assistant, '看你的实际需求：\n\n• iPhone 17 Pro：日常使用频率最高，通讯、拍照、刷视频都靠它\n• Switch 2：便携，想玩随时玩，但第一方大作要等\n• PS5 Pro：画质最强，适合周末宅家，但占地方\n\n问自己两个问题：① 最近最想玩什么游戏？② 主要在哪玩？'),
        ],
        daysAgo: 0,
      ),
      _Sample(
        title: '三星 Z Flip4 介绍',
        messages: [
          _msg(Sender.user, '三星 Z Flip4 这手机怎么样？'),
          _msg(Sender.assistant, '三星 Z Flip4 是 2022 年的竖折旗舰：\n\n• 骁龙 8+ Gen1\n• 6.7" 内屏 + 1.9" 外屏\n• 3700mAh 电池\n\n竖折的优势是便携、外屏能看通知和自拍。劣势是续航一般、折痕可见。现在价格跳水，二手性价比不错。'),
        ],
        daysAgo: 1,
      ),
      _Sample(
        title: '低血糖运动致命风险',
        messages: [
          _msg(Sender.user, '空腹跑步会不会有危险？'),
          _msg(Sender.assistant, '会有风险。低血糖运动可能导致：\n\n1. 头晕、乏力 → 摔倒受伤\n2. 严重时意识模糊 → 昏迷\n3. 极端情况诱发心律失常\n\n建议：运动前吃点碳水（如香蕉、燕麦），时长超过 1 小时要补糖。糖尿病患者尤其要在医生指导下进行。'),
        ],
        daysAgo: 2,
      ),
      _Sample(
        title: '农场研学日记',
        messages: [
          _msg(Sender.user, '帮我写一篇农场研学日记，300 字左右'),
          _msg(Sender.assistant, '# 农场研学日记\n\n今天我们来到郊外的有机农场。一下车，泥土和青草的清香扑面而来。\n\n上午我们参观了蔬菜大棚，认识了许多课本上学不到的蔬菜——羽衣甘蓝、樱桃萝卜、紫色花菜。农艺师叔叔讲解了滴灌系统的原理，原来一根细管就能精确给每一株植物供水。\n\n最有趣的是喂小羊。小羊们争先恐后地抢我们手里的青草，舌头粗糙又温暖。下午我们还学了用石磨磨豆子，亲手做了一杯豆浆。\n\n这次研学让我明白：食物不是超市里冷冰冰的商品，而是土地、阳光和劳动的结晶。'),
        ],
        daysAgo: 3,
      ),
      _Sample(
        title: 'INFJ 为何可怕',
        messages: [
          _msg(Sender.user, '为什么大家都说 INFJ 很可怕？'),
          _msg(Sender.assistant, 'INFJ 被称为"提倡者"，被认为"可怕"是因为：\n\n1. **洞察力强**：擅长读人，能看穿表面\n2. **共情过载**：但常常因此疲惫\n3. **理想主义**：对人对事要求高\n4. **关门慢**：很少有人能走进他们心里\n\n其实 INFJ 不可怕，他们只是太认真了。一旦信任你，会非常忠诚和深情。'),
        ],
        daysAgo: 5,
      ),
      _Sample(
        title: '朋友圈性格分析',
        messages: [
          _msg(Sender.user, '我朋友圈只发风景和工作，没人设没自拍，什么性格？'),
          _msg(Sender.assistant, '这种发布习惯通常反映出：\n\n• 内敛、独立，不太在意社交反馈\n• 注重个人空间，把朋友圈当作品展示而非社交工具\n• 可能内向（I）型，偏思考（T）型\n• 内心有稳定的世界观，不需要外界认可来确认自我\n\n这类人通常很可靠，朋友不多但都走心。'),
        ],
        daysAgo: 15,
      ),
    ];

    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      _conversations.add(Conversation(
        id: 'c_${i + 1}',
        title: s.title,
        messages: s.messages,
        updatedAt: now.subtract(Duration(days: s.daysAgo)),
      ));
    }
  }

  String newConversation() {
    final c = Conversation(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      title: I18n.t('chat.empty'),
    );
    _conversations.insert(0, c);
    _activeId = c.id;
    notifyListeners();
    return c.id;
  }

  void activate(String? id) {
    if (_activeId == id) return;
    _activeId = id;
    if (id != null) {
      final c = _byId(id);
      if (c != null) c.unread = false;
    }
    notifyListeners();
  }

  void rename(String id, String title) {
    final c = _byId(id);
    if (c == null) return;
    c.title = title.trim().isEmpty ? c.title : title.trim();
    notifyListeners();
  }

  void togglePin(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.pinned = !c.pinned;
    notifyListeners();
  }

  void toggleUnread(String id) {
    final c = _byId(id);
    if (c == null) return;
    c.unread = !c.unread;
    notifyListeners();
  }

  void delete(String id) {
    _conversations.removeWhere((c) => c.id == id);
    if (_activeId == id) _activeId = null;
    notifyListeners();
  }

  void toggleFolder(String id) {
    final f = folderById(id);
    if (f == null) return;
    f.expanded = !f.expanded;
    notifyListeners();
  }

  void addFolder(String name) {
    final id = 'fld_${DateTime.now().microsecondsSinceEpoch}';
    _folders.add(Folder(id: id, name: name));
    notifyListeners();
  }

  void moveToFolder(String convId, String? folderId) {
    final c = _byId(convId);
    if (c == null) return;
    c.folderId = folderId;
    notifyListeners();
  }

  void reorder(List<String> orderedTopLevelIds) {
    final byId = {for (final c in _conversations) c.id: c};
    final newList = <Conversation>[];
    for (final id in orderedTopLevelIds) {
      final c = byId[id];
      if (c != null && !c.pinned && c.folderId == null) newList.add(c);
    }
    for (final c in _conversations) {
      if (c.pinned || c.folderId != null) newList.add(c);
    }
    _conversations
      ..clear()
      ..addAll(newList);
    notifyListeners();
  }

  void reorderTopLevel(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final topList = topLevel;
    if (oldIndex < 0 ||
        oldIndex >= topList.length ||
        newIndex < 0 ||
        newIndex >= topList.length) {
      return;
    }
    final moving = topList.removeAt(oldIndex);
    topList.insert(newIndex, moving);
    // rebuild full list: pinned first, then topLevel (in new order), then folders
    final folders = <Conversation>[];
    final newList = <Conversation>[];
    for (final c in _conversations) {
      if (c.pinned) newList.add(c);
    }
    newList.addAll(topList);
    for (final c in _conversations) {
      if (c.folderId != null) folders.add(c);
    }
    newList.addAll(folders);
    _conversations
      ..clear()
      ..addAll(newList);
    notifyListeners();
  }

  void addMessage(String convId, Message msg) {
    final c = _byId(convId);
    if (c == null) return;
    c.messages.add(msg);
    c.updatedAt = DateTime.now();
    notifyListeners();
  }

  void updateMessage(String convId, String msgId, String text) {
    final c = _byId(convId);
    if (c == null) return;
    final i = c.messages.indexWhere((m) => m.id == msgId);
    if (i < 0) return;
    c.messages[i] = Message(
      id: c.messages[i].id,
      sender: c.messages[i].sender,
      text: text,
      attachments: c.messages[i].attachments,
      toolName: c.messages[i].toolName,
      toolArgs: c.messages[i].toolArgs,
      toolResult: c.messages[i].toolResult,
      toolOk: c.messages[i].toolOk,
      toolRunning: c.messages[i].toolRunning,
      createdAt: c.messages[i].createdAt,
    );
    notifyListeners();
  }

  void finishToolMessage(String convId, String msgId, String result, bool ok) {
    final c = _byId(convId);
    if (c == null) return;
    final i = c.messages.indexWhere((m) => m.id == msgId);
    if (i < 0) return;
    final orig = c.messages[i];
    c.messages[i] = Message(
      id: orig.id,
      sender: orig.sender,
      text: orig.text,
      attachments: orig.attachments,
      toolName: orig.toolName,
      toolArgs: orig.toolArgs,
      toolResult: result,
      toolOk: ok,
      toolRunning: false,
      createdAt: orig.createdAt,
    );
    notifyListeners();
  }
}

class _Sample {
  _Sample({required this.title, required this.messages, required this.daysAgo});
  final String title;
  final List<Message> messages;
  final int daysAgo;
}

Message _msg(Sender s, String t) => Message(
      id: 'm_${DateTime.now().microsecondsSinceEpoch}_${s.name}',
      sender: s,
      text: t,
      createdAt: DateTime.now(),
    );

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}