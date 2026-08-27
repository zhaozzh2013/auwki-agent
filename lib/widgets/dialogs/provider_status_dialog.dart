import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../i18n/strings.dart';
import '../../services/provider_stats.dart';
import '../../theme.dart';

/// G09：供应商状态页——本次会话内的成功率与平均延迟。
class ProviderStatusDialog extends StatelessWidget {
  const ProviderStatusDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppState.settingsOf(context);
    return AnimatedBuilder(
      animation: ProviderStatsService.instance,
      builder: (context, _) {
        final overview = ProviderStatsService.instance.overview(
          settings.providerId,
        );
        final perModel = ProviderStatsService.instance.perModel(
          settings.providerId,
        );
        return AlertDialog(
          backgroundColor: AppColors.surface,
          titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          title: Row(
            children: [
              Icon(Icons.monitor_heart_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                I18n.t('status.title'),
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: overview.count == 0
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text(
                        I18n.t('status.empty'),
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _stat(
                                I18n.t('status.requests'),
                                '${overview.count}',
                              ),
                            ),
                            Expanded(
                              child: _stat(
                                I18n.t('status.success_rate'),
                                '${(overview.avgLatency >= 0 ? overview.okCount / overview.count * 100 : 0).toStringAsFixed(0)}%',
                              ),
                            ),
                            Expanded(
                              child: _stat(
                                I18n.t('status.avg_latency'),
                                '${overview.avgLatency.toStringAsFixed(0)}ms',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        I18n.t('status.per_model'),
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final s in perModel)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  s.model,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Text(
                                I18n.t('status.req_count', {
                                  'count': '${s.count}',
                                  'ok': '${s.okCount}',
                                }),
                                style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  '${s.avgLatency.toStringAsFixed(0)}ms',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => ProviderStatsService.instance.clear(),
                          icon: const Icon(Icons.delete_outline, size: 15),
                          label: Text(I18n.t('status.clear')),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            textStyle: const TextStyle(fontSize: 12),
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
                I18n.t('git.close'),
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(color: AppColors.textTertiary, fontSize: 10.5),
        ),
      ],
    );
  }
}
