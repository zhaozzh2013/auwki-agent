import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'i18n/strings.dart';
import 'pages/home_page.dart';
import 'state/chat_store.dart';
import 'services/settings_store.dart';
import 'theme.dart';

void main() {
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
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return AppState(
      chat: _store,
      settings: _settings,
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
            home: const HomePage(),
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
