import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/widgets/sync_gate_modal.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../bloc/journal_bloc.dart';
import '../bloc/journal_event.dart';
import '../bloc/journal_state.dart';
import 'widgets/journal_equity_painter.dart';
import 'widgets/journal_heatmap.dart';
import 'widgets/journal_performance.dart';
import 'widgets/journal_trade_log.dart';

class JournalWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const JournalWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey(userId),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr(state.message),
                      style: const TextStyle(color: AppColors.bear),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                      ),
                      onPressed: () => context.read<JournalBloc>().add(
                        LoadJournalData(userId: userId),
                      ),
                      child: Text(context.tr('journal_retry')),
                    ),
                  ],
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
                                JournalPerformanceMetrics(
                                  stats: state.stats,
                                  compact: isMobile,
                                ),
                                const SizedBox(height: 24),
                                if (isMobile) ...[
                                  _buildEquityCurveCard(
                                    context,
                                    state.stats.equityData,
                                  ),
                                  const SizedBox(height: 24),
                                  JournalPerformanceSummary(stats: state.stats),
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
                                        child: JournalPerformanceSummary(
                                          stats: state.stats,
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
              'P&L: ${totalProfit >= 0 ? '+' : ''}${totalProfit.toStringAsFixed(2)}',
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
