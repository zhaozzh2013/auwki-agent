import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import 'ai_providers.dart';

enum AppTheme { dark, light, system }

enum CostMode { poor, medium, max }

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

  AiClient get client =>
      AiClient(config: _provider.withBaseUrl(_baseUrl), apiKey: _apiKey);

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
      }
    } catch (_) {}
    _ready = true;
    notifyListeners();
  }

  Future<void> _save(Map<String, dynamic> patch) async {
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
    if (_providerId == id) {
      _provider = kProviders.first;
      _providerId = kProviders.first.kind.name;
      _model = _provider.defaultModel;
      _baseUrl = _provider.baseUrl;
    }
    notifyListeners();
    await _save({
      'customProviders': _customProviders,
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
}
