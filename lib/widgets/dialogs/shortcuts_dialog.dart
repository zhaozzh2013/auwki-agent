import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/strings.dart';
import '../../services/settings_store.dart';
import '../../theme.dart';

/// C05：快捷键重映射——点击“设置”后按下一个键即可捕获。
Future<void> showShortcutsDialog(
  BuildContext context,
  SettingsStore settings,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ShortcutsDialog(settings: settings),
  );
}

class _ShortcutsDialog extends StatefulWidget {
  const _ShortcutsDialog({required this.settings});

  final SettingsStore settings;

  @override
  State<_ShortcutsDialog> createState() => _ShortcutsDialogState();
}

class _ShortcutsDialogState extends State<_ShortcutsDialog> {
  static const _actions = [
    ('new_chat', 'Ctrl+N'),
    ('settings', 'Ctrl+,'),
    ('profile', 'Ctrl+P'),
    ('zoom_in', 'Ctrl+='),
    ('zoom_out', 'Ctrl+-'),
    ('zoom_reset', 'Ctrl+0'),
  ];

  String? _capturing;
  final Map<String, FocusNode> _nodes = {};

  @override
  void dispose() {
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  FocusNode _node(String action) =>
      _nodes.putIfAbsent(action, FocusNode.new);

  KeyEventResult _onKey(String action, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final label = event.logicalKey.keyLabel.toLowerCase();
    const modifiers = {
      'control',
      'meta',
      'shift',
      'alt',
      'arrowup',
      'arrowdown',
      'arrowleft',
      'arrowright',
      'escape',
      'tab',
    };
    if (modifiers.contains(label) || label.isEmpty) {
      return KeyEventResult.ignored;
    }
    widget.settings.setShortcutOverride(action, label);
    setState(() => _capturing = null);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(
        I18n.t('shortcuts.title'),
        style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (action, def) in _actions)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$action ($def)',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Text(
                      widget.settings.shortcutOverride(action) ??
                          def.split('+').last,
                      style: TextStyle(
                        color: _capturing == action
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Focus(
                      focusNode: _node(action),
                      onKeyEvent: (node, event) => _onKey(action, event),
                      child: InkWell(
                        onTap: () {
                          setState(() => _capturing = action);
                          _node(action).requestFocus();
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _capturing == action
                                ? AppColors.primary.withValues(alpha: 0.18)
                                : AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _capturing == action
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          child: Text(
                            _capturing == action
                                ? I18n.t('shortcuts.press')
                                : I18n.t('shortcuts.set'),
                            style: TextStyle(
                              color: _capturing == action
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.settings.shortcutOverride(action) != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.close,
                          size: 15,
                          color: AppColors.textTertiary,
                        ),
                        onPressed: () {
                          widget.settings.setShortcutOverride(action, null);
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            if (_capturing != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  I18n.t('shortcuts.hint'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            I18n.t('dialog.cancel'),
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
