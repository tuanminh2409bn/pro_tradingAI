import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/journal_models.dart';
import 'journal_audio_button.dart';

String journalPerformanceSummary(BuildContext context, JournalStats stats) {
  if (stats.totalTrades == 0) return context.tr('journal_no_trades_ai');
  final parts = <String>[
    context
        .tr('journal_measured_summary')
        .replaceAll('{count}', '${stats.totalTrades}')
        .replaceAll('{pnl}', stats.totalProfit.toStringAsFixed(2))
        .replaceAll('{rate}', stats.winRate.toStringAsFixed(1)),
  ];
  final loss = stats.lossConcentration;
  if (loss != null &&
      loss.dayOfWeek >= 1 &&
      loss.dayOfWeek <= 7 &&
      loss.hourSlot >= 0 &&
      loss.hourSlot <= 23 &&
      loss.tradeCount > 0 &&
      loss.totalPnL.isFinite &&
      loss.totalPnL < 0) {
    const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    parts.add(
      context
          .tr('journal_loss_summary')
          .replaceAll('{day}', context.tr(weekdays[loss.dayOfWeek - 1]))
          .replaceAll('{hour}', loss.hourSlot.toString().padLeft(2, '0'))
          .replaceAll('{count}', '${loss.tradeCount}')
          .replaceAll('{pnl}', loss.totalPnL.toStringAsFixed(2)),
    );
  }
  return parts.join(' ');
}

class JournalPerformanceMetrics extends StatelessWidget {
  final JournalStats stats;
  final bool compact;

  const JournalPerformanceMetrics({
    super.key,
    required this.stats,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final factor = stats.profitFactor;
    final payoff = stats.payoffRatio;
    final noLosses = stats.winningTrades > 0 && stats.losingTrades == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: compact ? 2 : 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent:
                140 * MediaQuery.textScalerOf(context).scale(14) / 14,
          ),
          children: [
            _MetricCard(
              label: context.tr('journal_recorded_pnl'),
              value:
                  '${stats.totalProfit >= 0 ? '+' : ''}${stats.totalProfit.toStringAsFixed(2)}',
              subtitle:
                  '${stats.totalTrades} ${context.tr('journal_trade_count')}',
              color: stats.totalProfit < 0 ? AppColors.bear : AppColors.primary,
            ),
            _MetricCard(
              label: context.tr('win_rate'),
              value: stats.totalTrades == 0
                  ? '—'
                  : '${stats.winRate.toStringAsFixed(1)}%',
            ),
            _MetricCard(
              label: context.tr('profit_factor'),
              value: factor?.isFinite == true
                  ? factor!.toStringAsFixed(2)
                  : '—',
              subtitle: factor == null
                  ? context.tr(
                      noLosses
                          ? 'journal_no_losing_trades'
                          : 'journal_ratio_unavailable',
                    )
                  : null,
            ),
            _MetricCard(
              label: context.tr('journal_average_win_loss'),
              value: payoff?.isFinite == true
                  ? '${payoff!.toStringAsFixed(2)}×'
                  : '—',
              subtitle: context.tr(
                payoff == null
                    ? 'journal_payoff_requires_both'
                    : 'journal_break_even_excluded',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          context.tr('journal_pnl_currency_unverified'),
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.value,
    this.subtitle,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    ),
  );
}

class JournalPerformanceSummary extends StatelessWidget {
  final JournalStats stats;
  const JournalPerformanceSummary({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final summary = journalPerformanceSummary(context, stats);
    return Container(
      constraints: const BoxConstraints(minHeight: 300),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.tr('journal_summary_title'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primary,
                  ),
                ),
              ),
              JournalAudioButton(
                insight: stats.totalTrades == 0 ? '__NO_TRADES__' : summary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            summary,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (stats.totalTrades > 0) ...[
            const SizedBox(height: 16),
            Text(
              context
                  .tr('journal_outcome_counts')
                  .replaceAll('{wins}', '${stats.winningTrades}')
                  .replaceAll('{losses}', '${stats.losingTrades}')
                  .replaceAll('{flat}', '${stats.breakEvenTrades}'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            context.tr('journal_risk_unmeasured'),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
