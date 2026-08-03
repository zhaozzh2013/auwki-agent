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
    this.onChangeEnd,
    this.accent,
  });

  final ThinkingLevel value;
  final ValueChanged<ThinkingLevel> onChanged;
  final ValueChanged<ThinkingLevel>? onChangeEnd;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final idx = ThinkingLevel.values.indexOf(value);
    final c = accent ?? AppColors.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 26,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              activeTrackColor: c,
              inactiveTrackColor: AppColors.border,
              thumbColor: Colors.white,
              overlayColor: c.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              min: 0,
              max: 4,
              divisions: 4,
              value: idx.toDouble(),
              onChanged: (v) =>
                  onChanged(ThinkingLevel.values[v.round().clamp(0, 4)]),
              onChangeEnd: onChangeEnd == null
                  ? null
                  : (v) =>
                        onChangeEnd!(ThinkingLevel.values[v.round().clamp(0, 4)]),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (var i = 0; i < ThinkingLevel.values.length; i++)
              Expanded(
                child: _LevelLabel(
                  level: ThinkingLevel.values[i],
                  active: i == idx,
                  onTap: () {
                    final level = ThinkingLevel.values[i];
                    onChanged(level);
                    onChangeEnd?.call(level);
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _LevelLabel extends StatelessWidget {
  const _LevelLabel({
    required this.level,
    required this.active,
    this.onTap,
  });

  final ThinkingLevel level;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        level.label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: active ? AppColors.textPrimary : AppColors.textTertiary,
          fontSize: 12,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
