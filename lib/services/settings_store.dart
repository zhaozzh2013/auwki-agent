import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import '../widgets/thinking_slider.dart';
import 'ai_providers.dart';
import 'net_client.dart';

enum AppTheme { dark, light, system }

enum CostMode { poor, medium, max }

/// 场景预设（G11）：批量调整提示词与温度。
enum PromptPreset { general, coding, writing, translation }

/// C01/C15：界面密度。
enum UiDensity { compact, standard, comfortable }

/// C02：界面字体。
enum UiFont { system, serif, mono }

/// 多供应商自动切换中，每个供应商承担的职责。
enum ProviderRole { orchestrator, complex, simple, daily }

/// 设置存储：强类型字段 + 单一解析通道 + 串行原子持久化。
///
/// 设计要点（重构后）：
/// - `_applyMap` 是唯一的“Map → 字段”解析入口（`_load` 与 `restoreFrom`
///   共用），逐字段容错：坏类型/坏值只重置该字段为默认值，不再整体失败。
/// - 保存为内存全量导出 + 临时文件原子替换，崩溃/断电不会损坏 settings.json。
/// - 只有 `restoreFrom` 且备份中**没有** `apiKey` 字段时才保留现有 Key
///   （`toExportMap` 出于隐私不含 Key，避免恢复后 Key 意外丢失）。
class SettingsStore extends ChangeNotifier {
  SettingsStore() {
    _load();
  }

  ProviderConfig _provider = kProviders.first;
  String _providerId = kProviders.first.kind.name;
  String _model = kProviders.first.defaultModel;
  String _apiKey = '';
  String _baseUrl = kProviders.first.baseUrl;
  final List<Map<String, dynamic>> _customProviders = [];
  AppTheme _theme = AppTheme.dark;
  String _userName = I18n.t('sidebar.user');
  String _userInitial = I18n.t('profile.initial.default');
  bool _enterToSend = true;
  CostMode _costMode = CostMode.medium;
  bool _showRoundChanges = true;
  bool _debugMode = false;
  bool _hasSeenOnboarding = false;
  int _retentionDays = 0;
  PromptPreset _preset = PromptPreset.general;
  final Map<String, double> _temperatures = {};
  String _proxyHost = '';
  int _proxyPort = 0;
  bool _multiProviderRouting = false;
  List<Map<String, dynamic>> _providerRoutes = [];
  // ---- Batch 4: Agent 核心能力 ----
  bool _dryRun = false;
  bool _toolCacheEnabled = true;
  int _toolCacheTtlSeconds = 600;
  final Map<String, bool> _toolToggles = {};
  final List<Map<String, dynamic>> _permissionRules = [];
  final List<Map<String, dynamic>> _customTools = [];
  bool _auditEnabled = true;
  bool _memoryEnabled = true;
  final List<Map<String, dynamic>> _customAgents = [];
  final List<Map<String, dynamic>> _mcpServers = [];
  bool _autoStage = false;
  bool _autoCommit = false;
  double _cornerRadius = 1.0;
  UiDensity _uiDensity = UiDensity.standard;
  UiFont _uiFont = UiFont.system;
  bool _highContrast = false;
  final Map<String, String> _shortcutOverrides = {};
  double _inspectorWidth = 340;
  bool _inspectorOnLeft = false;
  double _uiZoom = 1.0;
  final List<String> _recentWorkspaces = [];
  Future<void> _saveQueue = Future<void>.value();

  bool _ready = false;
  bool get isReady => _ready;

  ProviderConfig get provider => _provider;
  String get providerId => _providerId;
  String get model => _model;
  String get apiKey => _apiKey;
  String get baseUrl => _baseUrl;
  AppTheme get theme => _theme;
  String get userName => _userName;
  String get userInitial => _userInitial;
  bool get enterToSend => _enterToSend;
  CostMode get costMode => _costMode;
  bool get showRoundChanges => _showRoundChanges;
  bool get debugMode => _debugMode;
  bool get hasSeenOnboarding => _hasSeenOnboarding;

  /// 对话保留天数（F10）：0 表示永久保留。
  int get retentionDays => _retentionDays;

  /// 场景预设（G11）。
  PromptPreset get preset => _preset;

