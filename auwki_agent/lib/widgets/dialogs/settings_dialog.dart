import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../services/ai_providers.dart';
import '../../services/settings_store.dart';
import '../../theme.dart';

Future<void> showSettingsDialog(BuildContext context) async {
  final settings = AppState.settingsOf(context);
  await showDialog(
    context: context,
    builder: (ctx) => _SettingsDialog(settings: settings),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.settings});
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          I18n.t('settings.title'),
          style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
        ),
        content: _SettingsForm(settings: settings),
      ),
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.settings});
  final SettingsStore settings;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final TextEditingController _apiKey;
  late final TextEditingController _baseUrl;
  bool _obscure = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _apiKey = TextEditingController();
    _baseUrl = TextEditingController();
  }

  void _ensureInitialized() {
    if (_initialized) return;
    _apiKey.text = widget.settings.apiKey;
    _baseUrl.text = widget.settings.baseUrl;
    _initialized = true;
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureInitialized();
    final s = widget.settings;
    return SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(I18n.t('settings.provider')),
            DropdownButton<String>(
              value: s.provider.kind.name,
              isExpanded: true,
              dropdownColor: AppColors.surfaceAlt,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              items: [
                for (final p in kProviders)
                  DropdownMenuItem(value: p.kind.name, child: Text(p.label)),
              ],
              onChanged: (v) async {
                if (v != null) await s.setProvider(v);
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
            const SizedBox(height: 16),
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
            ),
            const SizedBox(height: 16),
            _label('API Key'),
            TextField(
              controller: _apiKey,
              obscureText: _obscure,
              cursorColor: AppColors.primary,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'sk-...',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.language')),
            _segRow(
              options: [
                ('zh_CN', I18n.t('settings.language.zh')),
                ('en_US', 'English'),
              ],
              current:
                  '${I18n.locale.value.languageCode}_${I18n.locale.value.countryCode ?? ''}',
              onSelect: (code) {
                final parts = code.split('_');
                s.setLocale(
                  Locale(parts[0], parts.length > 1 ? parts[1] : null),
                );
              },
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.theme')),
            _segRow(
              options: [
                ('dark', I18n.t('settings.theme.dark')),
                ('light', I18n.t('settings.theme.light')),
              ],
              current: s.theme.name,
              onSelect: (v) =>
                  s.setTheme(AppTheme.values.firstWhere((t) => t.name == v)),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.enter_to_send')),
            _segRow(
              options: [
                ('on', I18n.t('settings.enter.send')),
                ('off', I18n.t('settings.enter.newline')),
              ],
              current: s.enterToSend ? 'on' : 'off',
              onSelect: (v) => s.setEnterToSend(v == 'on'),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.cost_mode')),
            _segRow(
              options: [
                ('poor', I18n.t('settings.cost.poor')),
                ('medium', I18n.t('settings.cost.medium')),
                ('max', I18n.t('settings.cost.max')),
              ],
              current: s.costMode.name,
              onSelect: (v) => s.setCostMode(
                CostMode.values.firstWhere((mode) => mode.name == v),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    I18n.t('dialog.cancel'),
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    await s.setBaseUrl(_baseUrl.text);
                    await s.setApiKey(_apiKey.text.trim());
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text(
                    I18n.t('dialog.confirm'),
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
