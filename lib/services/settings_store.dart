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
  int _themeAccent = 0;
  double _cornerRadius = 1.0;
  UiDensity _uiDensity = UiDensity.standard;
  UiFont _uiFont = UiFont.system;
  bool _highContrast = false;
  final Map<String, String> _shortcutOverrides = {};
  double _inspectorWidth = 340;
  bool _inspectorOnLeft = false;
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
      [for (final r in _providerRoutes) Map<String, dynamic>.from(r)];

  bool get dryRun => _dryRun;
  bool get toolCacheEnabled => _toolCacheEnabled;
  int get toolCacheTtlSeconds => _toolCacheTtlSeconds;
  bool get auditEnabled => _auditEnabled;
  bool get memoryEnabled => _memoryEnabled;

  /// 指定工具是否启用（A03）；未单独配置时默认启用。
  bool toolEnabled(String tool) => _toolToggles[tool] ?? true;

  Map<String, bool> get toolToggles => Map.unmodifiable(_toolToggles);

  List<Map<String, dynamic>> get permissionRules => [
    for (final r in _permissionRules) Map<String, dynamic>.from(r),
  ];

  List<Map<String, dynamic>> get customTools => [
    for (final m in _customTools) Map<String, dynamic>.from(m),
  ];

  List<Map<String, dynamic>> get customProviders => [
    for (final m in _customProviders) Map<String, dynamic>.from(m),
  ];

  List<Map<String, dynamic>> get customAgents => [
    for (final m in _customAgents) Map<String, dynamic>.from(m),
  ];

  List<Map<String, dynamic>> get mcpServers => [
    for (final m in _mcpServers) Map<String, dynamic>.from(m),
  ];

  /// D06：AI 轮次完成后自动暂存/提交。
  bool get autoStage => _autoStage;
  bool get autoCommit => _autoCommit;

  /// C01：主题强调色索引（0=默认）。
  int get themeAccent => _themeAccent;

  /// C01：圆角系数（0.5~1.5）。
  double get cornerRadius => _cornerRadius;

  UiDensity get uiDensity => _uiDensity;

  UiFont get uiFont => _uiFont;

  bool get highContrast => _highContrast;

  double get inspectorWidth => _inspectorWidth;

  bool get inspectorOnLeft => _inspectorOnLeft;

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

  /// 开启/关闭多供应商自动切换。
  Future<void> setMultiProviderRouting(bool v) async {
    if (_multiProviderRouting == v) return;
    _multiProviderRouting = v;
    notifyListeners();
    await _save({'multiProviderRouting': v, 'schemaVersion': 2});
  }

  /// 保存路由规则列表。
  Future<void> setProviderRoutes(List<Map<String, dynamic>> routes) async {
    _providerRoutes = [
      for (final r in routes)
        if ((r['providerId'] ?? '').toString().isNotEmpty)
          Map<String, dynamic>.from(r),
    ];
    notifyListeners();
    await _save({'providerRoutes': _providerRoutes});
  }

  /// 干跑模式（A19）：工具调用只返回预览，不产生副作用。
  Future<void> setDryRun(bool v) async {
    if (_dryRun == v) return;
    _dryRun = v;
    notifyListeners();
    await _save({'dryRun': v});
  }

  /// 工具结果缓存（A18）。
  Future<void> setToolCacheEnabled(bool v) async {
    if (_toolCacheEnabled == v) return;
    _toolCacheEnabled = v;
    notifyListeners();
    await _save({'toolCacheEnabled': v});
  }

  Future<void> setToolCacheTtl(int seconds) async {
    final v = seconds < 0 ? 0 : seconds;
    if (v == _toolCacheTtlSeconds) return;
    _toolCacheTtlSeconds = v;
    notifyListeners();
    await _save({'toolCacheTtlSeconds': v});
  }

  /// 工具开关（A03）。
  Future<void> setToolEnabled(String tool, bool v) async {
    if (v) {
      _toolToggles.remove(tool); // 默认即启用，恢复默认即可
    } else {
      _toolToggles[tool] = false;
    }
    notifyListeners();
    await _save({'toolToggles': _toolToggles});
  }

  /// 权限规则（A08）。
  Future<void> setPermissionRules(List<Map<String, dynamic>> rules) async {
    _permissionRules
      ..clear()
      ..addAll(rules.map((r) => Map<String, dynamic>.from(r)));
    notifyListeners();
    await _save({'permissionRules': _permissionRules});
  }

  /// 自定义工具（A02）。
  Future<void> setCustomTools(List<Map<String, dynamic>> tools) async {
    _customTools
      ..clear()
      ..addAll(tools.map((t) => Map<String, dynamic>.from(t)));
    notifyListeners();
    await _save({'customTools': _customTools});
  }

  /// 自定义子代理（A16）。
  Future<void> setCustomAgents(List<Map<String, dynamic>> agents) async {
    _customAgents
      ..clear()
      ..addAll(agents.map((a) => Map<String, dynamic>.from(a)));
    notifyListeners();
    await _save({'customAgents': _customAgents});
  }

  /// MCP 服务器配置（A01）。
  Future<void> setMcpServers(List<Map<String, dynamic>> servers) async {
    _mcpServers
      ..clear()
      ..addAll(servers.map((s) => Map<String, dynamic>.from(s)));
    notifyListeners();
    await _save({'mcpServers': _mcpServers});
  }

  Future<void> setAuditEnabled(bool v) async {
    if (_auditEnabled == v) return;
    _auditEnabled = v;
    notifyListeners();
    await _save({'auditEnabled': v});
  }

  Future<void> setMemoryEnabled(bool v) async {
    if (_memoryEnabled == v) return;
    _memoryEnabled = v;
    notifyListeners();
    await _save({'memoryEnabled': v});
  }

  Future<void> setAutoStage(bool v) async {
    if (_autoStage == v) return;
    _autoStage = v;
    notifyListeners();
    await _save({'autoStage': v});
  }

  Future<void> setAutoCommit(bool v) async {
    if (_autoCommit == v) return;
    _autoCommit = v;
    notifyListeners();
    await _save({'autoCommit': v});
  }

  Future<void> setThemeAccent(int index) async {
    if (_themeAccent == index) return;
    _themeAccent = index;
    notifyListeners();
    await _save({'themeAccent': index});
  }

  Future<void> setCornerRadius(double v) async {
    final value = v.clamp(0.5, 1.5);
    if (_cornerRadius == value) return;
    _cornerRadius = value;
    notifyListeners();
    await _save({'cornerRadius': value});
  }

  Future<void> setUiDensity(UiDensity d) async {
    if (_uiDensity == d) return;
    _uiDensity = d;
    notifyListeners();
    await _save({'uiDensity': d.name});
  }

  Future<void> setUiFont(UiFont f) async {
    if (_uiFont == f) return;
    _uiFont = f;
    notifyListeners();
    await _save({'uiFont': f.name});
  }

  Future<void> setHighContrast(bool v) async {
    if (_highContrast == v) return;
    _highContrast = v;
    notifyListeners();
    await _save({'highContrast': v});
  }

  Future<void> setShortcutOverride(String action, String? key) async {
    if (key == null || key.trim().isEmpty) {
      _shortcutOverrides.remove(action);
    } else {
      _shortcutOverrides[action] = key.trim().toLowerCase();
    }
    notifyListeners();
    await _save({'shortcutOverrides': _shortcutOverrides});
  }

  Future<void> setInspectorWidth(double w) async {
    final value = w.clamp(260.0, 560.0);
    if (_inspectorWidth == value) return;
    _inspectorWidth = value;
    notifyListeners();
    await _save({'inspectorWidth': value});
  }

  Future<void> setInspectorOnLeft(bool v) async {
    if (_inspectorOnLeft == v) return;
    _inspectorOnLeft = v;
    notifyListeners();
    await _save({'inspectorOnLeft': v});
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
    await _save({'recentWorkspaces': _recentWorkspaces});
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

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/settings.json');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final raw = await f.readAsString();
        final m = jsonDecode(raw) as Map<String, dynamic>;
        final customRaw = (m['customProviders'] as List?) ?? const [];
        _customProviders
          ..clear()
          ..addAll(
            customRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e)),
          );
        final pid = m['provider'] as String?;
        if (pid != null && pid.isNotEmpty && _isKnownProviderId(pid)) {
          _provider = _resolveProvider(pid);
          _providerId = pid;
        } else {
          _provider = kProviders.first;
          _providerId = kProviders.first.kind.name;
        }
        final mid = m['model'] as String?;
        if (mid != null && _provider.models.any((x) => x.id == mid)) {
          _model = mid;
        } else {
          _model = _provider.defaultModel;
        }
        _baseUrl = (m['baseUrl'] as String?) ?? _provider.baseUrl;
        _apiKey = (m['apiKey'] as String?) ?? '';
        final loc = m['locale'] as String?;
        if (loc != null) {
          final parts = loc.split('_');
          I18n.locale.value = Locale(
            parts[0],
            parts.length > 1 ? parts[1] : null,
          );
        }
        final th = m['theme'] as String?;
        if (th != null) {
          _theme = AppTheme.values.firstWhere(
            (t) => t.name == th,
            orElse: () => AppTheme.dark,
          );
        }
        _userName = (m['userName'] as String?) ?? _userName;
        _userInitial = (m['userInitial'] as String?) ?? _userInitial;
        _enterToSend = (m['enterToSend'] as bool?) ?? _enterToSend;
        final cost = m['costMode'] as String?;
        if (cost != null) {
          _costMode = CostMode.values.firstWhere(
            (x) => x.name == cost,
            orElse: () => CostMode.medium,
          );
        }
        _showRoundChanges = (m['showRoundChanges'] as bool?) ??
            _showRoundChanges;
        _debugMode = (m['debugMode'] as bool?) ?? false;
        _hasSeenOnboarding = (m['onboardingSeen'] as bool?) ?? false;
        _retentionDays = (m['retentionDays'] as num?)?.toInt() ?? 0;
        final preset = m['preset'] as String?;
        if (preset != null) {
          _preset = PromptPreset.values.firstWhere(
            (p) => p.name == preset,
            orElse: () => PromptPreset.general,
          );
        }
        final temps = m['temperatures'];
        if (temps is Map) {
          _temperatures.clear();
          temps.forEach((k, v) {
            if (v is num) _temperatures['$k'] = v.toDouble();
          });
        }
        _proxyHost = (m['proxyHost'] as String?) ?? '';
        _proxyPort = (m['proxyPort'] as num?)?.toInt() ?? 0;
        _multiProviderRouting =
            (m['multiProviderRouting'] as bool?) ?? false;
        final routes = m['providerRoutes'];
        if (routes is List) {
          _providerRoutes = [
            for (final r in routes)
              if (r is Map) Map<String, dynamic>.from(r),
          ];
        }
        NetClient.apply(proxyHost: _proxyHost, proxyPort: _proxyPort);
        // E06：结构版本化。首次加载旧配置时写入版本号。
        final version = (m['schemaVersion'] as num?)?.toInt() ?? 1;
        if (version < 2) {
          unawaited(_save({'schemaVersion': 2}));
        }
        _dryRun = (m['dryRun'] as bool?) ?? false;
        _toolCacheEnabled = (m['toolCacheEnabled'] as bool?) ?? true;
        _toolCacheTtlSeconds =
            (m['toolCacheTtlSeconds'] as num?)?.toInt() ?? 600;
        _auditEnabled = (m['auditEnabled'] as bool?) ?? true;
        _memoryEnabled = (m['memoryEnabled'] as bool?) ?? true;
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
            ..addAll(
              perm
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e)),
            );
        }
        final ct = m['customTools'];
        if (ct is List) {
          _customTools
            ..clear()
            ..addAll(
              ct.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        }
        final ca = m['customAgents'];
        if (ca is List) {
          _customAgents
            ..clear()
            ..addAll(
              ca.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        }
        final ms = m['mcpServers'];
        if (ms is List) {
          _mcpServers
            ..clear()
            ..addAll(
              ms.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            );
        }
        _autoStage = (m['autoStage'] as bool?) ?? false;
        _autoCommit = (m['autoCommit'] as bool?) ?? false;
        _themeAccent = (m['themeAccent'] as num?)?.toInt() ?? 0;
        _cornerRadius = (m['cornerRadius'] as num?)?.toDouble() ?? 1.0;
        final density = m['uiDensity'] as String?;
        if (density != null) {
          _uiDensity = UiDensity.values.firstWhere(
            (x) => x.name == density,
            orElse: () => UiDensity.standard,
          );
        }
        final font = m['uiFont'] as String?;
        if (font != null) {
          _uiFont = UiFont.values.firstWhere(
            (x) => x.name == font,
            orElse: () => UiFont.system,
          );
        }
        _highContrast = (m['highContrast'] as bool?) ?? false;
        final shortcuts = m['shortcutOverrides'];
        if (shortcuts is Map) {
          _shortcutOverrides.clear();
          shortcuts.forEach((k, v) {
            _shortcutOverrides['$k'] = '$v';
          });
        }
        _inspectorWidth = (m['inspectorWidth'] as num?)?.toDouble() ?? 340;
        _inspectorOnLeft = (m['inspectorOnLeft'] as bool?) ?? false;
        final recent = m['recentWorkspaces'];
        if (recent is List) {
          _recentWorkspaces
            ..clear()
            ..addAll(recent.whereType<String>().take(8));
        }
      }
    } catch (_) {}
    _ready = true;
    notifyListeners();
  }

  /// 串行化保存：避免快速连续修改时 read-modify-write 竞争丢失更新。
  Future<void> _save(Map<String, dynamic> patch) {
    final task = _saveQueue.then((_) async {
      try {
        final f = await _file();
        Map<String, dynamic> cur = {};
        if (await f.exists()) {
          try {
            cur = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          } catch (_) {}
        }
        cur.addAll(patch);
        await f.create(recursive: true);
        await f.writeAsString(jsonEncode(cur));
      } catch (_) {}
    });
    _saveQueue = task.catchError((_) {});
    return task;
  }

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
    await _save({
      'provider': _providerId,
      'model': _model,
      'baseUrl': _baseUrl,
    });
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
    await _save({'customProviders': _customProviders});
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
    await _save({
      'customProviders': _customProviders,
      'providerRoutes': _providerRoutes,
      'provider': _providerId,
      'model': _model,
      'baseUrl': _baseUrl,
    });
  }

  Future<void> setModel(String id) async {
    _model = id;
    notifyListeners();
    await _save({'model': id});
  }

  Future<void> setApiKey(String key) async {
    _apiKey = key;
    notifyListeners();
    await _save({'apiKey': key});
  }

  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim();
    _baseUrl = trimmed.isEmpty ? _provider.baseUrl : trimmed;
    notifyListeners();
    await _save({'baseUrl': _baseUrl});
  }

  Future<void> setLocale(Locale loc) async {
    I18n.locale.value = loc;
    notifyListeners();
    await _save({'locale': '${loc.languageCode}_${loc.countryCode ?? ''}'});
  }

  Future<void> setTheme(AppTheme t) async {
    _theme = t;
    notifyListeners();
    await _save({'theme': t.name});
  }

  Future<void> setUser(String name, String initial) async {
    _userName = name;
    _userInitial = initial;
    notifyListeners();
    await _save({'userName': name, 'userInitial': initial});
  }

  Future<void> setEnterToSend(bool v) async {
    _enterToSend = v;
    notifyListeners();
    await _save({'enterToSend': v});
  }

  Future<void> setCostMode(CostMode mode) async {
    _costMode = mode;
    notifyListeners();
    await _save({'costMode': mode.name});
  }

  Future<void> setShowRoundChanges(bool value) async {
    _showRoundChanges = value;
    notifyListeners();
    await _save({'showRoundChanges': value});
  }

  Future<void> setDebugMode(bool value) async {
    _debugMode = value;
    notifyListeners();
    await _save({'debugMode': value});
  }

  Future<void> setOnboardingSeen() async {
    if (_hasSeenOnboarding) return;
    _hasSeenOnboarding = true;
    notifyListeners();
    await _save({'onboardingSeen': true});
  }

  Future<void> resetOnboarding() async {
    _hasSeenOnboarding = false;
    notifyListeners();
    await _save({'onboardingSeen': false});
  }

  /// 对话保留天数（F10）：0 表示永久保留。
  Future<void> setRetentionDays(int days) async {
    final v = days < 0 ? 0 : days;
    if (v == _retentionDays) return;
    _retentionDays = v;
    notifyListeners();
    await _save({'retentionDays': v, 'schemaVersion': 2});
  }

  /// 场景预设（G11）。
  Future<void> setPreset(PromptPreset preset) async {
    if (_preset == preset) return;
    _preset = preset;
    notifyListeners();
    await _save({'preset': preset.name});
  }

  /// 设置指定模型的自定义温度（G10）。
  Future<void> setTemperature(String modelId, double value) async {
    final v = value.clamp(0.0, 2.0);
    if (v == 1.0) {
      _temperatures.remove(modelId);
    } else {
      _temperatures[modelId] = v;
    }
    notifyListeners();
    await _save({'temperatures': _temperatures});
  }

  /// 设置代理（G06）；host 为空或 port<=0 关闭。
  Future<void> setProxy(String host, int port) async {
    final h = host.trim();
    _proxyHost = h;
    _proxyPort = port < 0 ? 0 : (port > 65535 ? 65535 : port);
    NetClient.apply(proxyHost: h, proxyPort: _proxyPort);
    notifyListeners();
    await _save({'proxyHost': _proxyHost, 'proxyPort': _proxyPort});
  }

  /// 更新自定义供应商的模型列表（G01 自动获取）。
  Future<void> updateCustomProviderModels(String id, List<String> models) async {
    final list = models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    if (list.isEmpty) return;
    for (final m in _customProviders) {
      if ((m['id'] ?? '').toString() == id) {
        m['models'] = list;
        // bug3：当前正在使用该供应商时同步刷新 provider 配置，
        // 否则模型下拉列表仍是旧缓存，需要切换供应商才能看到。
        if (_providerId == id) {
          _provider = _configFromMap(m);
        }
        break;
      }
    }
    // 若当前正使用该供应商且模型列表为空/不可用，同步切换。
    if (_providerId == id && !_provider.models.any((x) => x.id == _model)) {
      _model = list.first;
    }
    notifyListeners();
    await _save({'customProviders': _customProviders});
  }

  /// 从配置 Map 整体恢复（F08 恢复向导）。
  Future<void> restoreFrom(Map<String, dynamic> m) async {
    final customRaw = (m['customProviders'] as List?) ?? const [];
    _customProviders
      ..clear()
      ..addAll(
        customRaw
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e)),
      );
    final pid = m['provider'] as String?;
    if (pid != null && pid.isNotEmpty && _isKnownProviderId(pid)) {
      _provider = _resolveProvider(pid);
      _providerId = pid;
    }
    final mid = m['model'] as String?;
    if (mid != null && _provider.models.any((x) => x.id == mid)) {
      _model = mid;
    }
    _baseUrl = (m['baseUrl'] as String?) ?? _provider.baseUrl;
    _apiKey = (m['apiKey'] as String?) ?? '';
    final loc = m['locale'] as String?;
    if (loc != null) {
      final parts = loc.split('_');
      I18n.locale.value = Locale(
        parts[0],
        parts.length > 1 ? parts[1] : null,
      );
    }
    final th = m['theme'] as String?;
    if (th != null) {
      _theme = AppTheme.values.firstWhere(
        (t) => t.name == th,
        orElse: () => AppTheme.dark,
      );
    }
    _userName = (m['userName'] as String?) ?? _userName;
    _userInitial = (m['userInitial'] as String?) ?? _userInitial;
    _enterToSend = (m['enterToSend'] as bool?) ?? _enterToSend;
    final cost = m['costMode'] as String?;
    if (cost != null) {
      _costMode = CostMode.values.firstWhere(
        (x) => x.name == cost,
        orElse: () => CostMode.medium,
      );
    }
    _showRoundChanges = (m['showRoundChanges'] as bool?) ?? _showRoundChanges;
    _debugMode = (m['debugMode'] as bool?) ?? false;
    _hasSeenOnboarding = (m['onboardingSeen'] as bool?) ?? _hasSeenOnboarding;
    _retentionDays = (m['retentionDays'] as num?)?.toInt() ?? 0;
    final preset = m['preset'] as String?;
    if (preset != null) {
      _preset = PromptPreset.values.firstWhere(
        (p) => p.name == preset,
        orElse: () => PromptPreset.general,
      );
    }
    final temps = m['temperatures'];
    if (temps is Map) {
      _temperatures.clear();
      temps.forEach((k, v) {
        if (v is num) _temperatures['$k'] = v.toDouble();
      });
    }
    _proxyHost = (m['proxyHost'] as String?) ?? '';
    _proxyPort = (m['proxyPort'] as num?)?.toInt() ?? 0;
    NetClient.apply(proxyHost: _proxyHost, proxyPort: _proxyPort);
    _multiProviderRouting = (m['multiProviderRouting'] as bool?) ?? false;
    final routes = m['providerRoutes'];
    if (routes is List) {
      _providerRoutes = [
        for (final r in routes)
          if (r is Map) Map<String, dynamic>.from(r),
      ];
    }
    _dryRun = (m['dryRun'] as bool?) ?? false;
    _toolCacheEnabled = (m['toolCacheEnabled'] as bool?) ?? true;
    _toolCacheTtlSeconds =
        (m['toolCacheTtlSeconds'] as num?)?.toInt() ?? 600;
    _auditEnabled = (m['auditEnabled'] as bool?) ?? true;
    _memoryEnabled = (m['memoryEnabled'] as bool?) ?? true;
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
        ..addAll(
          perm.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
    }
    final ct = m['customTools'];
    if (ct is List) {
      _customTools
        ..clear()
        ..addAll(
          ct.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
    }
    final ca = m['customAgents'];
    if (ca is List) {
      _customAgents
        ..clear()
        ..addAll(
          ca.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
    }
    final ms = m['mcpServers'];
    if (ms is List) {
      _mcpServers
        ..clear()
        ..addAll(
          ms.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
    }
    _autoStage = (m['autoStage'] as bool?) ?? false;
    _autoCommit = (m['autoCommit'] as bool?) ?? false;
    _themeAccent = (m['themeAccent'] as num?)?.toInt() ?? 0;
    _cornerRadius = (m['cornerRadius'] as num?)?.toDouble() ?? 1.0;
    final density = m['uiDensity'] as String?;
    if (density != null) {
      _uiDensity = UiDensity.values.firstWhere(
        (x) => x.name == density,
        orElse: () => UiDensity.standard,
      );
    }
    final font = m['uiFont'] as String?;
    if (font != null) {
      _uiFont = UiFont.values.firstWhere(
        (x) => x.name == font,
        orElse: () => UiFont.system,
      );
    }
    _highContrast = (m['highContrast'] as bool?) ?? false;
    final shortcuts = m['shortcutOverrides'];
    if (shortcuts is Map) {
      _shortcutOverrides.clear();
      shortcuts.forEach((k, v) => _shortcutOverrides['$k'] = '$v');
    }
    _inspectorWidth = (m['inspectorWidth'] as num?)?.toDouble() ?? 340;
    _inspectorOnLeft = (m['inspectorOnLeft'] as bool?) ?? false;
    final recent = m['recentWorkspaces'];
    if (recent is List) {
      _recentWorkspaces
        ..clear()
        ..addAll(recent.whereType<String>().take(8));
    }
    notifyListeners();
    await _save({
      'schemaVersion': 2,
      'provider': _providerId,
      'model': _model,
      'baseUrl': _baseUrl,
      'apiKey': _apiKey,
      'customProviders': _customProviders,
      'locale': '${I18n.locale.value.languageCode}_${I18n.locale.value.countryCode ?? ''}',
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
      'themeAccent': _themeAccent,
      'cornerRadius': _cornerRadius,
      'uiDensity': _uiDensity.name,
      'uiFont': _uiFont.name,
      'highContrast': _highContrast,
      'shortcutOverrides': _shortcutOverrides,
      'inspectorWidth': _inspectorWidth,
      'inspectorOnLeft': _inspectorOnLeft,
      'recentWorkspaces': _recentWorkspaces,
    });
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
    'locale':
        '${I18n.locale.value.languageCode}_${I18n.locale.value.countryCode ?? ''}',
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
    'themeAccent': _themeAccent,
    'cornerRadius': _cornerRadius,
    'uiDensity': _uiDensity.name,
    'uiFont': _uiFont.name,
    'highContrast': _highContrast,
    'shortcutOverrides': _shortcutOverrides,
    'inspectorWidth': _inspectorWidth,
    'inspectorOnLeft': _inspectorOnLeft,
    'recentWorkspaces': _recentWorkspaces,
  };
}
