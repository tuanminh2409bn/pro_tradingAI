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
import 'widgets/journal_audio_button.dart';
import 'widgets/journal_equity_painter.dart';
import 'widgets/journal_heatmap.dart';
import 'widgets/journal_trade_log.dart';

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
                  context.tr(state.message),
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
                                JournalHeatmap(
                                  data: buildJournalHeatmap(state.trades),
                                  compact: isMobile,
                                ),
                                const SizedBox(height: 24),
                                JournalTradeLog(
                                  trades: state.trades,
                                  scopeId: userId,
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
            context.tr('journal_closed_pnl_curve'),
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
                : CustomPaint(painter: JournalEquityPainter(data: equityData)),
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
              JournalAudioButton(insight: stats.aiInsight),
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
