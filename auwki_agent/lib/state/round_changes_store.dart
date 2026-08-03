import 'package:flutter/foundation.dart';

/// 一轮对话结束后生成的文件变更记录。
class RoundChangeRecord {
  RoundChangeRecord({
    required this.time,
    required this.conversationId,
    required this.lines,
  });

  final DateTime time;
  final String conversationId;

  /// 摘要正文行（不含“本轮更改：”标题）。
  final List<String> lines;

  bool get isEmpty => lines.isEmpty;
}

/// 保存最近若干轮的“本轮更改”记录，供右侧面板查看。
class RoundChangesStore extends ChangeNotifier {
  final List<RoundChangeRecord> _records = [];

  List<RoundChangeRecord> get records => List.unmodifiable(_records);

  RoundChangeRecord? get latest => _records.isEmpty ? null : _records.last;

  void add(RoundChangeRecord record) {
    if (record.lines.isEmpty) return;
    _records.add(record);
    if (_records.length > 30) _records.removeAt(0);
    notifyListeners();
  }

  void clear() {
    if (_records.isEmpty) return;
    _records.clear();
    notifyListeners();
  }
}
