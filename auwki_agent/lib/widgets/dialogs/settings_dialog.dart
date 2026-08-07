import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../services/ai_providers.dart';
import '../../services/app_restarter.dart';
import '../../services/app_info.dart';
import '../../services/backup_service.dart';
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
            const SizedBox(height: 18),
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
                onPressed: () => _addCustomProvider(context, s),
                icon: const Icon(Icons.add_link, size: 15),
                label: Text(I18n.t('settings.custom_provider.add')),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(fontSize: 12.5),
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
                ('system', I18n.t('settings.theme.system')),
              ],
              current: s.theme.name,
              onSelect: (v) => _onThemeSelected(
                AppTheme.values.firstWhere((t) => t.name == v),
              ),
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
            const SizedBox(height: 16),
            _label(I18n.t('settings.show_round_changes')),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      I18n.t('settings.show_round_changes.desc'),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Switch(
                    value: s.showRoundChanges,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => s.setShowRoundChanges(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.data_safety')),
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
                  Text(
                    I18n.t('settings.data_safety.desc'),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DataButton(
                          icon: Icons.backup_outlined,
                          label: I18n.t('settings.backup_now'),
                          onTap: _createBackup,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DataButton(
                          icon: Icons.file_download_outlined,
                          label: I18n.t('settings.export_data'),
                          onTap: _exportData,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DataButton(
                          icon: Icons.school_outlined,
                          label: I18n.t('settings.show_onboarding'),
                          onTap: _reshowOnboarding,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<String?>(
                    future: BackupService.latestBackupTime(),
                    builder: (context, snap) => Text(
                      I18n.t('settings.last_backup', {
                        'time':
                            snap.data ?? I18n.t('settings.last_backup.none'),
                      }),
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '${AppInfo.title} ${AppInfo.version}',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
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

  Future<void> _onThemeSelected(AppTheme theme) async {
    if (theme == widget.settings.theme) return;
    await widget.settings.setTheme(theme);
    if (!mounted) return;
    final restart = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ThemeRestartDialog(),
    );
    if (restart == true && mounted) {
      await AppRestarter.restart();
    }
  }

  Future<void> _addCustomProvider(
    BuildContext context,
    SettingsStore s,
  ) async {
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
                  _label(I18n.t('settings.custom_provider.api_style')),
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
      await s.addCustomProvider(
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
    name.dispose();
    base.dispose();
    models.dispose();
  }

  Future<void> _createBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await BackupService.createBackup();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              I18n.t('settings.backup_done', {'path': path}),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: AppColors.surfaceAlt,
          ),
        );
      if (mounted) setState(() {});
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              I18n.t('settings.backup_failed', {'error': '$e'}),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
  }

  Future<void> _exportData() async {
    final path = await FilePicker.saveFile(
      dialogTitle: I18n.t('settings.export_data'),
      fileName: 'auwki-backup-${DateTime.now().millisecondsSinceEpoch}.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path == null) return;
    try {
      await BackupService.exportTo(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              I18n.t('settings.export_done', {'path': path}),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: AppColors.surfaceAlt,
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              I18n.t('settings.backup_failed', {'error': '$e'}),
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
  }

  Future<void> _reshowOnboarding() async {
    await widget.settings.resetOnboarding();
    if (mounted) Navigator.of(context).pop();
  }

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

class _DataButton extends StatelessWidget {
  const _DataButton({
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
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.primary),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 10.5,
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

/// 主题切换后的重启提示：3 秒倒计时，超时或点击“立即重启”都会重启应用。
class _ThemeRestartDialog extends StatefulWidget {
  const _ThemeRestartDialog();

  @override
  State<_ThemeRestartDialog> createState() => _ThemeRestartDialogState();
}

class _ThemeRestartDialogState extends State<_ThemeRestartDialog> {
  static const int _timeoutSeconds = 3;

  Timer? _timer;
  int _left = _timeoutSeconds;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) _restartNow();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _restartNow() {
    _timer?.cancel();
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Icon(Icons.restart_alt, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            I18n.t('settings.theme.restart.title'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
        ],
      ),
      content: Text(
        I18n.t('settings.theme.restart.body', {'n': '$_left'}),
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          height: 1.5,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            I18n.t('settings.theme.restart.later'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: _restartNow,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(I18n.t('settings.theme.restart.now')),
        ),
      ],
    );
  }
}
