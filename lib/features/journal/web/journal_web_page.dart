import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/widgets/sync_gate_modal.dart';
import '../../../data/models/journal_models.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/journal_bloc.dart';
import '../bloc/journal_event.dart';
import '../bloc/journal_state.dart';

class JournalWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const JournalWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          JournalBloc(journalRepository: context.read<JournalRepository>())
            ..add(LoadJournalData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<JournalBloc, JournalState>(
          builder: (context, state) {
            if (state is JournalLoading || state is JournalInitial) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            if (state is JournalError) {
              return Center(
                child: Text(
                  state.message,
                  style: const TextStyle(color: AppColors.bear),
                ),
              );
            }

            if (state is JournalLoaded) {
              return BrokerLinkGate(
                userId: userId,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 900;
                    return Column(
                      children: [
                        _WebTopNavbar(
                          onMenuPressed: onMenuPressed,
                          totalProfit: state.stats.totalProfit,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(isMobile ? 16.0 : 32.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildHeader(context, isMobile),
                                const SizedBox(height: 32),
                                _buildMetricsGrid(
                                  context,
                                  state.stats,
                                  isMobile,
                                ),
                                const SizedBox(height: 24),
                                if (isMobile) ...[
                                  _buildEquityCurveCard(
                                    context,
                                    state.stats.equityData,
                                  ),
                                  const SizedBox(height: 24),
                                  _buildAIInsightsCard(context, state.stats),
                                ] else
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _buildEquityCurveCard(
                                          context,
                                          state.stats.equityData,
                                        ),
                                      ),
                                      const SizedBox(width: 24),
                                      Expanded(
                                        flex: 1,
                                        child: _buildAIInsightsCard(
                                          context,
                                          state.stats,
                                        ),
                                      ),
                                    ],
                                  ),
                                const SizedBox(height: 24),
                                _buildHeatmapCard(
                                  context,
                                  isMobile,
                                  state.stats.heatmapData,
                                ),
                                const SizedBox(height: 24),
                                _buildTradeLogTable(
                                  context,
                                  state.trades,
                                  isMobile,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isMobile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('journal_page_title'),
          style: TextStyle(
            fontSize: isMobile ? 24 : 32,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('journal_page_desc'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: isMobile ? 12 : 14,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsGrid(
    BuildContext context,
    JournalStats stats,
    bool isMobile,
  ) {
    final profitSign = stats.totalProfit >= 0 ? '+' : '';
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: isMobile ? 2 : 4,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: isMobile ? 1.5 : 2.2,
      children: [
        _buildMetricCard(
          context.tr('total_net_profit'),
          '$profitSign\$${stats.totalProfit.toStringAsFixed(2)}',
          trend: '${stats.totalTrades} trades',
          isPositive: stats.totalProfit >= 0,
        ),
        _buildMetricCard(
          context.tr('win_rate'),
          '${stats.winRate.toStringAsFixed(1)}%',
          hasGauge: true,
        ),
        _buildMetricCard(
          context.tr('profit_factor'),
          stats.profitFactor.toStringAsFixed(2),
          hasProgress: true,
        ),
        _buildMetricCard(
          context.tr('avg_rr_ratio'),
          stats.rrRatio,
          subtitle: stats.profitFactor >= 1.5
              ? context.tr('journal_above_target')
              : context.tr('journal_below_target'),
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String label,
    String value, {
    String? trend,
    bool isPositive = true,
    bool hasGauge = false,
    bool hasProgress = false,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: isPositive && trend != null
                          ? AppColors.primary
                          : Colors.white,
                    ),
                  ),
                ),
                if (trend != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    trend,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasGauge) ...[
            const SizedBox(width: 4),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Center(
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Text(
                      value.contains('%') ? value : '0%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEquityCurveCard(BuildContext context, List<double> equityData) {
    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('equity_growth_curve'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
            ),
          ),
          const Spacer(),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: equityData.isEmpty
                ? Center(
                    child: Text(
                      context.tr('journal_no_trades'),
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 12,
                      ),
                    ),
                  )
                : CustomPaint(painter: _EquityPainter(data: equityData)),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr('start'),
                style: const TextStyle(fontSize: 12, color: Colors.white24),
              ),
              Text(
                context.tr('current'),
                style: const TextStyle(fontSize: 12, color: Colors.white24),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAIInsightsCard(BuildContext context, JournalStats stats) {
    final disciplineScore = stats.totalTrades > 0
        ? math.min(
            1.0,
            (stats.winRate / 100) * 0.6 +
                (stats.profitFactor > 1 ? 0.4 : stats.profitFactor * 0.4),
          )
        : 0.0;
    final riskAdherence = stats.totalTrades > 0
        ? math.min(
            1.0,
            stats.worstTrade.abs() > 0
                ? math.min(
                    1.0,
                    (stats.bestTrade / stats.worstTrade.abs()).clamp(0.0, 1.0) *
                            0.7 +
                        0.3,
                  )
                : 1.0,
          )
        : 0.0;

    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                context.tr('ai_performance_insight'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: context.tr('listen_ai_advice'),
                child: InkWell(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr('journal_playing_voice')),
                        backgroundColor: AppColors.primary,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.volume_up,
                      color: AppColors.primary,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Text(
              stats.aiInsight == '__NO_TRADES__'
                  ? context.tr('journal_no_trades_ai')
                  : stats.aiInsight.isNotEmpty
                  ? stats.aiInsight
                  : context.tr('journal_no_trades_ai'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontStyle: FontStyle.italic,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('psychology_score'),
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white38,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _ProgressBar(
            label: context.tr('discipline'),
            value: disciplineScore,
            color: AppColors.primary,
          ),
          const SizedBox(height: 12),
          _ProgressBar(
            label: context.tr('risk_adherence'),
            value: riskAdherence,
            color: AppColors.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapCard(
    BuildContext context,
    bool isMobile,
    List<HeatmapEntry> heatmapData,
  ) {
    final int cols = isMobile ? 12 : 24;
    const int rows = 5;

    final heatmapLookup = <String, HeatmapEntry>{};
    for (final entry in heatmapData) {
      if (entry.dayOfWeek >= 1 && entry.dayOfWeek <= 5) {
        final hourIndex = isMobile ? (entry.hourSlot ~/ 2) : entry.hourSlot;
        final key = '${entry.dayOfWeek}-$hourIndex';
        if (heatmapLookup.containsKey(key)) {
          final existing = heatmapLookup[key]!;
          heatmapLookup[key] = HeatmapEntry(
            dayOfWeek: entry.dayOfWeek,
            hourSlot: hourIndex,
            totalPnL: existing.totalPnL + entry.totalPnL,
            tradeCount: existing.tradeCount + entry.tradeCount,
          );
        } else {
          heatmapLookup[key] = entry;
        }
      }
    }

    double maxLoss = 0;
    double maxProfit = 0;
    for (final entry in heatmapLookup.values) {
      if (entry.totalPnL < 0 && entry.totalPnL.abs() > maxLoss)
        maxLoss = entry.totalPnL.abs();
      if (entry.totalPnL > 0 && entry.totalPnL > maxProfit)
        maxProfit = entry.totalPnL;
    }

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
          Text(
            context.tr('journal_heatmap_title'),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Column(
                children: [
                  Text(
                    context.tr('mon'),
                    style: const TextStyle(fontSize: 12, color: Colors.white24),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('fri'),
                    style: const TextStyle(fontSize: 12, color: Colors.white24),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  itemCount: cols * rows,
                  itemBuilder: (context, index) {
                    final day = (index ~/ cols) + 1;
                    final hour = index % cols;
                    final key = '$day-$hour';
                    final entry = heatmapLookup[key];

                    Color cellColor;
                    if (entry == null || entry.tradeCount == 0) {
                      cellColor = Colors.white.withValues(alpha: 0.03);
                    } else if (entry.totalPnL < 0) {
                      final intensity = maxLoss > 0
                          ? (entry.totalPnL.abs() / maxLoss).clamp(0.2, 1.0)
                          : 0.4;
                      cellColor = AppColors.bear.withValues(alpha: intensity);
                    } else {
                      final intensity = maxProfit > 0
                          ? (entry.totalPnL / maxProfit).clamp(0.2, 1.0)
                          : 0.4;
                      cellColor = AppColors.primary.withValues(
                        alpha: intensity,
                      );
                    }

                    return Tooltip(
                      message: entry != null && entry.tradeCount > 0
                          ? '${entry.tradeCount} ${context.tr("journal_lots")}, P&L: \$${entry.totalPnL.toStringAsFixed(2)}'
                          : context.tr('journal_no_trades_cell'),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cellColor,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.bear.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.tr('journal_heatmap_loss'),
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(width: 16),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.tr('journal_no_trades_cell'),
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
              const SizedBox(width: 16),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.tr('journal_heatmap_profit'),
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradeLogTable(
    BuildContext context,
    List<TradeRecord> trades,
    bool isMobile,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.tr('journal_trade_log'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                if (!isMobile)
                  Row(
                    children: [
                      _buildTableBtn(context.tr('journal_export_csv')),
                      const SizedBox(width: 8),
                      _buildTableBtn(context.tr('journal_filter')),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          if (trades.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                context.tr('journal_no_trades_recorded'),
                style: const TextStyle(color: Colors.white24, fontSize: 13),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: isMobile ? 600 : 0),
                child: _TradeTable(trades: trades),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableBtn(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _ProgressBar({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white54),
            ),
            Text(
              '${(value * 100).toInt()}%',
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: value,
          color: color,
          backgroundColor: Colors.white.withValues(alpha: 0.05),
          minHeight: 2,
        ),
      ],
    );
  }
}

class _EquityPainter extends CustomPainter {
  final List<double> data;
  _EquityPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFF3772FF)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path();
    double minVal = data.reduce(math.min);
    double maxVal = data.reduce(math.max);
    double range = maxVal - minVal;
    if (range == 0) range = 1;

    double dx = size.width / (data.length - 1);

    for (int i = 0; i < data.length; i++) {
      double x = i * dx;
      double y = size.height - ((data[i] - minVal) / range) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class _TradeTable extends StatelessWidget {
  final List<TradeRecord> trades;
  const _TradeTable({required this.trades});

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: IntrinsicColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
        6: IntrinsicColumnWidth(),
        7: IntrinsicColumnWidth(),
      },
      children: [
        _buildRow([
          context.tr('symbol'),
          context.tr('action'),
          context.tr('size'),
          context.tr('entry'),
          context.tr('exit'),
          context.tr('swap'),
          context.tr('slippage'),
          context.tr('net_pl'),
        ], isHeader: true),
        ...trades.map(
          (trade) => _buildRow([
            trade.symbol,
            trade.action,
            '${trade.lotSize} ${context.tr("journal_lots")}',
            trade.entryPrice.toStringAsFixed(2),
            trade.exitPrice.toStringAsFixed(2),
            trade.swap.toStringAsFixed(2),
            trade.slippage.toStringAsFixed(2),
            '${trade.netProfit >= 0 ? '+' : ''}\$${trade.netProfit.toStringAsFixed(2)}',
          ], isPositive: trade.netProfit >= 0),
        ),
      ],
    );
  }

  TableRow _buildRow(
    List<String> cells, {
    bool isHeader = false,
    bool? isPositive,
  }) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      children: cells.map((cell) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            cell,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: isHeader ? 12 : 14,
              fontWeight: isHeader ? FontWeight.w900 : FontWeight.normal,
              color: isHeader
                  ? Colors.white38
                  : (cell.contains('\$') && isPositive != null
                        ? (isPositive ? AppColors.primary : AppColors.bear)
                        : Colors.white70),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _WebTopNavbar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  final double totalProfit;
  const _WebTopNavbar({this.onMenuPressed, this.totalProfit = 0.0});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF111417),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (onMenuPressed != null)
            IconButton(
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          const Text(
            'KINETIC',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 40),
          Expanded(
            child: Text(
              'P&L: ${totalProfit >= 0 ? '+' : ''}\$${totalProfit.toStringAsFixed(2)}',
              style: const TextStyle(color: Color(0xFFc3c6d8), fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }
}
