import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme.dart';

/// 命令面板动作项。
class PaletteAction {
  const PaletteAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.keywords = const [],
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final List<String> keywords;
}

/// Ctrl+K 快速命令面板：搜索并执行操作。
Future<void> showCommandPalette(
  BuildContext context, {
  required List<PaletteAction> actions,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CommandPaletteDialog(actions: actions),
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.actions});

  final List<PaletteAction> actions;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PaletteAction> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.actions;
    return widget.actions.where((a) {
      return a.label.toLowerCase().contains(q) ||
          a.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  void _run(PaletteAction a) {
    Navigator.of(context).pop();
    a.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      title: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: I18n.t('palette.hint'),
          hintStyle: TextStyle(color: AppColors.textTertiary),
          prefixIcon: Icon(Icons.search, color: AppColors.textSecondary),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.border),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.primary),
          ),
        ),
        onChanged: (v) => setState(() => _query = v),
        onSubmitted: (_) {
          if (items.isNotEmpty) _run(items.first);
        },
      ),
      content: SizedBox(
        width: 420,
        height: 320,
        child: items.isEmpty
            ? Center(
                child: Text(
                  I18n.t('palette.no_result'),
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 13,
                  ),
                ),
              )
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: AppColors.border,
                ),
                itemBuilder: (context, i) {
                  final a = items[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(a.icon, size: 18, color: AppColors.primary),
                    title: Text(
                      a.label,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () => _run(a),
                  );
                },
              ),
      ),
    );
  }
}
