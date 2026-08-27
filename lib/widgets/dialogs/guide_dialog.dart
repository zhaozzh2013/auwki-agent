import 'package:flutter/material.dart';

import '../../i18n/strings.dart';
import '../../theme.dart';

/// C07：交互式引导 v2（步骤式 + 可跳过）。
Future<void> showGuideDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _GuideDialog(),
  );
}

class _GuideDialog extends StatefulWidget {
  const _GuideDialog();

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  int _page = 0;

  static const _steps = [
    (Icons.auto_awesome, 'guide.step1.title', 'guide.step1.body'),
    (Icons.tune, 'guide.step2.title', 'guide.step2.body'),
    (Icons.extension_outlined, 'guide.step3.title', 'guide.step3.body'),
    (Icons.dashboard_customize_outlined, 'guide.step4.title', 'guide.step4.body'),
  ];

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = _steps[_page];
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('guide.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              I18n.t(title),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              I18n.t(body),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  Container(
                    width: i == _page ? 18 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppColors.primary
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            I18n.t('onboarding.skip'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () {
            if (_page >= _steps.length - 1) {
              Navigator.pop(context);
            } else {
              setState(() => _page++);
            }
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(
            _page >= _steps.length - 1
                ? I18n.t('onboarding.start')
                : I18n.t('onboarding.next'),
          ),
        ),
      ],
    );
  }
}
