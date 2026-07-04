import 'package:flutter/material.dart';

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
            home: HomePage(),
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
          ? ColorScheme.dark(
              primary: palette.primary,
              surface: palette.surface,
            )
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
      extensions: [palette],
    );
  }
}