  /// 指定模型的自定义温度（G10）；未配置返回 null（用预设温度）。
  double? temperatureFor(String modelId) => _temperatures[modelId];

  /// 预设对应的温度基调（模型未单独配置时生效）。
  double get presetTemperature => switch (_preset) {
        PromptPreset.general => 1.0,
        PromptPreset.coding => 0.3,
        PromptPreset.writing => 0.9,
        PromptPreset.translation => 0.3,
      };

  AiClient get client =>
      AiClient(config: _provider.withBaseUrl(_baseUrl), apiKeys: apiKeys);

  /// 一个或多个 API Key（G05）：按行/逗号分隔，自动轮换。
  List<String> get apiKeys => [
        for (final line in _apiKey.split(RegExp(r'[\n,，]')))
          if (line.trim().isNotEmpty) line.trim(),
      ];

  /// 代理配置（G06）；host 为空或 port<=0 表示关闭。
  String get proxyHost => _proxyHost;
  int get proxyPort => _proxyPort;

  /// 多供应商自动切换（按问题复杂程度动态更换供应商）。
  bool get multiProviderRouting => _multiProviderRouting;

  /// 路由规则：{role, providerId, modelId, apiKey}。
  List<Map<String, dynamic>> get providerRoutes =>
      [for (final r in _providerRoutes) _deepCopyMap(r)];

  bool get dryRun => _dryRun;
  bool get toolCacheEnabled => _toolCacheEnabled;
  int get toolCacheTtlSeconds => _toolCacheTtlSeconds;
  bool get auditEnabled => _auditEnabled;
  bool get memoryEnabled => _memoryEnabled;

  /// 指定工具是否启用（A03）；未单独配置时默认启用。
  bool toolEnabled(String tool) => _toolToggles[tool] ?? true;

  Map<String, bool> get toolToggles => Map.unmodifiable(_toolToggles);

  List<Map<String, dynamic>> get permissionRules => [
        for (final r in _permissionRules) _deepCopyMap(r),
      ];

  List<Map<String, dynamic>> get customTools => [
        for (final m in _customTools) _deepCopyMap(m),
      ];

  List<Map<String, dynamic>> get customProviders => [
        for (final m in _customProviders) _deepCopyMap(m),
      ];

  List<Map<String, dynamic>> get customAgents => [
        for (final m in _customAgents) _deepCopyMap(m),
      ];

  List<Map<String, dynamic>> get mcpServers => [
        for (final m in _mcpServers) _deepCopyMap(m),
      ];

  /// D06：AI 轮次完成后自动暂存/提交。
  bool get autoStage => _autoStage;
  bool get autoCommit => _autoCommit;

  /// C01：圆角系数（0.5~1.5）。
  double get cornerRadius => _cornerRadius;

  UiDensity get uiDensity => _uiDensity;

  UiFont get uiFont => _uiFont;

  bool get highContrast => _highContrast;

  double get inspectorWidth => _inspectorWidth;

  bool get inspectorOnLeft => _inspectorOnLeft;

  /// 全局界面缩放（Ctrl+=/-/0，0.75~2.0）。
  double get uiZoom => _uiZoom;

  List<String> get recentWorkspaces => List.unmodifiable(_recentWorkspaces);

  /// C05：某动作的快捷键覆盖（null 表示用默认）。
  String? shortcutOverride(String action) => _shortcutOverrides[action];

  /// 按思考档位解析职责。
  static ProviderRole roleForLevel(ThinkingLevel level) => switch (level) {
        ThinkingLevel.fast => ProviderRole.simple,
        ThinkingLevel.thinking => ProviderRole.daily,
        ThinkingLevel.deep => ProviderRole.complex,
        ThinkingLevel.max => ProviderRole.complex,
        ThinkingLevel.flagship => ProviderRole.orchestrator,
      };

