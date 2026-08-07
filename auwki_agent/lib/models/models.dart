import '../i18n/strings.dart';

enum Sender { user, assistant, system, tool }

class Attachment {
  Attachment({
    required this.name,
    required this.size,
    required this.mimeType,
    required this.content,
  });

  final String name;
  final int size;
  final String mimeType;
  final String content;

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
    name: (json['name'] ?? '').toString(),
    size: (json['size'] as num?)?.toInt() ?? 0,
    mimeType: (json['mimeType'] ?? '').toString(),
    content: (json['content'] ?? '').toString(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'size': size,
    'mimeType': mimeType,
    'content': content,
  };
}

class Message {
  Message({
    required this.id,
    required this.sender,
    required this.text,
    this.attachments = const [],
    this.toolName,
    this.toolArgs,
    this.toolResult,
    this.toolOk,
    this.toolRunning = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final Sender sender;
  final String text;
  final List<Attachment> attachments;

  final String? toolName;
  final String? toolArgs;
  final String? toolResult;
  final bool? toolOk;
  final bool toolRunning;

  final DateTime createdAt;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
    id: (json['id'] ?? '').toString(),
    sender: Sender.values.firstWhere(
      (s) => s.name == json['sender'],
      orElse: () => Sender.assistant,
    ),
    text: (json['text'] ?? '').toString(),
    attachments: ((json['attachments'] as List?) ?? const [])
        .whereType<Map>()
        .map((a) => Attachment.fromJson(Map<String, dynamic>.from(a)))
        .toList(),
    toolName: json['toolName']?.toString(),
    toolArgs: json['toolArgs']?.toString(),
    toolResult: json['toolResult']?.toString(),
    toolOk: json['toolOk'] as bool?,
    toolRunning: json['toolRunning'] as bool? ?? false,
    createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sender': sender.name,
    'text': text,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'toolName': toolName,
    'toolArgs': toolArgs,
    'toolResult': toolResult,
    'toolOk': toolOk,
    'toolRunning': toolRunning,
    'createdAt': createdAt.toIso8601String(),
  };
}

class Folder {
  Folder({required this.id, required this.name, this.expanded = true});

  final String id;
  String name;
  bool expanded;

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? '').toString(),
    expanded: json['expanded'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'expanded': expanded,
  };
}

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    this.folderId,
    this.workspaceDir,
    this.pinned = false,
    this.unread = false,
    List<Message>? messages,
    DateTime? updatedAt,
  }) : messages = messages ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String? folderId;

  /// 本对话的工作空间目录；为 null 时表示沿用应用启动目录（旧数据兼容）。
  String? workspaceDir;

  bool pinned;
  bool unread;
  List<Message> messages;
  DateTime updatedAt;

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: (json['id'] ?? '').toString(),
    title: (json['title'] ?? '').toString(),
    folderId: json['folderId']?.toString(),
    workspaceDir: json['workspaceDir']?.toString(),
    pinned: json['pinned'] as bool? ?? false,
    unread: json['unread'] as bool? ?? false,
    messages: ((json['messages'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => Message.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
    updatedAt: DateTime.tryParse((json['updatedAt'] ?? '').toString()),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'folderId': folderId,
    'workspaceDir': workspaceDir,
    'pinned': pinned,
    'unread': unread,
    'messages': messages.map((m) => m.toJson()).toList(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  String get preview {
    if (messages.isEmpty) return '';
    final last = messages.last;
    final t = last.text.trim();
    return t.isEmpty
        ? '📎 ${I18n.t('chat.attachment_count', {'count': '${last.attachments.length}'})}'
        : t;
  }
}
