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

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'mimeType': mimeType,
        'preview': content.length > 200
            ? '${content.substring(0, 200)}…'
            : content,
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
}

class Folder {
  Folder({required this.id, required this.name, this.expanded = true});

  final String id;
  String name;
  bool expanded;
}

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    this.folderId,
    this.pinned = false,
    this.unread = false,
    List<Message>? messages,
    DateTime? updatedAt,
  })  : messages = messages ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String? folderId;
  bool pinned;
  bool unread;
  List<Message> messages;
  DateTime updatedAt;

  String get preview {
    if (messages.isEmpty) return '';
    final last = messages.last;
    final t = last.text.trim();
    return t.isEmpty ? '📎 ${last.attachments.length} 个附件' : t;
  }
}