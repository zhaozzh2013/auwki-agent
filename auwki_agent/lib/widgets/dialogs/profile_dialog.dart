import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../services/settings_store.dart';
import '../../theme.dart';

Future<void> showProfileDialog(BuildContext context) async {
  final settings = AppState.settingsOf(context);
  await showDialog(
    context: context,
    builder: (ctx) => AnimatedBuilder(
      animation: settings,
      builder: (context, _) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(I18n.t('profile.title'),
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        content: _ProfileForm(settings: settings),
      ),
    ),
  );
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({required this.settings});
  final SettingsStore settings;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final TextEditingController _name;
  late final TextEditingController _initial;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.settings.userName);
    _initial = TextEditingController(text: widget.settings.userInitial);
  }

  @override
  void dispose() {
    _name.dispose();
    _initial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initial.text.isEmpty ? '?' : _initial.text,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _initial,
                  maxLength: 2,
                  textAlign: TextAlign.center,
                  cursorColor: AppColors.primary,
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
                  decoration: InputDecoration(
                    counterText: '',
                    labelText: '头像文字',
                    labelStyle: TextStyle(color: AppColors.textSecondary),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            cursorColor: AppColors.primary,
            style: TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: '用户名',
              labelStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(I18n.t('dialog.cancel'),
                    style: TextStyle(color: AppColors.textSecondary)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () async {
                  await widget.settings.setUser(
                    _name.text.trim().isEmpty
                        ? widget.settings.userName
                        : _name.text.trim(),
                    _initial.text.trim().isEmpty
                        ? widget.settings.userInitial
                        : _initial.text.trim(),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(I18n.t('dialog.confirm'),
                    style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}