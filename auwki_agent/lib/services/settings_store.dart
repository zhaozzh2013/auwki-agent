import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../i18n/strings.dart';
import 'ai_providers.dart';

enum AppTheme { dark, light }

enum CostMode { poor, medium, max }

class SettingsStore extends ChangeNotifier {
  SettingsStore() {
    _load();
  }

  ProviderConfig _provider = kProviders.first;
  String _model = kProviders.first.defaultModel;
  String _apiKey = '';
  String _baseUrl = kProviders.first.baseUrl;
  AppTheme _theme = AppTheme.dark;
  String _userName = I18n.t('sidebar.user');
  String _userInitial = I18n.t('profile.initial.default');
  bool _enterToSend = true;
  CostMode _costMode = CostMode.medium;

  bool _ready = false;
  bool get isReady => _ready;

  ProviderConfig get provider => _provider;
  String get model => _model;
  String get apiKey => _apiKey;
  String get baseUrl => _baseUrl;
  AppTheme get theme => _theme;
  String get userName => _userName;
  String get userInitial => _userInitial;
  bool get enterToSend => _enterToSend;
  CostMode get costMode => _costMode;

  AiClient get client =>
      AiClient(config: _provider.withBaseUrl(_baseUrl), apiKey: _apiKey);

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
        final pid = m['provider'] as String?;
        if (pid != null) _provider = providerById(pid);
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

  Future<void> setProvider(String kindName) async {
    _provider = providerById(kindName);
    if (!_provider.models.any((m) => m.id == _model)) {
      _model = _provider.defaultModel;
    }
    _baseUrl = _provider.baseUrl;
    notifyListeners();
    await _save({
      'provider': _provider.kind.name,
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
}
