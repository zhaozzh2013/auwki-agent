import 'package:flutter/material.dart';

import 'services/settings_store.dart';
import 'state/chat_store.dart';
import 'state/round_changes_store.dart';

class AppState extends InheritedWidget {
  const AppState({
    super.key,
    required this.chat,
    required this.settings,
    required this.roundChanges,
    required super.child,
  });

  final ChatStore chat;
  final SettingsStore settings;
  final RoundChangesStore roundChanges;

  static ChatStore chatOf(BuildContext context) => _of(context).chat;

  static SettingsStore settingsOf(BuildContext context) =>
      _of(context).settings;

  static RoundChangesStore roundChangesOf(BuildContext context) =>
      _of(context).roundChanges;

  static AppState _of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<AppState>();
    assert(s != null, 'AppState not found in widget tree');
    return s!;
  }

  @override
  bool updateShouldNotify(covariant AppState oldWidget) =>
      chat != oldWidget.chat ||
      settings != oldWidget.settings ||
      roundChanges != oldWidget.roundChanges;
}
