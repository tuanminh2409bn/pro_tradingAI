import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../bloc/trading_room_bloc.dart';
import '../bloc/trading_room_event.dart';
import '../bloc/trading_room_state.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../data/repositories/trading_repository.dart';
import 'widgets/kinetic_chart.dart';

class TradingRoomWebPage extends StatelessWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const TradingRoomWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TradingRoomBloc(
        tradingRepository: context.read<TradingRepository>(),
      )..add(LoadTradingData(userId: userId)),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 900;
            
            return Column(
              children: [
                _WebTopNavbar(onMenuPressed: onMenuPressed),
                Expanded(
                  child: isMobile 
                    ? _buildMobileLayout(context) 
                    : _buildDesktopLayout(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Expanded(
            flex: 8,
            child: Column(
              children: [
                const _AssetHeader(),
                const SizedBox(height: 16),
                Expanded(
                  child: _buildChartContainer(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            flex: 3,
            child: _OrderPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const _AssetHeader(),
            const SizedBox(height: 16),
            SizedBox(
              height: 400, // Fixed height for chart on mobile
              child: _buildChartContainer(),
            ),
            const SizedBox(height: 16),
            const _OrderPanel(), // Order panel stays below chart on mobile
          ],
        ),
      ),
    );
  }

  Widget _buildChartContainer() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: BlocBuilder<TradingRoomBloc, TradingRoomState>(
        builder: (context, state) {
          if (state is TradingRoomLoaded) {
            return KineticChart(
              candles: state.candles,
              signal: state.currentSignal,
            );
          }
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        },
      ),
    );
  }
}

class _AssetHeader extends StatelessWidget {
  const _AssetHeader();
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingRoomBloc, TradingRoomState>(
      builder: (context, state) {
        String symbol = 'XAUUSD';
        double price = 2038.50;
        if (state is TradingRoomLoaded) {
          symbol = state.currentSymbol;
          if (state.candles.isNotEmpty) price = state.candles.last.close;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            children: [
              Text(symbol, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(width: 12),
              const Icon(Icons.trending_up, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text('\$$price', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary)),
              const Spacer(),
              _buildTimeframeBtn(context, '1M', '1', isActive: state is TradingRoomLoaded && state.currentTimeframe == '1'),
              _buildTimeframeBtn(context, '5M', '5', isActive: state is TradingRoomLoaded && state.currentTimeframe == '5'),
              _buildTimeframeBtn(context, '15M', '15', isActive: state is TradingRoomLoaded && state.currentTimeframe == '15'),
              _buildTimeframeBtn(context, '1H', '60', isActive: state is TradingRoomLoaded && state.currentTimeframe == '60'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimeframeBtn(BuildContext context, String label, String value, {bool isActive = false}) {
    return GestureDetector(
      onTap: () {
        context.read<TradingRoomBloc>().add(ChangeTimeframe(value));
      },
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isActive ? AppColors.primary : Colors.white10),
        ),
        child: Text(label, style: TextStyle(color: isActive ? AppColors.primary : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _OrderPanel extends StatefulWidget {
  const _OrderPanel();

  @override
  State<_OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends State<_OrderPanel> {
  final TextEditingController _lotController = TextEditingController(text: '0.10');

  @override
  void dispose() {
    _lotController.dispose();
    super.dispose();
  }

  void _handleTrade(BuildContext context, String type) {
    final lot = double.tryParse(_lotController.text) ?? 0.10;
    context.read<TradingRoomBloc>().add(ExecuteTrade(type: type, lotSize: lot));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$type Order Executed: $lot Lots', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: type == 'BUY' ? AppColors.primary : AppColors.bear,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingRoomBloc, TradingRoomState>(
      builder: (context, state) {
        double currentPrice = 0.0;
        if (state is TradingRoomLoaded && state.candles.isNotEmpty) {
          currentPrice = state.candles.last.close;
        }

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('EXECUTION ENGINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
              const SizedBox(height: 24),
              _buildInputLabel('LOT SIZE'),
              TextField(
                controller: _lotController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: '0.10',
                  hintStyle: TextStyle(color: Colors.white24),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _buildTradeBtn(context, 'SELL', AppColors.bear, currentPrice),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTradeBtn(context, 'BUY', AppColors.primary, currentPrice),
                  ),
                ],
              ),
              const SizedBox(height: 40),
              const Text('ACTIVE SIGNALS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white54, letterSpacing: 1)),
              const SizedBox(height: 16),
              _buildSignalCard('XAUUSD', 'BUY @ ${currentPrice > 0 ? currentPrice.toStringAsFixed(3) : '...'}', '85% Prob.'),
              _buildSignalCard('BTCUSD', 'SELL @ 64200.000', '72% Prob.'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(label, style: const TextStyle(fontSize: 9, color: Colors.white38, fontWeight: FontWeight.bold));
  }

  Widget _buildTradeBtn(BuildContext context, String label, Color color, double price) {
    return GestureDetector(
      onTap: () => _handleTrade(context, label),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 14)),
            if (price > 0)
              Text(price.toStringAsFixed(3), style: TextStyle(color: color.withOpacity(0.7), fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }


  Widget _buildSignalCard(String symbol, String desc, String prob) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(symbol, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
          Text(prob, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 10)),
        ],
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
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 20),
            ),
          const Text('KINETIC', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.white)),
          const SizedBox(width: 40),
          const Expanded(
            child: Text('Equity: \$42,050.00', style: TextStyle(color: Color(0xFFc3c6d8), fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }
}