  /// 多供应商路由解析：返回匹配当前档位的 (供应商, 模型, Key)。
  /// 未启用路由或没有匹配规则时返回 null（走原先流程）。
  ({ProviderConfig provider, String model, String apiKey})? resolveRoute(
    ThinkingLevel level,
  ) {
    if (!_multiProviderRouting) return null;
    final role = roleForLevel(level).name;
    for (final r in _providerRoutes) {
      if ((r['role'] ?? '').toString() != role) continue;
      final pid = (r['providerId'] ?? '').toString();
      final model = (r['modelId'] ?? '').toString();
      final apiKey = (r['apiKey'] ?? '').toString();
      if (pid.isEmpty || model.isEmpty || apiKey.isEmpty) continue;
      final provider = _resolveProvider(pid);
      return (provider: provider, model: model, apiKey: apiKey);
    }
    return null;
  }

  // ---------------------------------------------------------------- setter

  Future<void> setMultiProviderRouting(bool v) async {
    if (_multiProviderRouting == v) return;
    _multiProviderRouting = v;
    notifyListeners();
    await _persist();
  }

  /// 保存路由规则列表。
  Future<void> setProviderRoutes(List<Map<String, dynamic>> routes) async {
    _providerRoutes = [
      for (final r in routes)
        if ((r['providerId'] ?? '').toString().isNotEmpty)
          _deepCopyMap(r),
    ];
    notifyListeners();
    await _persist();
  }

  /// 干跑模式（A19）：工具调用只返回预览，不产生副作用。
  Future<void> setDryRun(bool v) async {
    if (_dryRun == v) return;
    _dryRun = v;
    notifyListeners();
    await _persist();
  }

  /// 工具结果缓存（A18）。
  Future<void> setToolCacheEnabled(bool v) async {
    if (_toolCacheEnabled == v) return;
    _toolCacheEnabled = v;
    notifyListeners();
    await _persist();
  }

  Future<void> setToolCacheTtl(int seconds) async {
    final v = seconds < 0 ? 0 : seconds;
    if (v == _toolCacheTtlSeconds) return;
    _toolCacheTtlSeconds = v;
    notifyListeners();
    await _persist();
  }

  /// 工具开关（A03）。
  Future<void> setToolEnabled(String tool, bool v) async {
    if (v) {
      _toolToggles.remove(tool); // 默认即启用，恢复默认即可
    } else {
      _toolToggles[tool] = false;
    }
    notifyListeners();
    await _persist();
  }

  /// 权限规则（A08）。
  Future<void> setPermissionRules(List<Map<String, dynamic>> rules) async {
    _permissionRules
      ..clear()
      ..addAll(rules.map(_deepCopyMap));
    notifyListeners();
    await _persist();
  }

  /// 自定义工具（A02）。
  Future<void> setCustomTools(List<Map<String, dynamic>> tools) async {
    _customTools
      ..clear()
      ..addAll(tools.map(_deepCopyMap));
    notifyListeners();
    await _persist();
  }

  /// 自定义子代理（A16）。
  Future<void> setCustomAgents(List<Map<String, dynamic>> agents) async {
    _customAgents
      ..clear()
      ..addAll(agents.map(_deepCopyMap));
    notifyListeners();
    await _persist();
  }

  /// MCP 服务器配置（A01）。
  Future<void> setMcpServers(List<Map<String, dynamic>> servers) async {
    _mcpServers
      ..clear()
      ..addAll(servers.map(_deepCopyMap));
    notifyListeners();
    await _persist();
  }

  Future<void> setAuditEnabled(bool v) async {
    if (_auditEnabled == v) return;
    _auditEnabled = v;
    notifyListeners();
    await _persist();
  }

  Future<void> setMemoryEnabled(bool v) async {
    if (_memoryEnabled == v) return;
    _memoryEnabled = v;
    notifyListeners();
    await _persist();
  }

  Future<void> setAutoStage(bool v) async {
    if (_autoStage == v) return;
    _autoStage = v;
    notifyListeners();
    await _persist();
  }

  Future<void> setAutoCommit(bool v) async {
    if (_autoCommit == v) return;
    _autoCommit = v;
    notifyListeners();
    await _persist();
  }

