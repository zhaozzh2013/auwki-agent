import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_globals.dart';
import 'app_state.dart';
import 'i18n/strings.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'state/chat_store.dart';
import 'state/round_changes_store.dart';
import 'services/backup_service.dart';
import 'services/log_service.dart';
import 'services/scheduled_task_runner.dart';
import 'services/scheduled_task_service.dart';
import 'services/settings_store.dart';
import 'services/single_instance.dart';
import 'theme.dart';
import 'widgets/onboarding_screen.dart';
import 'widgets/dialogs/settings_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LogService.milestone('binding');
  await LogService.init();
  LogService.milestone('log_ready');

  // E04：单实例——已有实例在运行时本进程退出。
  if (!await SingleInstance.acquire()) {
    exit(0);
  }
  LogService.milestone('single_instance_ok');

  // C14：系统托盘 + 全局快捷键（失败不影响启动）。
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      windowManager.addListener(_AppWindowListener());
      await trayManager.setToolTip('AUWKI Agent');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: I18n.t('tray.show')),
            MenuItem(key: 'quit', label: I18n.t('tray.quit')),
          ],
        ),
      );
      trayManager.addListener(_AppTrayListener());
      await hotKeyManager.unregisterAll();
      await hotKeyManager.register(
        HotKey(
          key: PhysicalKeyboardKey.space,
          modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        ),
        keyDownHandler: (hotKey) async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (_) {}
  }

  BackupService.scheduleInitialBackup();
  ErrorWidget.builder = (details) => _FriendlyError(details: details);
  runApp(const AuwkiAgentApp());
}

class _AppWindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    // 关窗改为隐藏到托盘。
    await windowManager.hide();
  }
}

