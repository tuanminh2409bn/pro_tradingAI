import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/journal_models.dart';

Map<String, HeatmapEntry> journalHeatmapBuckets(
  List<HeatmapEntry> entries, {
  required bool compact,
}) {
  final result = <String, HeatmapEntry>{};
  final invalidKeys = <String>{};
  for (final entry in entries) {
    if (entry.dayOfWeek < 1 ||
        entry.dayOfWeek > 7 ||
        entry.hourSlot < 0 ||
        entry.hourSlot > 23 ||
        entry.tradeCount <= 0 ||
        !entry.totalPnL.isFinite) {
      continue;
    }
    final bucket = compact ? entry.hourSlot ~/ 2 : entry.hourSlot;
    final key = '${entry.dayOfWeek}-$bucket';
    if (invalidKeys.contains(key)) continue;
    final previous = result[key];
    final total = (previous?.totalPnL ?? 0) + entry.totalPnL;
    if (!total.isFinite) {
      result.remove(key);
      invalidKeys.add(key);
      continue;
    }
    result[key] = HeatmapEntry(
      dayOfWeek: entry.dayOfWeek,
      hourSlot: compact ? bucket * 2 : bucket,
      totalPnL: total,
      tradeCount: (previous?.tradeCount ?? 0) + entry.tradeCount,
    );
  }
  return result;
}

class JournalHeatmap extends StatelessWidget {
  final List<HeatmapEntry> data;
  final bool compact;
  const JournalHeatmap({super.key, required this.data, required this.compact});

  @override
  Widget build(BuildContext context) {
    final columns = compact ? 12 : 24;
    final buckets = journalHeatmapBuckets(data, compact: compact);
    var maxLoss = 0.0;
    var maxProfit = 0.0;
    for (final entry in buckets.values) {
      if (entry.totalPnL < 0 && entry.totalPnL.abs() > maxLoss) {
        maxLoss = entry.totalPnL.abs();
      }
      if (entry.totalPnL > maxProfit) maxProfit = entry.totalPnL;
    }
    const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('journal_heatmap_title'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'UTC',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              const labelWidth = 38.0;
              const gap = 12.0;
              final cellSize =
                  (constraints.maxWidth -
                      labelWidth -
                      gap -
                      2 * (columns - 1)) /
                  columns;
              return Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Column(
                      children: [
                        for (final day in days)
                          SizedBox(
                            height: cellSize + 2,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                context.tr(day),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: gap),
                  Expanded(
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 2,
                        crossAxisSpacing: 2,
                      ),
                      itemCount: columns * 7,
                      itemBuilder: (context, index) {
                        final day = index ~/ columns + 1;
                        final bucket = index % columns;
                        final entry = buckets['$day-$bucket'];
                        final hour = compact ? bucket * 2 : bucket;
                        final endHour = compact ? hour + 1 : hour;
                        final time =
                            '${hour.toString().padLeft(2, '0')}:00–${endHour.toString().padLeft(2, '0')}:59 UTC';
                        final prefix = '${context.tr(days[day - 1])} $time';
                        final message = entry == null
                            ? '$prefix · ${context.tr('journal_no_trades_cell')}'
                            : '$prefix · ${entry.tradeCount} ${context.tr('journal_trade_count')} · P&L: ${entry.totalPnL.toStringAsFixed(2)}';
                        final Color color;
                        if (entry == null) {
                          color = Colors.white.withValues(alpha: 0.03);
                        } else if (entry.totalPnL < 0) {
                          color = AppColors.bear.withValues(
                            alpha: (entry.totalPnL.abs() / maxLoss).clamp(
                              0.2,
                              1.0,
                            ),
                          );
                        } else if (entry.totalPnL > 0) {
                          color = AppColors.primary.withValues(
                            alpha: (entry.totalPnL / maxProfit).clamp(0.2, 1.0),
                          );
                        } else {
                          color = Colors.white.withValues(alpha: 0.22);
                        }
                        return Tooltip(
                          key: ValueKey('journal-heatmap-$day-$bucket'),
                          message: message,
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 50),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  '00:00',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
                Text(
                  '23:59',
                  style: TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _legend(
                context,
                'journal_heatmap_loss',
                AppColors.bear.withValues(alpha: 0.6),
              ),
              _legend(
                context,
                'journal_no_trades_cell',
                Colors.white.withValues(alpha: 0.03),
              ),
              _legend(
                context,
                'journal_filter_flat',
                Colors.white.withValues(alpha: 0.22),
              ),
              _legend(
                context,
                'journal_heatmap_profit',
                AppColors.primary.withValues(alpha: 0.6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(BuildContext context, String label, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        context.tr(label),
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
    ],
  );
}
