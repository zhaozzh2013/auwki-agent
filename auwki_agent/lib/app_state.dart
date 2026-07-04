import 'package:flutter/material.dart';

import 'services/settings_store.dart';
import 'state/chat_store.dart';

class AppState extends InheritedWidget {
  const AppState({
    super.key,
    required this.chat,
    required this.settings,
    required super.child,
  });

  final ChatStore chat;
  final SettingsStore settings;

  static ChatStore chatOf(BuildContext context) => _of(context).chat;

  static SettingsStore settingsOf(BuildContext context) =>
      _of(context).settings;

  static AppState _of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppState>();
    assert(s != null, 'AppState not found in widget tree');
    return s!;
  }

  @override
  bool updateShouldNotify(covariant AppState oldWidget) =>
      chat != oldWidget.chat || settings != oldWidget.settings;
}