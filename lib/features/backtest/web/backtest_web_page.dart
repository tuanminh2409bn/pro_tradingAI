import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../data/repositories/backtest_repository.dart';
import '../../../data/repositories/trading_repository.dart';
import '../bloc/backtest_bloc.dart';
import '../bloc/backtest_event.dart';
import '../bloc/backtest_state.dart';

class BacktestWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const BacktestWebPage({super.key, required this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) {
        final tradingRepository = context.read<TradingRepository>();
        tradingRepository.changeSymbol('XAUUSD');
        tradingRepository.changeTimeframe('5');
        return BacktestBloc(
          backtestRepository: context.read<BacktestRepository>(),
          historyStream: tradingRepository.getCandleStream,
        )..add(StartBacktestSession('XAUUSD', 10000.0, userId: userId));
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _WebTopNavbar(onMenuPressed: onMenuPressed),
            Expanded(
              child: BlocBuilder<BacktestBloc, BacktestState>(
                builder: (context, state) {
                  if (state is BacktestLoading || state is BacktestInitial) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  if (state is BacktestError) {
                    return Center(
                      child: Text(
                        context.tr(state.message),
                        style: const TextStyle(color: AppColors.bear),
                      ),
                    );
                  }

                  if (state is BacktestLoaded) {
                    final session = state.session;
                    return Stack(
                      children: [
                        Column(
                          children: [
                            _buildSimulationHeader(context, state),
                            Expanded(
                              child: Row(
                                children: [
                                  _buildTradingPanel(state),
                                  Expanded(
                                    child: _buildChartCanvas(context, state),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (session.isLocked) _buildDisciplineLockOverlay(),
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimulationHeader(BuildContext context, BacktestLoaded state) {
    final session = state.session;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            _buildHeaderMetric(
              'TRADING PAIR',
              session.symbol,
              subtitle: 'Gold Spot',
            ),
            const SizedBox(width: 40),
            _buildHeaderMetric(
              'INITIAL BAL',
              '\$${session.initialBalance}',
              icon: Icons.account_balance_wallet,
            ),
          ],
        ),
        _buildPlaybackControls(context, state),
        Row(
          children: [
            _buildHeaderMetric(
              'SIM EQUITY',
              '\$${session.equity.toStringAsFixed(2)}',
              isNumeric: true,
              textAlign: CrossAxisAlignment.end,
            ),
            const SizedBox(width: 24),
            _buildHeaderMetric(
              'P&L (OPEN)',
              '${session.openPL >= 0 ? '+' : ''}\$${session.openPL.toStringAsFixed(2)}',
              isNumeric: true,
              isPositive: session.openPL >= 0,
              textAlign: CrossAxisAlignment.end,
            ),
          ],
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 1000;
        return Container(
          padding: EdgeInsets.all(isNarrow ? 16 : 24),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: isNarrow
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: content,
                )
              : content,
        );
      },
    );
  }

  Widget _buildHeaderMetric(
    String label,
    String value, {
    String? subtitle,
    IconData? icon,
    bool isNumeric = false,
    bool isPositive = false,
    CrossAxisAlignment textAlign = CrossAxisAlignment.start,
  }) {
    return Column(
      crossAxisAlignment: textAlign,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w900,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: Colors.white54),
              const SizedBox(width: 8),
            ],
            Text(
              value,
              style: TextStyle(
                fontSize: isNumeric ? 18 : 16,
                fontWeight: isNumeric ? FontWeight.w900 : FontWeight.bold,
                color: isPositive ? AppColors.primary : Colors.white,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: AppColors.primary),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(BuildContext context, BacktestLoaded state) {
    final session = state.session;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0b0e11),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: context.tr('backtest_first_candle'),
            onPressed: state.cursor == 0
                ? null
                : () => context.read<BacktestBloc>().add(
                    const SeekReplayCursor(0),
                  ),
            icon: const Icon(Icons.first_page, size: 18),
          ),
          IconButton(
            tooltip: context.tr('backtest_previous_candle'),
            onPressed: state.cursor == 0
                ? null
                : () => context.read<BacktestBloc>().add(
                    const StepReplayCursor(-1),
                  ),
            icon: const Icon(Icons.fast_rewind, size: 18),
          ),
          Semantics(
            label: context.tr(
              session.isPlaying ? 'backtest_pause' : 'backtest_play',
            ),
            button: true,
            child: Tooltip(
              message: context.tr(
                session.isPlaying ? 'backtest_pause' : 'backtest_play',
              ),
              excludeFromSemantics: true,
              child: InkWell(
                onTap: () => context.read<BacktestBloc>().add(TogglePlayback()),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 15,
                      ),
                    ],
                  ),
                  child: Icon(
                    session.isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 24,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: context.tr('backtest_next_candle'),
            onPressed: state.cursor >= state.totalBars - 1
                ? null
                : () => context.read<BacktestBloc>().add(
                    const StepReplayCursor(1),
                  ),
            icon: const Icon(Icons.fast_forward, size: 18),
          ),
          const SizedBox(width: 8),
          const VerticalDivider(color: Colors.white10, indent: 8, endIndent: 8),
          const SizedBox(width: 8),
          const Text(
            'SPEED',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
            ),
          ),
          const SizedBox(width: 8),
          _buildSpeedBtn(context, '1X', isActive: session.speed == 1, speed: 1),
          _buildSpeedBtn(context, '5X', isActive: session.speed == 5, speed: 5),
          _buildSpeedBtn(
            context,
            '10X',
            isActive: session.speed == 10,
            speed: 10,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildSpeedBtn(
    BuildContext context,
    String label, {
    bool isActive = false,
    required int speed,
  }) {
    return InkWell(
      onTap: () => context.read<BacktestBloc>().add(UpdateSpeed(speed)),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.2)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isActive ? AppColors.primary : Colors.white38,
          ),
        ),
      ),
    );
  }

  Widget _buildTradingPanel(BacktestLoaded state) {
    final activeTrades = state.activeTrades;
    final currentPrice = state.visibleBars.last.close;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'REPLAY STATUS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 24),
          _buildInputLabel('CURRENT CLOSED-CANDLE PRICE'),
          Text(
            currentPrice.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.cursor + 1} / ${state.totalBars} · ${state.historySource}',
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 24),
          const Text(
            'Order simulation is locked until the persisted risk and review workflow is approved.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 40),
          const Text(
            'ACTIVE SESSIONS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Colors.white38,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: activeTrades.length,
              itemBuilder: (context, index) {
                final trade = activeTrades[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _buildActiveTradeItem(
                    '${trade.type} ${trade.lotSize} Lots',
                    '${trade.currentProfit >= 0 ? '+' : ''}\$${trade.currentProfit.toStringAsFixed(2)}',
                    trade.currentProfit >= 0,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          color: Colors.white54,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActiveTradeItem(String title, String profit, bool isPositive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          Text(
            profit,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isPositive ? AppColors.primary : AppColors.bear,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCanvas(BuildContext context, BacktestLoaded state) {
    final session = state.session;
    return Container(
      color: const Color(0xFF0b0e11),
      child: Stack(
        children: [
          Center(
            child: Text(
              '${state.visibleBars.length} CLOSED CANDLES REVEALED',
              style: const TextStyle(
                color: Colors.white24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 40,
            right: 40,
            child: Column(
              children: [
                Slider(
                  value: state.cursor.toDouble(),
                  min: 0,
                  max: (state.totalBars - 1).toDouble(),
                  divisions: state.totalBars > 1 ? state.totalBars - 1 : null,
                  onChanged: (value) => context.read<BacktestBloc>().add(
                    SeekReplayCursor(value.round()),
                  ),
                  activeColor: AppColors.primary,
                  inactiveColor: Colors.white10,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      session.startTime.toString().split(' ')[0],
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      session.endTime.toString().split(' ')[0],
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisciplineLockOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.bear),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_reset, color: AppColors.bear, size: 64),
              const SizedBox(height: 24),
              const Text(
                'DISCIPLINE LOCK',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Simulation Equity has reached zero. Take 15 mins to reflect.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text(
                    'VIEW ANALYTICS',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebTopNavbar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  const _WebTopNavbar({this.onMenuPressed});
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
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
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
          const Spacer(),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 20),
          ),
        ],
      ),
    );
  }
}