  Future<void> setCornerRadius(double v) async {
    final value = v.clamp(0.5, 1.5);
    if (_cornerRadius == value) return;
    _cornerRadius = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setUiDensity(UiDensity d) async {
    if (_uiDensity == d) return;
    _uiDensity = d;
    notifyListeners();
    await _persist();
  }

  Future<void> setUiFont(UiFont f) async {
    if (_uiFont == f) return;
    _uiFont = f;
    notifyListeners();
    await _persist();
  }

  Future<void> setHighContrast(bool v) async {
    if (_highContrast == v) return;
    _highContrast = v;
    notifyListeners();
    await _persist();
  }

  Future<void> setShortcutOverride(String action, String? key) async {
    if (key == null || key.trim().isEmpty) {
      _shortcutOverrides.remove(action);
    } else {
      _shortcutOverrides[action] = key.trim().toLowerCase();
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setInspectorWidth(double w) async {
    final value = w.clamp(260.0, 560.0);
    if (_inspectorWidth == value) return;
    _inspectorWidth = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setInspectorOnLeft(bool v) async {
    if (_inspectorOnLeft == v) return;
    _inspectorOnLeft = v;
    notifyListeners();
    await _persist();
  }

  /// 全局界面缩放（0.75~2.0）。
  Future<void> setUiZoom(double v) async {
    final value = v.clamp(0.75, 2.0);
    if (_uiZoom == value) return;
    _uiZoom = value;
    notifyListeners();
    await _persist();
  }

  Future<void> addRecentWorkspace(String dir) async {
    final d = dir.trim();
    if (d.isEmpty) return;
    _recentWorkspaces
      ..remove(d)
      ..insert(0, d);
    if (_recentWorkspaces.length > 8) {
      _recentWorkspaces.removeRange(8, _recentWorkspaces.length);
    }
    notifyListeners();
    await _persist();
  }

  List<ProviderConfig> get customProviderConfigs =>
      [for (final m in _customProviders) _configFromMap(m)];

  List<ProviderConfig> get allProviders =>
      [...kProviders, ...customProviderConfigs];

  /// 下拉选择项：(id, 显示名)。内置用 kind.name，自定义用存储 id。
  List<(String, String)> get providerChoices => [
        for (final p in kProviders) (p.kind.name, p.label),
        for (final m in _customProviders)
          ((m['id'] ?? '').toString(), (m['name'] ?? '自定义').toString()),
      ];

  ProviderConfig _configFromMap(Map<String, dynamic> m) {
    final models = ((m['models'] as List?) ?? const [])
        .whereType<String>()
        .toList();
    return providerFromSeed(
      CustomProviderSeed(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '自定义').toString(),
        baseUrl: (m['baseUrl'] ?? '').toString(),
        apiStyle: (m['apiStyle'] ?? 'openai').toString() == 'anthropic'
            ? ApiStyle.anthropic
            : ApiStyle.openai,
        models: models,
      ),
    );
  }

  ProviderConfig _resolveProvider(String id) {
    for (final p in kProviders) {
      if (p.kind.name == id) return p;
    }
    for (final m in _customProviders) {
      if ((m['id'] ?? '').toString() == id) return _configFromMap(m);
    }
    return kProviders.first;
  }

  bool _isKnownProviderId(String id) {
    if (kProviders.any((p) => p.kind.name == id)) return true;
    return _customProviders.any((m) => (m['id'] ?? '') == id);
  }

  // ------------------------------------------------------------ 加载/解析

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final decoded = _decodeJsonObject(raw);
        if (decoded != null) {
          _applyMap(decoded);
        } else {
          // E06：损坏的配置文件隔离保存，下次启动不再解析失败。
          _quarantineBrokenFile(f);
        }
      }
    } catch (e) {
      debugPrint('SettingsStore._load failed: $e');
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  static Map<String, dynamic>? _decodeJsonObject(String raw) {
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// 损坏文件改名保留（`.broken-<ts>`），避免反复解析与覆盖用户原始数据。
  static Future<void> _quarantineBrokenFile(File f) async {
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      await f.rename('${f.path}.broken-$stamp');
      debugPrint('SettingsStore: broken settings.json quarantined');
    } catch (e) {
      debugPrint('SettingsStore: quarantine failed: $e');
    }
  }

  /// 唯一的 “Map → 字段” 解析入口（`_load`/`restoreFrom` 共用）。
  /// 逐字段容错：类型不符/取值非法时重置为默认值，不影响其它字段。
  /// [restore] 为 true 时，备份缺 `apiKey` 字段则保留现有 Key（隐私导出
  /// 不含 Key，恢复不应把 Key 清空）。
  void _applyMap(Map<String, dynamic> m, {bool restore = false}) {
    final customRaw = m['customProviders'];
    if (customRaw is List) {
      _customProviders
        ..clear()
        ..addAll(customRaw.whereType<Map>().map(_typedMap));
    }
    final pid = _str(m, 'provider');
    if (pid.isNotEmpty && _isKnownProviderId(pid)) {
      _provider = _resolveProvider(pid);
      _providerId = pid;
    } else {
      _provider = kProviders.first;
      _providerId = kProviders.first.kind.name;
    }
    final mid = _str(m, 'model');
    _model = _provider.models.any((x) => x.id == mid)
        ? mid
        : _provider.defaultModel;
    _baseUrl = m.containsKey('baseUrl')
        ? _str(m, 'baseUrl')
        : (_baseUrl.isEmpty ? _provider.baseUrl : _baseUrl);
    if (m.containsKey('apiKey') || !restore) {
      _apiKey = _str(m, 'apiKey');
    }
    final loc = m['locale'];
    if (loc is String && loc.isNotEmpty) {
      final parts = loc.split('_');
      I18n.locale.value =
          Locale(parts[0], parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null);
    }
    _theme = _enum(m, 'theme', AppTheme.values, AppTheme.dark);
    _userName = _str(m, 'userName', _userName);
    _userInitial = _str(m, 'userInitial', _userInitial);
    _enterToSend = _bool(m, 'enterToSend', _enterToSend);
    _costMode = _enum(m, 'costMode', CostMode.values, CostMode.medium);
    _showRoundChanges = _bool(m, 'showRoundChanges', _showRoundChanges);
    _debugMode = _bool(m, 'debugMode', false);
    _hasSeenOnboarding = _bool(m, 'onboardingSeen', false);
    _retentionDays = _int(m, 'retentionDays', 0);
    _preset = _enum(m, 'preset', PromptPreset.values, PromptPreset.general);
    final temps = m['temperatures'];
    if (temps is Map) {
      _temperatures.clear();
      temps.forEach((k, v) {
        if (v is num) _temperatures['$k'] = v.toDouble();
      });
    }
    _proxyHost = _str(m, 'proxyHost');
    _proxyPort = _int(m, 'proxyPort', 0);
    _multiProviderRouting = _bool(m, 'multiProviderRouting', false);
    final routes = m['providerRoutes'];
    if (routes is List) {
      _providerRoutes =
          routes.whereType<Map>().map(_typedMap).toList();
    }
    NetClient.apply(proxyHost: _proxyHost, proxyPort: _proxyPort);
    _dryRun = _bool(m, 'dryRun', false);
    _toolCacheEnabled = _bool(m, 'toolCacheEnabled', true);
    _toolCacheTtlSeconds = _int(m, 'toolCacheTtlSeconds', 600);
    _auditEnabled = _bool(m, 'auditEnabled', true);
    _memoryEnabled = _bool(m, 'memoryEnabled', true);
    final toggles = m['toolToggles'];
    if (toggles is Map) {
      _toolToggles.clear();
      toggles.forEach((k, v) {
        if (v is bool) _toolToggles['$k'] = v;
      });
    }
    final perm = m['permissionRules'];
    if (perm is List) {
      _permissionRules
        ..clear()
        ..addAll(perm.whereType<Map>().map(_typedMap));
    }
    final ct = m['customTools'];
    if (ct is List) {
      _customTools
        ..clear()
        ..addAll(ct.whereType<Map>().map(_typedMap));
    }
    final ca = m['customAgents'];
    if (ca is List) {
      _customAgents
        ..clear()
        ..addAll(ca.whereType<Map>().map(_typedMap));
    }
    final ms = m['mcpServers'];
    if (ms is List) {
      _mcpServers
        ..clear()
        ..addAll(ms.whereType<Map>().map(_typedMap));
    }
    _autoStage = _bool(m, 'autoStage', false);
    _autoCommit = _bool(m, 'autoCommit', false);
    _cornerRadius = _double(m, 'cornerRadius', 1.0);
    _uiDensity = _enum(m, 'uiDensity', UiDensity.values, UiDensity.standard);
    _uiFont = _enum(m, 'uiFont', UiFont.values, UiFont.system);
    _highContrast = _bool(m, 'highContrast', false);
    final shortcuts = m['shortcutOverrides'];
    if (shortcuts is Map) {
      _shortcutOverrides.clear();
      shortcuts.forEach((k, v) {
        if (v is String) _shortcutOverrides['$k'] = v;
      });
    }
    _inspectorWidth = _double(m, 'inspectorWidth', 340);
    _inspectorOnLeft = _bool(m, 'inspectorOnLeft', false);
    _uiZoom = _double(m, 'uiZoom', 1.0).clamp(0.75, 2.0);
    final recent = m['recentWorkspaces'];
    if (recent is List) {
      _recentWorkspaces
        ..clear()
        ..addAll(recent.whereType<String>().take(8));
    }
  }

  // ------------------------------------------------------------ 类型工具

  static Map<String, dynamic> _typedMap(Map e) =>
      Map<String, dynamic>.from(e);

  /// 深拷贝（含内层 List），隔离外部引用。
  static Map<String, dynamic> _deepCopyMap(Map<String, dynamic> m) {
    final out = Map<String, dynamic>.from(m);
    for (final k in out.keys) {
      final v = out[k];
      if (v is List) out[k] = List<dynamic>.from(v);
    }
    return out;
  }

  static String _str(Map<String, dynamic> m, String k, [String def = '']) {
    final v = m[k];
    return v is String ? v : def;
  }

  static bool _bool(Map<String, dynamic> m, String k, bool def) {
    final v = m[k];
    return v is bool ? v : def;
  }

  static int _int(Map<String, dynamic> m, String k, int def) {
    final v = m[k];
    return v is num ? v.toInt() : def;
  }

  static double _double(Map<String, dynamic> m, String k, double def) {
    final v = m[k];
    return v is num ? v.toDouble() : def;
  }

  static T _enum<T>(
    Map<String, dynamic> m,
    String k,
    List<T> values,
    T def,
  ) {
    final v = m[k];
    if (v is String) {
      for (final e in values) {
        if (e.toString().split('.').last == v) return e;
      }
    }
    return def;
  }

  // ------------------------------------------------------------ 持久化

  /// 串行化 + 原子化保存（临时文件替换），失败只记日志不抛出。
  Future<void> _persist() {
    final task = _saveQueue.then((_) async {
      try {
        final f = await _file();
        await f.parent.create(recursive: true);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode(_fullJson()));
        await tmp.rename(f.path);
      } catch (e) {
        debugPrint('SettingsStore._persist failed: $e');
      }
    });
    _saveQueue = task.catchError((_) {});
    return task;
  }

  /// 内存全量导出（含 API Key，仅供本文件持久化使用）。
  Map<String, dynamic> _fullJson() => {
        'schemaVersion': 2,
        'provider': _providerId,
        'model': _model,
        'baseUrl': _baseUrl,
        'apiKey': _apiKey,
        'customProviders': _customProviders,
        'locale': _localeTag(),
        'theme': _theme.name,
        'userName': _userName,
        'userInitial': _userInitial,
        'enterToSend': _enterToSend,
        'costMode': _costMode.name,
        'showRoundChanges': _showRoundChanges,
        'debugMode': _debugMode,
        'onboardingSeen': _hasSeenOnboarding,
        'retentionDays': _retentionDays,
        'preset': _preset.name,
        'temperatures': _temperatures,
        'proxyHost': _proxyHost,
        'proxyPort': _proxyPort,
        'multiProviderRouting': _multiProviderRouting,
        'providerRoutes': _providerRoutes,
        'dryRun': _dryRun,
        'toolCacheEnabled': _toolCacheEnabled,
        'toolCacheTtlSeconds': _toolCacheTtlSeconds,
        'toolToggles': _toolToggles,
        'permissionRules': _permissionRules,
        'customTools': _customTools,
        'customAgents': _customAgents,
        'mcpServers': _mcpServers,
        'auditEnabled': _auditEnabled,
        'memoryEnabled': _memoryEnabled,
        'autoStage': _autoStage,
        'autoCommit': _autoCommit,
        'cornerRadius': _cornerRadius,
        'uiDensity': _uiDensity.name,
        'uiFont': _uiFont.name,
        'highContrast': _highContrast,
        'shortcutOverrides': _shortcutOverrides,
        'inspectorWidth': _inspectorWidth,
        'inspectorOnLeft': _inspectorOnLeft,
        'uiZoom': _uiZoom,
        'recentWorkspaces': _recentWorkspaces,
      };

  /// 语言标签：单段语言（如 zh）不带尾下划线。
  static String _localeTag() {
    final loc = I18n.locale.value;
    final cc = loc.countryCode;
    return cc == null || cc.isEmpty ? loc.languageCode : '${loc.languageCode}_$cc';
  }

  // ---------------------------------------------------------------- setters

  Future<void> setProvider(String id) async {
    final nextId = _isKnownProviderId(id)
        ? id
        : kProviders.first.kind.name;
    _provider = _resolveProvider(nextId);
    _providerId = nextId;
    if (!_provider.models.any((m) => m.id == _model)) {
      _model = _provider.defaultModel;
    }
    _baseUrl = _provider.baseUrl;
    notifyListeners();
    await _persist();
  }

  Future<void> addCustomProvider({
    required String name,
    required String baseUrl,
    required ApiStyle apiStyle,
    required List<String> models,
  }) async {
    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    _customProviders.add({
      'id': id,
      'name': name.trim(),
      'baseUrl': baseUrl.trim(),
      'apiStyle': apiStyle.name,
      'models': models
          .map((m) => m.trim())
          .where((m) => m.isNotEmpty)
          .toList(),
    });
    notifyListeners();
    await _persist();
  }

  Future<void> removeCustomProvider(String id) async {
    _customProviders.removeWhere((m) => (m['id'] ?? '') == id);
    // 删除引用该供应商的路由，避免 resolveRoute 静默回退到默认供应商。
    _providerRoutes.removeWhere((r) => (r['providerId'] ?? '') == id);
    if (_providerId == id) {
      _provider = kProviders.first;
      _providerId = kProviders.first.kind.name;
      _model = _provider.defaultModel;
      _baseUrl = _provider.baseUrl;
    }
    notifyListeners();
    await _persist();
  }

  Future<void> setModel(String id) async {
    _model = id;
    notifyListeners();
    await _persist();
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    notifyListeners();
    await _persist();
  }

  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim();
    _baseUrl = trimmed.isEmpty ? _provider.baseUrl : trimmed;
    notifyListeners();
    await _persist();
  }

