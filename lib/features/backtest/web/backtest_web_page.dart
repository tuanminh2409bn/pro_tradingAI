import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/backtest_models.dart';
import '../../../data/repositories/backtest_repository.dart';
import '../bloc/backtest_bloc.dart';
import '../bloc/backtest_event.dart';
import '../bloc/backtest_state.dart';

class BacktestWebPage extends StatelessWidget {
  const BacktestWebPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => BacktestBloc(
        backtestRepository: context.read<BacktestRepository>(),
      )..add(const StartBacktestSession('XAUUSD', 10000.0)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: BlocBuilder<BacktestBloc, BacktestState>(
          builder: (context, state) {
            if (state is BacktestLoading || state is BacktestInitial) {
              return const Center(child: CircularProgressIndicator(color: AppColors.primary));
            }

            if (state is BacktestError) {
              return Center(child: Text(state.message, style: const TextStyle(color: AppColors.bear)));
            }

            if (state is BacktestLoaded) {
              final session = state.session;
              return Stack(
                children: [
                  Column(
                    children: [
                      const _WebTopNavbar(),
                      Expanded(
                        child: Column(
                          children: [
                            _buildSimulationHeader(context, session),
                            Expanded(
                              child: Row(
                                children: [
                                  _buildTradingPanel(state.activeTrades),
                                  Expanded(child: _buildChartCanvas(session)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const _WebTickerFooter(),
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
    );
  }

  Widget _buildSimulationHeader(BuildContext context, BacktestSession session) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _buildHeaderMetric('TRADING PAIR', session.symbol, subtitle: 'Gold Spot'),
              const SizedBox(width: 40),
              _buildHeaderMetric('INITIAL BAL', '\$${session.initialBalance}', icon: Icons.account_balance_wallet),
            ],
          ),
          _buildPlaybackControls(context, session),
          Row(
            children: [
              _buildHeaderMetric('SIM EQUITY', '\$${session.equity.toStringAsFixed(2)}', isNumeric: true, textAlign: CrossAxisAlignment.end),
              const SizedBox(width: 24),
              _buildHeaderMetric('P&L (OPEN)', '${session.openPL >= 0 ? '+' : ''}\$${session.openPL.toStringAsFixed(2)}', isNumeric: true, isPositive: session.openPL >= 0, textAlign: CrossAxisAlignment.end),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetric(String label, String value, {String? subtitle, IconData? icon, bool isNumeric = false, bool isPositive = false, CrossAxisAlignment textAlign = CrossAxisAlignment.start}) {
    return Column(
      crossAxisAlignment: textAlign,
      children: [
        Text(label, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 12, color: Colors.white54), const SizedBox(width: 8)],
            Text(
              value,
              style: TextStyle(
                fontSize: isNumeric ? 18 : 16,
                fontWeight: isNumeric ? FontWeight.w900 : FontWeight.bold,
                color: isPositive ? AppColors.primary : Colors.white,
              ),
            ),
            if (subtitle != null) ...[const SizedBox(width: 8), Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.primary))],
          ],
        ),
      ],
    );
  }

  Widget _buildPlaybackControls(BuildContext context, BacktestSession session) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFF0b0e11), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Row(
        children: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.first_page, size: 18, color: Colors.white54)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.fast_rewind, size: 18, color: Colors.white54)),
          InkWell(
            onTap: () => context.read<BacktestBloc>().add(TogglePlayback()),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 15)]),
              child: Icon(session.isPlaying ? Icons.pause : Icons.play_arrow, size: 24, color: Colors.black),
            ),
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.fast_forward, size: 18, color: Colors.white54)),
          const SizedBox(width: 8),
          const VerticalDivider(color: Colors.white10, indent: 8, endIndent: 8),
          const SizedBox(width: 8),
          const Text('SPEED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white38)),
          const SizedBox(width: 8),
          _buildSpeedBtn(context, '1X', isActive: session.speed == 1, speed: 1),
          _buildSpeedBtn(context, '5X', isActive: session.speed == 5, speed: 5),
          _buildSpeedBtn(context, '10X', isActive: session.speed == 10, speed: 10),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildSpeedBtn(BuildContext context, String label, {bool isActive = false, required int speed}) {
    return InkWell(
      onTap: () => context.read<BacktestBloc>().add(UpdateSpeed(speed)),
      child: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? AppColors.primary.withOpacity(0.2) : Colors.transparent),
        ),
        child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isActive ? AppColors.primary : Colors.white38)),
      ),
    );
  }

  Widget _buildTradingPanel(List<BacktestTrade> activeTrades) {
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
          const Text('EXECUTE TRADE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 1)),
          const SizedBox(height: 24),
          _buildInputLabel('POSITION SIZE (LOTS)'),
          _buildSimulationInput('1.25'),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildInputLabel('STOP LOSS'), _buildSimulationInput('Price...')])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_buildInputLabel('TAKE PROFIT'), _buildSimulationInput('Price...')])),
            ],
          ),
          const SizedBox(height: 32),
          _buildSimulationTradeBtn('BUY MARKET', '2042.12', AppColors.primary),
          const SizedBox(height: 16),
          _buildSimulationTradeBtn('SELL MARKET', '2042.10', AppColors.bear),
          const SizedBox(height: 40),
          const Text('ACTIVE SESSIONS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: activeTrades.length,
              itemBuilder: (context, index) {
                final trade = activeTrades[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: _buildActiveTradeItem('${trade.type} ${trade.lotSize} Lots', '${trade.currentProfit >= 0 ? '+' : ''}\$${trade.currentProfit.toStringAsFixed(2)}', trade.currentProfit >= 0),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54, fontWeight: FontWeight.bold)));
  }

  Widget _buildSimulationInput(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF0b0e11), borderRadius: BorderRadius.circular(4)),
      child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSimulationTradeBtn(String label, String price, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black)),
          Text(price, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black)),
        ],
      ),
    );
  }

  Widget _buildActiveTradeItem(String title, String profit, bool isPositive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white10)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)), const SizedBox(width: 12), Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))]),
          Text(profit, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isPositive ? AppColors.primary : AppColors.bear)),
        ],
      ),
    );
  }

  Widget _buildChartCanvas(BacktestSession session) {
    return Container(
      color: const Color(0xFF0b0e11),
      child: Stack(
        children: [
          const Center(child: Text('HISTORICAL DATA FEED', style: TextStyle(color: Colors.white10, fontWeight: FontWeight.bold))),
          Positioned(
            bottom: 40, left: 40, right: 40,
            child: Column(
              children: [
                Slider(value: 0.6, onChanged: (v) {}, activeColor: AppColors.primary, inactiveColor: Colors.white10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(session.startTime.toString().split(' ')[0], style: const TextStyle(fontSize: 9, color: Colors.white24, fontWeight: FontWeight.bold)),
                    Text(session.endTime.toString().split(' ')[0], style: const TextStyle(fontSize: 9, color: Colors.white24, fontWeight: FontWeight.bold)),
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
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.bear)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_reset, color: AppColors.bear, size: 64),
              const SizedBox(height: 24),
              const Text('DISCIPLINE LOCK', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 12),
              const Text('Simulation Equity has reached zero. Take 15 mins to reflect.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white10, padding: const EdgeInsets.all(16)),
                  child: const Text('VIEW ANALYTICS', style: TextStyle(fontWeight: FontWeight.bold)),
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
  const _WebTopNavbar();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(color: Color(0xFF111417), border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Row(
        children: [
          const Text('KINETIC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          const SizedBox(width: 40),
          const Text('Equity: \$42,050.00', style: TextStyle(color: Color(0xFFc3c6d8), fontSize: 13)),
          const Spacer(),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8)),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8)),
          const SizedBox(width: 16),
          IconButton(
            onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 20),
          ),
        ],
      ),
    );
  }
}

class _WebTickerFooter extends StatelessWidget {
  const _WebTickerFooter();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: const Color(0xFF0b0e11),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _TickerItem('XAUUSD: 2042.12', AppColors.primary),
          SizedBox(width: 32),
          _TickerItem('BTCUSD: 64210.50', AppColors.bear),
          SizedBox(width: 32),
          _TickerItem('EURUSD: 1.0821', Colors.white54),
        ],
      ),
    );
  }
}

class _TickerItem extends StatelessWidget {
  final String text;
  final Color color;
  const _TickerItem(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Row(children: [Icon(Icons.trending_up, color: color, size: 14), const SizedBox(width: 4), Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))]);
  }
}
