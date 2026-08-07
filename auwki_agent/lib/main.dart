import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'i18n/strings.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'state/chat_store.dart';
import 'state/round_changes_store.dart';
import 'services/backup_service.dart';
import 'services/log_service.dart';
import 'services/settings_store.dart';
import 'theme.dart';
import 'widgets/onboarding_screen.dart';
import 'widgets/dialogs/settings_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LogService.init();
  BackupService.scheduleInitialBackup();
  ErrorWidget.builder = (details) => _FriendlyError(details: details);
  runApp(const AuwkiAgentApp());
}

class AuwkiAgentApp extends StatefulWidget {
  const AuwkiAgentApp({super.key});

  @override
  State<AuwkiAgentApp> createState() => _AuwkiAgentAppState();
}

class _AuwkiAgentAppState extends State<AuwkiAgentApp> {
  final ChatStore _store = ChatStore();
  final SettingsStore _settings = SettingsStore();
  final RoundChangesStore _roundChanges = RoundChangesStore();
  double _zoom = 1.0;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final control =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!control) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      setState(() => _zoom = (_zoom + 0.25).clamp(0.75, 2.0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      setState(() => _zoom = (_zoom - 0.25).clamp(0.75, 2.0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      setState(() => _zoom = 1.0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      final id = _store.newConversation();
      _store.activate(id);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.comma) {
      showSettingsDialog(context);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyP) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ProfilePage()),
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AppState(
      chat: _store,
      settings: _settings,
      roundChanges: _roundChanges,
      child: AnimatedBuilder(
        animation: Listenable.merge([_store, _settings, I18n.locale]),
        builder: (context, _) {
          final isDark = _settings.theme == AppTheme.dark;
          final palette = isDark ? AppPalette.dark : AppPalette.light;
          AppColors.palette = palette;
          return MaterialApp(
            title: I18n.t('app.title'),
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(isDark, palette),
            builder: (context, child) {
              final media = MediaQuery.of(context);
              return Focus(
                autofocus: true,
                onKeyEvent: _handleKey,
                child: MediaQuery(
                  data: media.copyWith(textScaler: TextScaler.linear(_zoom)),
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: !_settings.isReady
                ? const _SplashScreen()
                : _settings.hasSeenOnboarding
                ? const HomePage()
                : OnboardingScreen(settings: _settings),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(bool isDark, AppPalette palette) {
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: palette.hover,
      colorScheme: isDark
          ? ColorScheme.dark(primary: palette.primary, surface: palette.surface)
          : ColorScheme.light(
              primary: palette.primary,
              surface: palette.surface,
            ),
      textTheme: TextTheme().apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      iconTheme: IconThemeData(color: palette.textPrimary),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: palette.surfaceAlt,
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        textStyle: TextStyle(color: palette.textPrimary, fontSize: 12),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: palette.primary,
        selectionColor: palette.primary.withValues(alpha: 0.35),
        selectionHandleColor: palette.primary,
      ),
      extensions: [palette],
    );
  }
}

/// 设置加载完成前的启动画面，避免首次引导闪一下。
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 44, color: AppColors.primary),
            const SizedBox(height: 14),
            Text(
              I18n.t('app.title'),
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 友好的全局错误页（代替红屏报错）。
class _FriendlyError extends StatelessWidget {
  const _FriendlyError({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1E1E22),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sentiment_neutral, color: Colors.orangeAccent),
              const SizedBox(height: 12),
              const Text(
                'AUWKI Agent',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                I18n.t('stability.friendly_error'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