  Future<void> setLocale(Locale loc) async {
    I18n.locale.value = loc;
    notifyListeners();
    await _persist();
  }

  Future<void> setTheme(AppTheme t) async {
    _theme = t;
    notifyListeners();
    await _persist();
  }

  Future<void> setUser(String name, String initial) async {
    _userName = name;
    _userInitial = initial;
    notifyListeners();
    await _persist();
  }

  Future<void> setEnterToSend(bool v) async {
    _enterToSend = v;
    notifyListeners();
    await _persist();
  }

  Future<void> setCostMode(CostMode mode) async {
    _costMode = mode;
    notifyListeners();
    await _persist();
  }

  Future<void> setShowRoundChanges(bool value) async {
    _showRoundChanges = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setDebugMode(bool value) async {
    _debugMode = value;
    notifyListeners();
    await _persist();
  }

  Future<void> setOnboardingSeen() async {
    if (_hasSeenOnboarding) return;
    _hasSeenOnboarding = true;
    notifyListeners();
    await _persist();
  }

  Future<void> resetOnboarding() async {
    _hasSeenOnboarding = false;
    notifyListeners();
    await _persist();
  }

  /// 对话保留天数（F10）：0 表示永久保留。
  Future<void> setRetentionDays(int days) async {
    final v = days < 0 ? 0 : days;
    if (v == _retentionDays) return;
    _retentionDays = v;
    notifyListeners();
    await _persist();
  }

  /// 场景预设（G11）。
  Future<void> setPreset(PromptPreset preset) async {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    await _persist();
  }

  /// 设置指定模型的自定义温度（G10，0.0~2.0）。显式保存任意值
  /// （含 1.0），不再把“等于 1.0”当作未配置而从预设温度回退。
  Future<void> setTemperature(String modelId, double value) async {
    final v = value.clamp(0.0, 2.0);
    _temperatures[modelId] = v;
    notifyListeners();
    await _persist();
  }

  /// 清除指定模型的自定义温度（回退到预设温度）。
  Future<void> resetModelTemperature(String modelId) async {
    if (_temperatures.remove(modelId) != null) {
      notifyListeners();
      await _persist();
    }
  }

  /// 设置代理（G06）；host 为空或 port<=0 关闭。
  Future<void> setProxy(String host, int port) async {
    final h = host.trim();
    _proxyHost = h;
    _proxyPort = port < 0 ? 0 : (port > 65535 ? 65535 : port);
    NetClient.apply(proxyHost: h, proxyPort: _proxyPort);
    notifyListeners();
    await _persist();
  }

  /// 更新自定义供应商的模型列表（G01 自动获取）。
  Future<void> updateCustomProviderModels(
    String id,
    List<String> models,
  ) async {
    final list =
        models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    if (list.isEmpty) return;
    for (final m in _customProviders) {
      if ((m['id'] ?? '').toString() == id) {
        m['models'] = List<String>.from(list);
        // 当前正在使用该供应商时同步刷新 provider 配置，
        // 否则模型下拉列表仍是旧缓存，需要切换供应商才能看到。
        if (_providerId == id) {
          _provider = _configFromMap(m);
        }
        if (_providerId == id &&
            !_provider.models.any((x) => x.id == _model)) {
          _model = list.first;
        }
        break;
      }
    }
    notifyListeners();
    await _persist();
  }

  /// 从配置 Map 整体恢复（F08 恢复向导）。
  /// 备份缺 `apiKey` 字段时保留现有 Key（不因隐私导出而清空）。
  /// 字段容错同 `_load`，坏值只重置该字段。
  Future<void> restoreFrom(Map<String, dynamic> m) async {
    _applyMap(m, restore: true);
    // E06：恢复后写入当前 schema 版本。
    notifyListeners();
    await _persist();
  }

  /// 导出配置快照（诊断/备份用；不含 API Key 明文）。
  Map<String, dynamic> toExportMap() => {
        'schemaVersion': 2,
        'provider': _providerId,
        'model': _model,
        'baseUrl': _baseUrl,
        'customProviders': [
          for (final m in _customProviders)
            {
              'id': m['id'],
              'name': m['name'],
              'baseUrl': m['baseUrl'],
              'apiStyle': m['apiStyle'],
              'models': m['models'],
            },
        ],
        'locale': _localeTag(),
        'theme': _theme.name,
        'userName': _userName,
        'userInitial': _userInitial,
        'enterToSend': _enterToSend,
        'costMode': _costMode.name,
        'showRoundChanges': _showRoundChanges,
        'debugMode': _debugMode,
        'retentionDays': _retentionDays,
        'preset': _preset.name,
        'temperatures': _temperatures,
        'proxyHost': _proxyHost,
        'proxyPort': _proxyPort,
        'dryRun': _dryRun,
        'toolCacheEnabled': _toolCacheEnabled,
        'toolCacheTtlSeconds': _toolCacheTtlSeconds,
        'toolToggles': _toolToggles,
        'permissionRules': _permissionRules,
        'customTools': _customTools,
        'customAgents': _customAgents,
        'mcpServers': _mcpServers,
        'auditEnabled': _auditEnabled,
        'memoryEnabled': _memoryEnabled,
        'autoStage': _autoStage,
        'autoCommit': _autoCommit,
        'cornerRadius': _cornerRadius,
        'uiDensity': _uiDensity.name,
        'uiFont': _uiFont.name,
        'highContrast': _highContrast,
        'shortcutOverrides': _shortcutOverrides,
        'inspectorWidth': _inspectorWidth,
        'inspectorOnLeft': _inspectorOnLeft,
        'uiZoom': _uiZoom,
        'recentWorkspaces': _recentWorkspaces,
      };
}