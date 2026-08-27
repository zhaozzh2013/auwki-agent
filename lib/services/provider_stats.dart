import 'package:flutter/foundation.dart';

/// 单次请求的统计记录（G09 供应商状态）。
class ProviderStatEntry {
  ProviderStatEntry({
    required this.providerId,
    required this.model,
    required this.ok,
    required this.latencyMs,
  });

  final String providerId;
  final String model;
  final bool ok;
  final int latencyMs;
}

/// 某供应商下单个模型的聚合统计。
class ProviderModelStat {
  ProviderModelStat({
    required this.model,
    required this.count,
    required this.okCount,
    required this.totalLatency,
  });

  final String model;
  final int count;
  final int okCount;
  final int totalLatency;

  double get successRate => count == 0 ? 0 : okCount / count;
  double get avgLatency => count == 0 ? 0 : totalLatency / count;
}

/// 会话内的请求成功率/延迟统计（G09）。
/// 数据保存在内存，重启清零；用于诊断供应商健康度。
class ProviderStatsService extends ChangeNotifier {
  ProviderStatsService._();

  static final ProviderStatsService instance = ProviderStatsService._();

  static const int _maxEntries = 300;

  final List<ProviderStatEntry> _entries = [];

  List<ProviderStatEntry> get entries => List.unmodifiable(_entries);

  void record({
    required String providerId,
    required String model,
    required bool ok,
    required int latencyMs,
  }) {
    _entries.add(
      ProviderStatEntry(
        providerId: providerId,
        model: model,
        ok: ok,
        latencyMs: latencyMs,
      ),
    );
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// 供应商整体概览。
  ({int count, int okCount, double avgLatency}) overview(String providerId) {
    var count = 0;
    var okCount = 0;
    var total = 0;
    for (final e in _entries) {
      if (e.providerId != providerId) continue;
      count++;
      if (e.ok) okCount++;
      total += e.latencyMs;
    }
    return (
      count: count,
      okCount: okCount,
      avgLatency: count == 0 ? 0 : total / count,
    );
  }

  /// 按模型聚合。
  List<ProviderModelStat> perModel(String providerId) {
    final byModel = <String, List<ProviderStatEntry>>{};
    for (final e in _entries) {
      if (e.providerId != providerId) continue;
      byModel.putIfAbsent(e.model, () => []).add(e);
    }
    final out = <ProviderModelStat>[];
    byModel.forEach((model, list) {
      out.add(
        ProviderModelStat(
          model: model,
          count: list.length,
          okCount: list.where((e) => e.ok).length,
          totalLatency: list.fold(0, (s, e) => s + e.latencyMs),
        ),
      );
    });
    out.sort((a, b) => b.count.compareTo(a.count));
    return out;
  }
}
