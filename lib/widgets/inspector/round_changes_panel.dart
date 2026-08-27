import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../theme.dart';

/// 右侧面板：本轮更改。
class RoundChangesPanel extends StatelessWidget {
  const RoundChangesPanel({super.key, required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final store = AppState.roundChangesOf(context);
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final records = store.records;
        if (records.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                I18n.t('changes.empty'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          );
        }
        final latest = records.last;
        final history = records.reversed.skip(1).take(10).toList();
        return ListView(
          padding: const EdgeInsets.only(top: 2),
          children: [
            _ChangeCard(
              title: I18n.t('changes.latest'),
              time: _formatTime(latest.time),
              lines: latest.lines,
              accent: accent,
              highlight: true,
            ),
            if (history.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                I18n.t('changes.history'),
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              for (final r in history) ...[
                _ChangeCard(
                  title: I18n.t('changes.round_at', {
                    'time': _formatTime(r.time),
                  }),
                  time: '',
                  lines: r.lines,
                  accent: accent,
                  highlight: false,
                ),
                const SizedBox(height: 8),
              ],
            ],
          ],
        );
      },
    );
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }
}

class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.title,
    required this.time,
    required this.lines,
    required this.accent,
    required this.highlight,
  });

  final String title;
  final String time;
  final List<String> lines;
  final Color accent;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? AppColors.surfaceAlt : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight ? accent.withValues(alpha: 0.45) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: highlight ? accent : AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (time.isNotEmpty)
                Text(
                  time,
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                line,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
