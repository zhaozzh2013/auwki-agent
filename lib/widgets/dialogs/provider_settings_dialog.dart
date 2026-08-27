import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../services/ai_providers.dart';
import '../../services/settings_store.dart';
import '../../theme.dart';

/// 供应商设置（二级菜单）：供应商/模型/API Key/温度/自定义供应商，
/// 以及多供应商自动切换（开关 + 职责规则表格）。
class ProviderSettingsDialog extends StatefulWidget {
  const ProviderSettingsDialog({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<ProviderSettingsDialog> createState() =>
      _ProviderSettingsDialogState();
}

class _ProviderSettingsDialogState extends State<ProviderSettingsDialog> {
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  late List<Map<String, dynamic>> _routes;
  bool _obscure = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _apiKey = TextEditingController();
    _baseUrl = TextEditingController();
    _routes = widget.settings.providerRoutes;
  }

  SettingsStore get _settings => widget.settings;

  @override
  void dispose() {
    _apiKey.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  void _ensureInitialized() {
    if (_initialized) return;
    _apiKey.text = _settings.apiKey;
    _baseUrl.text = _settings.baseUrl;
    _initialized = true;
  }

  // ── 多供应商路由（本地编辑，改动即保存） ──

  void _updateRoute(int index, String key, String value) {
    if (index < 0 || index >= _routes.length) return;
    _routes[index][key] = value;
    _settings.setProviderRoutes(_routes);
  }

  void _addRoute() {
    final used = {for (final r in _routes) r['role']?.toString()};
    ProviderRole? next;
    for (final role in ProviderRole.values) {
      if (!used.contains(role.name)) {
        next = role;
        break;
      }
    }
    if (next == null) {
      _snack(I18n.t('settings.multi_provider.full'));
      return;
    }
    final provider = _settings.allProviders.isNotEmpty
        ? _settings.allProviders.first
        : kProviders.first;
    _routes.add({
      'role': next.name,
      'providerId': provider.kind.name,
      'modelId': provider.defaultModel,
      'apiKey': '',
    });
    _settings.setProviderRoutes(_routes);
  }

  void _removeRoute(int index) {
    if (index < 0 || index >= _routes.length) return;
    _routes.removeAt(index);
    _settings.setProviderRoutes(_routes);
  }

  /// 所有职责都已分配完整（provider/model/key 均非空）才算完成。
  bool _routesComplete(SettingsStore s) => _missingRoles(s).isEmpty;

  List<String> _missingRoles(SettingsStore s) {
    final covered = <String>{};
    for (final r in _routes) {
      final pid = (r['providerId'] ?? '').toString().trim();
      final mid = (r['modelId'] ?? '').toString().trim();
      final key = (r['apiKey'] ?? '').toString().trim();
      if (pid.isNotEmpty && mid.isNotEmpty && key.isNotEmpty) {
        covered.add((r['role'] ?? '').toString());
      }
    }
    return [
      for (final role in ProviderRole.values)
        if (!covered.contains(role.name)) role.name,
    ];
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, style: const TextStyle(fontSize: 12)),
          backgroundColor: AppColors.surfaceAlt,
        ),
      );
  }

  // ── G03 / G01 ──

  Future<void> _testConnection() async {
    final s = _settings;
    _snack(I18n.t('settings.test_connection.running'));
    final result = await s.client.testConnection();
    if (!mounted) return;
    _snack(
      result.ok
          ? I18n.t('settings.test_connection.ok', {
              'ms': '${result.latencyMs}',
              'models': result.models == null
                  ? '-'
                  : '${result.models!.length}',
            })
          : I18n.t('settings.test_connection.failed', {
              'error': result.error ?? 'unknown',
            }),
    );
  }

  Future<void> _refreshModels() async {
    final s = _settings;
    _snack(I18n.t('settings.refresh_models.running'));
    final models = await s.client.fetchModels();
    if (!mounted) return;
    _snack(
      models == null || models.isEmpty
          ? I18n.t('settings.refresh_models.failed')
          : I18n.t('settings.refresh_models.done', {
              'count': '${models.length}',
            }),
    );
    if (models != null &&
        models.isNotEmpty &&
        s.provider.kind == ProviderKind.custom) {
      await s.updateCustomProviderModels(s.providerId, models);
    }
  }

  Future<void> _addCustomProvider() async {
    final name = TextEditingController();
    final base = TextEditingController();
    final models = TextEditingController();
    var style = ApiStyle.openai;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            I18n.t('settings.custom_provider.add'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    autofocus: true,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: I18n.t('settings.custom_provider.name'),
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: base,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: I18n.t('settings.custom_provider.base_url'),
                      hintText: 'https://api.example.com/v1',
                      hintStyle: TextStyle(color: AppColors.textTertiary),
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: models,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: I18n.t('settings.custom_provider.models'),
                      hintText: 'model-a, model-b',
                      hintStyle: TextStyle(color: AppColors.textTertiary),
                      labelStyle: TextStyle(color: AppColors.textSecondary),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    I18n.t('settings.custom_provider.api_style'),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _segRow(
                    options: [
                      (
                        'openai',
                        I18n.t('settings.custom_provider.api_style.openai'),
                      ),
                      (
                        'anthropic',
                        I18n.t('settings.custom_provider.api_style.anthropic'),
                      ),
                    ],
                    current: style.name,
                    onSelect: (v) => setLocal(
                      () => style = v == 'anthropic'
                          ? ApiStyle.anthropic
                          : ApiStyle.openai,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                I18n.t('git.cancel'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: Text(I18n.t('dialog.save')),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _settings.addCustomProvider(
        name: name.text,
        baseUrl: base.text,
        apiStyle: style,
        models: models.text
            .split(RegExp(r'[,，]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialized();
    final s = _settings;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      contentPadding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
      title: Row(
        children: [
          Icon(Icons.dns_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            I18n.t('settings.provider_manage'),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _label(I18n.t('settings.provider')),
              DropdownButton<String>(
                value: s.providerChoices.any((c) => c.$1 == s.providerId)
                    ? s.providerId
                    : s.providerChoices.first.$1,
                isExpanded: true,
                dropdownColor: AppColors.surfaceAlt,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                items: [
                  for (final (id, label) in s.providerChoices)
                    DropdownMenuItem(value: id, child: Text(label)),
                ],
                onChanged: (v) async {
                  if (v != null) {
                    await s.setProvider(v);
                    if (mounted) _baseUrl.text = s.baseUrl;
                  }
                },
              ),
              const SizedBox(height: 8),
              _label(I18n.t('settings.model')),
              DropdownButton<String>(
                value: s.model,
                isExpanded: true,
                dropdownColor: AppColors.surfaceAlt,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                items: [
                  for (final m in s.provider.models)
                    DropdownMenuItem(value: m.id, child: Text(m.label)),
                ],
                onChanged: (v) async {
                  if (v != null) await s.setModel(v);
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.network_check,
                      label: I18n.t('settings.test_connection'),
                      onTap: _testConnection,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.sync,
                      label: I18n.t('settings.refresh_models'),
                      onTap: _refreshModels,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _label(I18n.t('settings.temperature')),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Text(
                      I18n.t('settings.temperature'),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 12,
                          ),
                        ),
                        child: Slider(
                          min: 0,
                          max: 2,
                          divisions: 20,
                          value: (s.temperatureFor(s.model) ??
                                  s.presetTemperature)
                              .clamp(0.0, 2.0),
                          onChanged: (v) => s.setTemperature(s.model, v),
                        ),
                      ),
                    ),
                    Text(
                      (s.temperatureFor(s.model) ?? s.presetTemperature)
                          .toStringAsFixed(1),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (s.temperatureFor(s.model) != null)
                      InkWell(
                        onTap: () => s.resetModelTemperature(s.model),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.restart_alt,
                            size: 15,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _label(I18n.t('settings.base_url')),
              TextField(
                controller: _baseUrl,
                cursorColor: AppColors.primary,
                style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: s.provider.baseUrl,
                  hintStyle: TextStyle(color: AppColors.textTertiary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                onChanged: (v) => s.setBaseUrl(v),
              ),
              const SizedBox(height: 14),
              _label(I18n.t('settings.api_keys')),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: _obscure
                    ? TextField(
                        key: const ValueKey('api_key_hidden'),
                        controller: _apiKey,
                        obscureText: true,
                        maxLines: 1,
                        readOnly: false,
                        onChanged: (v) => s.setApiKey(v),
                        cursorColor: AppColors.primary,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          letterSpacing: 1.5,
                        ),
                        decoration: InputDecoration(
                          hintText: I18n.t('settings.api_keys.hint'),
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.visibility,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            tooltip: I18n.t('settings.api_keys.show'),
                            onPressed: () =>
                                setState(() => _obscure = false),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary),
                          ),
                        ),
                      )
                    : TextField(
                        key: const ValueKey('api_key_editing'),
                        controller: _apiKey,
                        obscureText: false,
                        maxLines: 3,
                        minLines: 2,
                        cursorColor: AppColors.primary,
                        autofocus: true,
                        onChanged: (v) => s.setApiKey(v),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: I18n.t('settings.api_keys.hint'),
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.visibility_off,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                            tooltip: I18n.t('settings.api_keys.hide'),
                            onPressed: () =>
                                setState(() => _obscure = true),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.border),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.primary),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              _label(I18n.t('settings.custom_provider')),
              for (final (id, name)
                  in s.providerChoices.skip(kProviders.length))
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.only(left: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 14,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => s.removeCustomProvider(id),
                        icon: Icon(
                          Icons.delete_outline,
                          size: 15,
                          color: Colors.redAccent,
                        ),
                        tooltip: I18n.t('settings.custom_provider.delete'),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addCustomProvider,
                  icon: const Icon(Icons.add_link, size: 15),
                  label: Text(I18n.t('settings.custom_provider.add')),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _label(I18n.t('settings.multi_provider')),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            I18n.t('settings.multi_provider.desc'),
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        ),
                        Switch(
                          value: s.multiProviderRouting,
                          activeThumbColor: AppColors.primary,
                          onChanged: (v) {
                            if (v && !_routesComplete(s)) {
                              final missing = _missingRoles(s);
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      I18n.t('settings.multi_provider.incomplete', {
                                        'roles': missing.join(', '),
                                      }),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    backgroundColor: Colors.redAccent.shade700,
                                  ),
                                );
                              return;
                            }
                            s.setMultiProviderRouting(v);
                          },
                        ),
                      ],
                    ),
                    if (s.multiProviderRouting) ...[
                      const SizedBox(height: 10),
                      for (var i = 0; i < _routes.length; i++)
                        _RouteCard(
                          index: i,
                          route: _routes[i],
                          settings: s,
                          onUpdate: _updateRoute,
                          onRemove: _removeRoute,
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _addRoute,
                          icon: const Icon(Icons.add, size: 15),
                          label: Text(I18n.t('settings.multi_provider.add')),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            textStyle: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ),
                      Text(
                        I18n.t('settings.multi_provider.hint'),
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 10.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (s.multiProviderRouting && !_routesComplete(s)) {
              final missing = _missingRoles(s);
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      I18n.t('settings.multi_provider.incomplete', {
                        'roles': missing.join(', '),
                      }),
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.redAccent.shade700,
                  ),
                );
              return;
            }
            Navigator.pop(context);
          },
          child: Text(
            I18n.t('git.close'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          t,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );

  Widget _segRow({
    required List<(String, String)> options,
    required String current,
    required ValueChanged<String> onSelect,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final (val, label) in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onSelect(val),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: current == val
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: current == val
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 供应商设置二级菜单的入口。
/// [settings] 由调用方显式传入：对话框运行在根 Overlay 之上，
/// 无法通过 InheritedWidget 获取 AppState。
Future<void> showProviderSettingsDialog(
  BuildContext context,
  SettingsStore settings,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => ProviderSettingsDialog(settings: settings),
  );
}

/// 小型操作按钮。
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 多供应商路由：单条规则卡片（职责 + 供应商 + 模型 + API Key）。
class _RouteCard extends StatefulWidget {
  const _RouteCard({
    required this.index,
    required this.route,
    required this.settings,
    required this.onUpdate,
    required this.onRemove,
  });

  final int index;
  final Map<String, dynamic> route;
  final SettingsStore settings;
  final void Function(int index, String key, String value) onUpdate;
  final void Function(int index) onRemove;

  @override
  State<_RouteCard> createState() => _RouteCardState();
}

class _RouteCardState extends State<_RouteCard> {
  late final TextEditingController _key;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(
      text: (widget.route['apiKey'] ?? '').toString(),
    );
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  String _roleLabel(ProviderRole role) => switch (role) {
        ProviderRole.orchestrator => '分配问题',
        ProviderRole.complex => '解决复杂问题',
        ProviderRole.simple => '解决简单问题',
        ProviderRole.daily => '日常使用',
      };

  @override
  Widget build(BuildContext context) {
    final providers = widget.settings.allProviders;
    final currentProviderId = (widget.route['providerId'] ?? '').toString();
    ProviderConfig? matched;
    for (final p in providers) {
      if (p.kind.name == currentProviderId) {
        matched = p;
        break;
      }
    }
    final currentProvider =
        matched ?? (providers.isEmpty ? kProviders.first : providers.first);
    var currentRole = ProviderRole.daily;
    for (final r in ProviderRole.values) {
      if (r.name == (widget.route['role'] ?? '').toString()) {
        currentRole = r;
        break;
      }
    }
    final currentModel = (widget.route['modelId'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<ProviderRole>(
                  value: currentRole,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: AppColors.surfaceAlt,
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  items: [
                    for (final role in ProviderRole.values)
                      DropdownMenuItem(
                        value: role,
                        child: Text(_roleLabel(role)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      widget.onUpdate(widget.index, 'role', v.name);
                    }
                  },
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: I18n.t('settings.multi_provider.remove'),
                onPressed: () => widget.onRemove(widget.index),
                icon: const Icon(Icons.delete_outline, size: 16),
                color: Colors.redAccent,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: DropdownButton<String>(
                  value: providers.any((p) => p.kind.name == currentProviderId)
                      ? currentProviderId
                      : currentProvider.kind.name,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: AppColors.surfaceAlt,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  items: [
                    for (final p in providers)
                      DropdownMenuItem(
                        value: p.kind.name,
                        child: Text(
                          p.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    ProviderConfig? p;
                    for (final x in providers) {
                      if (x.kind.name == v) {
                        p = x;
                        break;
                      }
                    }
                    widget.onUpdate(widget.index, 'providerId', v);
                    if (p != null) {
                      widget.onUpdate(widget.index, 'modelId', p.defaultModel);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<String>(
                  value: currentProvider.models
                          .any((m) => m.id == currentModel)
                      ? currentModel
                      : currentProvider.defaultModel,
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: AppColors.surfaceAlt,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                  ),
                  items: [
                    for (final m in currentProvider.models)
                      DropdownMenuItem(
                        value: m.id,
                        child: Text(
                          m.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      widget.onUpdate(widget.index, 'modelId', v);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _key,
            obscureText: true,
            maxLines: 1,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: I18n.t('settings.api_keys.hint'),
              hintStyle: TextStyle(color: AppColors.textTertiary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
            onChanged: (v) => widget.onUpdate(widget.index, 'apiKey', v),
          ),
        ],
      ),
    );
  }
}
