import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n/strings.dart';
import '../services/settings_store.dart';
import '../services/token_stats.dart';
import '../theme.dart';
import '../widgets/dialogs/model_compare_dialog.dart';
import '../widgets/dialogs/profile_dialog.dart';
import '../widgets/dialogs/provider_status_dialog.dart';

/// 用户详情页：资料、用量统计与 token 消耗图表。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppState.settingsOf(context);
    final store = AppState.chatOf(context);
    final stats = TokenStats.compute(store.conversations);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.arrow_back,
                    size: 20,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  I18n.t('profile.page.title'),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ProfileHeader(settings: settings),
            const SizedBox(height: 16),
            _StatsGrid(
              conversations: store.conversations.length,
              messages: stats.totalMessages,
              totalTokens: stats.totalTokens,
              todayTokens: stats.todayTokens,
            ),
            const SizedBox(height: 16),
            _Card(
              title: I18n.t('profile.chart.title'),
              child: _TokenBarChart(daily: stats.daily),
            ),
            const SizedBox(height: 16),
            _Card(
              title: I18n.t('profile.top.title'),
              child: stats.conversations.isEmpty
                  ? Text(
                      I18n.t('profile.top.empty'),
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 12.5,
                      ),
                    )
                  : Column(
                      children: [
                        for (final c in stats.conversations.take(8))
                          _ConversationRow(
                            stat: c,
                            maxTokens: stats.conversations.first.tokens,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _Card(
              title: I18n.t('profile.cost.title'),
              child: Row(
                children: [
                  Icon(
                    Icons.savings_outlined,
                    size: 16,
                    color: AppColors.planAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    I18n.t('profile.cost.value', {
                      'cost': '\$${stats.estimatedCostUsd.toStringAsFixed(3)}',
                    }),
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      I18n.t('profile.cost.hint'),
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.monitor_heart_outlined,
                    label: I18n.t('profile.provider_status'),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ProviderStatusDialog(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.compare_arrows,
                    label: I18n.t('profile.model_compare'),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => const ModelCompareDialog(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () => showProfileDialog(context),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 15,
                  color: AppColors.primary,
                ),
                label: Text(
                  I18n.t('profile.edit'),
                  style: TextStyle(color: AppColors.primary, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.25),
            AppColors.surfaceAlt,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              settings.userInitial,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settings.userName,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${settings.provider.label} · ${settings.model}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.conversations,
    required this.messages,
    required this.totalTokens,
    required this.todayTokens,
  });

  final int conversations;
  final int messages;
  final int totalTokens;
  final int todayTokens;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatCell(
          label: I18n.t('profile.stats.conversations'),
          value: '$conversations',
        ),
        _StatCell(
          label: I18n.t('profile.stats.messages'),
          value: '$messages',
        ),
        _StatCell(
          label: I18n.t('profile.stats.tokens'),
          value: _fmt(totalTokens),
        ),
        _StatCell(
          label: I18n.t('profile.stats.today'),
          value: _fmt(todayTokens),
          highlight: true,
        ),
      ],
    );
  }

  static String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.primary.withValues(alpha: 0.12)
              : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: highlight
                ? AppColors.primary.withValues(alpha: 0.4)
                : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: highlight ? AppColors.primary : AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TokenBarChart extends StatelessWidget {
  const _TokenBarChart({required this.daily});

  final List<MapEntry<DateTime, int>> daily;

  @override
  Widget build(BuildContext context) {
    final maxTokens = daily.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    if (maxTokens == 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            I18n.t('profile.chart.empty'),
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12.5),
          ),
        ),
      );
    }
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    const weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayLabels =
        I18n.locale.value.languageCode == 'en' ? weekdaysEn : weekdays;
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final entry in daily)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (entry.value > 0)
                      Text(
                        _fmt(entry.value),
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 9,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Container(
                      height: 4 + 110 * (entry.value / maxTokens),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(
                          alpha: entry.value > 0 ? 0.9 : 0.15,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      dayLabels[entry.key.weekday - 1],
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.stat, required this.maxTokens});

  final ConversationTokenStat stat;
  final int maxTokens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              stat.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: maxTokens == 0 ? 0.0 : stat.tokens / maxTokens,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              _fmt(stat.tokens),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
