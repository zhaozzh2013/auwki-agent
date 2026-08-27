import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../services/app_info.dart';
import '../../services/backup_service.dart';
import '../../services/diagnostics_service.dart';
import '../../services/settings_store.dart';
import '../../state/chat_store.dart';
import '../../theme.dart';
import 'logs_dialog.dart';
import 'provider_settings_dialog.dart';
import 'restore_dialog.dart';
import 'shortcuts_dialog.dart';
import 'storage_dialog.dart';
import 'agent_tools_dialog.dart';

Future<void> showSettingsDialog(BuildContext context) async {
  final settings = AppState.settingsOf(context);
  final store = AppState.chatOf(context);
  await showDialog(
    context: context,
    builder: (ctx) => _SettingsDialog(settings: settings, store: store),
  );
}

class _SettingsDialog extends StatelessWidget {
  const _SettingsDialog({required this.settings, required this.store});
  final SettingsStore settings;
  final ChatStore store;

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
        content: _SettingsForm(settings: settings, store: store),
      ),
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.settings, required this.store});
  final SettingsStore settings;
  final ChatStore store;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final TextEditingController _proxyHost;
  late final TextEditingController _proxyPort;
  int _versionTaps = 0;
  DateTime _lastVersionTap = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _proxyHost = TextEditingController();
    _proxyPort = TextEditingController();
  }

  @override
  void dispose() {
    _proxyHost.dispose();
    _proxyPort.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(I18n.t('settings.provider_manage')),
            Material(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => showProviderSettingsDialog(context, s),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.dns_outlined,
                        size: 17,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              I18n.t('settings.provider_manage'),
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              I18n.t('settings.provider_manage.desc'),
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.preset')),
            _segRow(
              options: [
                ('general', I18n.t('settings.preset.general')),
                ('coding', I18n.t('settings.preset.coding')),
                ('writing', I18n.t('settings.preset.writing')),
                ('translation', I18n.t('settings.preset.translation')),
              ],
              current: s.preset.name,
              onSelect: (v) => s.setPreset(
                PromptPreset.values.firstWhere((p) => p.name == v),
              ),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.language')),
            _segRow(
              options: [
                ('zh_CN', I18n.t('settings.language.zh')),
                ('en_US', 'English'),
                ('ja_JP', '日本語'),
              ],
              current:
                  '${I18n.locale.value.languageCode}_${I18n.locale.value.countryCode ?? ''}',
              onSelect: (code) {
                _onLocaleSelected(code);
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
            _label(I18n.t('settings.accent')),
            Wrap(
              spacing: 10,
              children: [
                for (var i = 0; i < 6; i++)
                  GestureDetector(
                    onTap: () => _applyWithOverlay(() => s.setThemeAccent(i)),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _accentColor(i),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: s.themeAccent == i
                              ? AppColors.textPrimary
                              : AppColors.border,
                          width: s.themeAccent == i ? 2 : 1,
                        ),
                      ),
                      child: s.themeAccent == i
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _label(I18n.t('settings.corner_radius')),
            Slider(
              value: s.cornerRadius,
              min: 0.5,
              max: 1.5,
              divisions: 4,
              activeColor: AppColors.primary,
              onChanged: (v) => s.setCornerRadius(v),
            ),
            _label(I18n.t('settings.density')),
            _segRow(
              options: [
                ('compact', I18n.t('settings.density.compact')),
                ('standard', I18n.t('settings.density.standard')),
                ('comfortable', I18n.t('settings.density.comfortable')),
              ],
              current: s.uiDensity.name,
              onSelect: (v) => s.setUiDensity(
                UiDensity.values.firstWhere((x) => x.name == v),
              ),
            ),
            const SizedBox(height: 12),
            _label(I18n.t('settings.font')),
            _segRow(
              options: [
                ('system', I18n.t('settings.font.system')),
                ('serif', I18n.t('settings.font.serif')),
                ('mono', I18n.t('settings.font.mono')),
              ],
              current: s.uiFont.name,
              onSelect: (v) => s.setUiFont(
                UiFont.values.firstWhere((x) => x.name == v),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    I18n.t('settings.high_contrast'),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Switch(
                  value: s.highContrast,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => s.setHighContrast(v),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showShortcutsDialog(context, s),
                icon: const Icon(Icons.keyboard_outlined, size: 15),
                label: Text(I18n.t('shortcuts.title')),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
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
            _label(I18n.t('settings.debug_mode')),
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
                      I18n.t('settings.debug_mode.desc'),
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Switch(
                    value: s.debugMode,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => s.setDebugMode(v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('settings.proxy')),
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
                          I18n.t('settings.proxy.desc'),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                      Switch(
                        value: s.proxyPort > 0 && s.proxyHost.isNotEmpty,
                        activeThumbColor: AppColors.primary,
                        // 开关与输入框联动：host/port 实时保存，开关直接生效。
                        onChanged: (v) {
                          if (v) {
                            final host = _proxyHost.text.trim();
                            final port = int.tryParse(_proxyPort.text) ?? 0;
                            if (host.isEmpty || port <= 0) {
                              _snack(I18n.t('settings.proxy.need_host_port'));
                              return;
                            }
                            s.setProxy(host, port);
                          } else {
                            s.setProxy('', 0);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _proxyHost,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: I18n.t('settings.proxy.host'),
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary,
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.primary),
                            ),
                          ),
                          // 实时保存：输入即生效，无需点保存。
                          onChanged: (_) {
                            if (_proxyHost.text.trim().isNotEmpty ||
                                _proxyPort.text.isNotEmpty) {
                              s.setProxy(
                                _proxyHost.text,
                                int.tryParse(_proxyPort.text) ?? 0,
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _proxyPort,
                          keyboardType: TextInputType.number,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: I18n.t('settings.proxy.port'),
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary,
                            ),
                            enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.border),
                            ),
                            focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: AppColors.primary),
                            ),
                          ),
                          onChanged: (_) {
                            if (_proxyHost.text.trim().isNotEmpty ||
                                _proxyPort.text.isNotEmpty) {
                              s.setProxy(
                                _proxyHost.text,
                                int.tryParse(_proxyPort.text) ?? 0,
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _label(I18n.t('agent.tools.title')),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.extension_outlined,
                    size: 16,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      I18n.t('agent.tools.title.desc'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showAgentToolsDialog(context, s),
                    child: Text(
                      I18n.t('dialog.open'),
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12.5,
                      ),
                    ),
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DataButton(
                          icon: Icons.terminal,
                          label: I18n.t('settings.view_logs'),
                          onTap: _showLogs,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DataButton(
                          icon: Icons.storage_outlined,
                          label: I18n.t('settings.storage'),
                          onTap: _showStorage,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DataButton(
                          icon: Icons.medical_services_outlined,
                          label: I18n.t('settings.diagnostics'),
                          onTap: _exportDiagnostics,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _DataButton(
                          icon: Icons.settings_backup_restore,
                          label: I18n.t('settings.restore'),
                          onTap: _showRestore,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DataButton(
                          icon: Icons.south_west,
                          label: I18n.t('settings.import'),
                          onTap: _importData,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          I18n.t('settings.retention'),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<int>(
                        // 历史配置/导入可能带任意天数，取最近的预设项避免断言崩溃。
                        value: const [0, 30, 90, 180, 365].reduce(
                          (a, b) =>
                              (s.retentionDays - a).abs() <
                                  (s.retentionDays - b).abs()
                              ? a
                              : b,
                        ),
                        isDense: true,
                        dropdownColor: AppColors.surfaceAlt,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 0,
                            child: Text(I18n.t('settings.retention_forever')),
                          ),
                          DropdownMenuItem(
                            value: 30,
                            child: Text(I18n.t('settings.retention_30d')),
                          ),
                          DropdownMenuItem(
                            value: 90,
                            child: Text(I18n.t('settings.retention_90d')),
                          ),
                          DropdownMenuItem(
                            value: 180,
                            child: Text(I18n.t('settings.retention_180d')),
                          ),
                          DropdownMenuItem(
                            value: 365,
                            child: Text(I18n.t('settings.retention_365d')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) s.setRetentionDays(v);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onVersionTap(context),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    '${AppInfo.title} ${AppInfo.version}',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
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
                  onPressed: () => Navigator.pop(context),
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

  Color _accentColor(int index) {
    const colors = [
      Color(0xFFE5484D),
      Color(0xFF3B82F6),
      Color(0xFF22C55E),
      Color(0xFFA855F7),
      Color(0xFFF97316),
      Color(0xFFEC4899),
    ];
    return colors[index.clamp(0, colors.length - 1)];
  }

  Future<void> _onThemeSelected(AppTheme theme) async {
    if (theme == widget.settings.theme) return;
    // bug4：即时生效 + 全窗口覆盖动画，且停留在设置页。
    await _applyWithOverlay(() => widget.settings.setTheme(theme));
  }

  void _onVersionTap(BuildContext context) {
    final now = DateTime.now();
    if (now.difference(_lastVersionTap).inMilliseconds > 1500) {
      _versionTaps = 0;
    }
    _lastVersionTap = now;
    _versionTaps++;
    if (_versionTaps < 5) return;
    _versionTaps = 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Icon(Icons.celebration, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              I18n.t('easter.title'),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
            ),
          ],
        ),
        content: Text(
          I18n.t('easter.body'),
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              I18n.t('easter.ok'),
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onLocaleSelected(String code) async {
    final parts = code.split('_');
    final loc = Locale(parts[0], parts.length > 1 ? parts[1] : null);
    if (loc == I18n.locale.value) return;
    await _applyWithOverlay(() => widget.settings.setLocale(loc));
  }

  /// 覆盖全窗口做短暂过渡，期间应用设置变更，随后移除覆盖层。
  Future<void> _applyWithOverlay(Future<void> Function() apply) async {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => const IgnorePointer(
        child: ColoredBox(color: Colors.black54),
      ),
    );
    overlay.insert(entry);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    try {
      await apply();
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      entry.remove();
    }
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

  void _showLogs() {
    showDialog<void>(
      context: context,
      builder: (_) => const LogsDialog(),
    );
  }

  void _showStorage() {
    showDialog<void>(
      context: context,
      builder: (_) => const StorageDialog(),
    );
  }

  void _showRestore() {
    showDialog<void>(
      context: context,
      builder: (_) => RestoreDialog(
        settings: widget.settings,
        store: widget.store,
      ),
    );
  }

  void _importData() {
    importConversationsDialog(context, widget.store);
  }

  Future<void> _exportDiagnostics() async {
    final path = await FilePicker.saveFile(
      dialogTitle: I18n.t('settings.diagnostics'),
      fileName:
          'auwki-diagnostics-${DateTime.now().millisecondsSinceEpoch}.json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (path == null) return;
    try {
      final data = await DiagnosticsService.collect(
        settingsExport: widget.settings.toExportMap(),
      );
      await DiagnosticsService.saveTo(path, data);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              I18n.t('settings.diagnostics.done', {'path': path}),
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
              '${I18n.t('settings.diagnostics.failed')} $e',
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: Colors.redAccent.shade700,
          ),
        );
    }
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
