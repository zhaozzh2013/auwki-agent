import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../services/settings_store.dart';
import '../theme.dart';

/// 首次启动引导：欢迎 + 功能速览，展示一次后进入主页。
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await widget.settings.setOnboardingSeen();
  }

  void _next() {
    if (_page >= _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  List<({IconData icon, String title, String body})> get _pages => [
    (
      icon: Icons.auto_awesome,
      title: I18n.t('onboarding.page1.title'),
      body: I18n.t('onboarding.page1.body'),
    ),
    (
      icon: Icons.tune,
      title: I18n.t('onboarding.page2.title'),
      body: I18n.t('onboarding.page2.body'),
    ),
    (
      icon: Icons.hub_outlined,
      title: I18n.t('onboarding.page3.title'),
      body: I18n.t('onboarding.page3.body'),
    ),
    (
      icon: Icons.space_dashboard_outlined,
      title: I18n.t('onboarding.page4.title'),
      body: I18n.t('onboarding.page4.body'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final isLast = _page == pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            page.icon,
                            size: 44,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == _page ? 20 : 7,
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
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 20),
              child: Row(
                children: [
                  if (!isLast)
                    TextButton(
                      onPressed: _finish,
                      child: Text(
                        I18n.t('onboarding.skip'),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 1),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: _next,
                    child: Text(
                      isLast
                          ? I18n.t('onboarding.start')
                          : I18n.t('onboarding.next'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