class _AppTrayListener extends TrayListener {
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'quit') {
      exit(0);
    }
  }
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
  int _lastAppliedRetentionDays = -1;

  @override
  void initState() {
    super.initState();
    LogService.milestone('stores_created');
    // A13：启动定时任务轮询。
    ScheduledTaskService.instance.onFire = (task) =>
        ScheduledTaskRunner.run(task, _store, _settings);
    ScheduledTaskService.instance.start();
    // F10：设置加载完成后应用对话保留策略。
    _settings.addListener(_maybeApplyRetention);
    // 缩放持久化：启动时从设置同步一次。
    _settings.addListener(_syncZoomFromSettings);
    // E04：第二个实例请求激活时给出提示。
    SingleInstance.activationRequested.addListener(_onActivationRequested);
  }

  @override
  void dispose() {
    ScheduledTaskService.instance.stop();
    _settings.removeListener(_maybeApplyRetention);
    SingleInstance.activationRequested.removeListener(_onActivationRequested);
    super.dispose();
  }

  void _maybeApplyRetention() {
    if (!_settings.isReady) return;
    final days = _settings.retentionDays;
    if (days == _lastAppliedRetentionDays) return;
    _lastAppliedRetentionDays = days;
    if (days > 0) {
      final removed = _store.applyRetention(Duration(days: days));
      if (removed > 0) {
        LogService.log('retention: removed $removed conversations (${days}d)');
      }
    }
  }

  /// 设置里的缩放值同步到界面（启动时和外部修改时）。
  void _syncZoomFromSettings() {
    if (!_settings.isReady) return;
    final saved = _settings.uiZoom;
    if (_zoom != saved) {
      setState(() => _zoom = saved);
    }
  }

  void _onActivationRequested() {
    if (!SingleInstance.activationRequested.value) return;
    appMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          I18n.t('single.instance_active'),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final control =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (!control) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final label = key.keyLabel.toLowerCase();
    // C05：快捷键可重映射。
    bool m(String action, String def) =>
        (_settings.shortcutOverride(action) ?? def) == label;
    if (m('zoom_in', '=') ||
        key == LogicalKeyboardKey.numpadAdd) {
      setState(() => _zoom = (_zoom + 0.25).clamp(0.75, 2.0));
      unawaited(_settings.setUiZoom(_zoom));
      return KeyEventResult.handled;
    }
    if (m('zoom_out', '-') ||
        key == LogicalKeyboardKey.numpadSubtract) {
      setState(() => _zoom = (_zoom - 0.25).clamp(0.75, 2.0));
      unawaited(_settings.setUiZoom(_zoom));
      return KeyEventResult.handled;
    }
    if (m('zoom_reset', '0') || key == LogicalKeyboardKey.numpad0) {
      setState(() => _zoom = 1.0);
      unawaited(_settings.setUiZoom(1.0));
      return KeyEventResult.handled;
    }
    if (m('new_chat', 'n')) {
      final id = _store.newConversation();
      _store.activate(id);
      return KeyEventResult.handled;
    }
    if (m('settings', ',')) {
      showSettingsDialog(context);
      return KeyEventResult.handled;
    }
    if (m('profile', 'p')) {
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
          final systemDark =
              MediaQuery.platformBrightnessOf(context) == Brightness.dark;
          final isDark = _settings.theme == AppTheme.dark ||
              (_settings.theme == AppTheme.system && systemDark);
          final basePalette = isDark ? AppPalette.dark : AppPalette.light;
          // bug2：强调色作用于全局调色板；bug5：高对比强化文字/边框。
          var palette = basePalette;
          if (_settings.highContrast) {
            palette = palette.copyWith(
              textPrimary: isDark ? Colors.white : Colors.black,
              textSecondary: isDark
                  ? const Color(0xFFE0E0E0)
                  : const Color(0xFF303030),
              textTertiary: isDark
                  ? const Color(0xFFBDBDBD)
                  : const Color(0xFF555555),
              border: isDark ? Colors.white54 : Colors.black45,
              bg: isDark ? const Color(0xFF000000) : Colors.white,
              sidebar: isDark ? const Color(0xFF0B0B0B) : Colors.white,
              surface: isDark ? const Color(0xFF121212) : Colors.white,
              surfaceAlt: isDark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFF0F0F0),
            );
          }
          AppColors.palette = palette;
          return MaterialApp(
            // bug4：保持 MaterialApp 稳定，设置（语言/强调色/主题）即时生效且不销毁已开对话框。
            key: const ValueKey('auwki-app'),
            title: I18n.t('app.title'),
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: appMessengerKey,
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
    final accent = palette.primary;
    final fontFamily = switch (_settings.uiFont) {
      UiFont.system => null,
      UiFont.serif => 'Georgia',
      UiFont.mono => 'Consolas',
    };
    // bug6：密度不仅改 Material 组件，还缩放基础字号，让三档肉眼可感知。
    final densityFactor = switch (_settings.uiDensity) {
      UiDensity.compact => 0.95,
      UiDensity.standard => 1.0,
      UiDensity.comfortable => 1.05,
    };
    final visualDensity = switch (_settings.uiDensity) {
      UiDensity.compact => VisualDensity.compact,
      UiDensity.standard => VisualDensity.standard,
      UiDensity.comfortable => VisualDensity.comfortable,
    };
    // C01：圆角系数作用于主题组件（对话框/卡片/按钮/底部弹层/输入框）。
    final corner = 12.0 * _settings.cornerRadius.clamp(0.5, 1.5);
    final cornerShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(corner));
    // bug10：基于完整基础字族构建，避免 TextTheme() 造成输入提示文字异常放大。
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final textTheme = base.textTheme
        .apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
          fontFamily: fontFamily,
        )
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            color: palette.textPrimary,
            fontSize:
                (base.textTheme.bodyLarge?.fontSize ?? 16) *
                densityFactor,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            color: palette.textPrimary,
            fontSize:
                (base.textTheme.bodyMedium?.fontSize ?? 14) *
                densityFactor,
          ),
        );
    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      cardTheme: CardThemeData(shape: cornerShape),
      dialogTheme: DialogThemeData(shape: cornerShape),
      bottomSheetTheme: BottomSheetThemeData(shape: cornerShape),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(shape: cornerShape),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(shape: cornerShape),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: cornerShape),
      ),
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: palette.hover,
      colorScheme: isDark
          ? ColorScheme.dark(primary: accent, surface: palette.surface)
          : ColorScheme.light(
              primary: accent,
              surface: palette.surface,
            ),
      textTheme: textTheme,
      visualDensity: visualDensity,
      // 整体缩放：默认图标大小随 Ctrl+=/- 缩放（文字由 TextScaler 统一缩放）。
      iconTheme: IconThemeData(
        color: palette.textPrimary,
        size: 24 * _zoom,
      ),
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
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: TextStyle(
          color: palette.textPrimary,
          fontSize: 12,
        ),
        backgroundColor: palette.surfaceAlt,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll(
          palette.border.withValues(alpha: 0.9),
        ),
        trackColor: WidgetStatePropertyAll(Colors.transparent),
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.2,
            colors: [
              AppColors.primary.withValues(alpha: 0.10),
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.auto_awesome,
                  size: 44,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                I18n.t('app.title'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
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
