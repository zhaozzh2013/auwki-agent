import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../theme.dart';

enum ThinkingLevel {
  fast('thinking.fast'),
  thinking('thinking.thinking'),
  deep('thinking.deep'),
  max('thinking.max'),
  flagship('thinking.flagship');

  const ThinkingLevel(this.labelKey);
  final String labelKey;

  String get label => I18n.t(labelKey);
}

class ThinkingSlider extends StatelessWidget {
  const ThinkingSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent,
  });

  final ThinkingLevel value;
  final ValueChanged<ThinkingLevel> onChanged;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final idx = ThinkingLevel.values.indexOf(value);
    final c = accent ?? AppColors.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 30,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 5,
              activeTrackColor: c,
              inactiveTrackColor: AppColors.border,
              thumbColor: Colors.white,
              overlayColor: c.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              min: 0,
              max: 4,
              divisions: 4,
              value: idx.toDouble(),
              onChanged: (v) =>
                  onChanged(ThinkingLevel.values[v.round().clamp(0, 4)]),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            for (var i = 0; i < ThinkingLevel.values.length; i++)
              Expanded(
                child: _LevelLabel(
                  level: ThinkingLevel.values[i],
                  active: i == idx,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LevelLabel extends StatelessWidget {
  const _LevelLabel({required this.level, required this.active});

  final ThinkingLevel level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Text(
      level.label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: active ? AppColors.textPrimary : AppColors.textTertiary,
        fontSize: 13,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
