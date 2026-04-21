import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../bloc/trading_room_bloc.dart';
import '../bloc/trading_room_event.dart';
import '../bloc/trading_room_state.dart';
import '../web/widgets/kinetic_chart.dart';
import '../../../data/repositories/trading_repository.dart';

class TradingRoomMobilePage extends StatefulWidget {
  const TradingRoomMobilePage({super.key});

  @override
  State<TradingRoomMobilePage> createState() => _TradingRoomMobilePageState();
}

class _TradingRoomMobilePageState extends State<TradingRoomMobilePage> {
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TradingRoomBloc(
        tradingRepository: context.read<TradingRepository>(),
      )..add(LoadTradingData()),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text(
            'KINETIC',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          actions: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'EQUITY',
                  style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold),
                ),
                BlocBuilder<TradingRoomBloc, TradingRoomState>(
                  builder: (context, state) {
                    final equity = state is TradingRoomLoaded ? state.account.equity : 0.0;
                    return Text(
                      '\$$equity',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(width: 16),
            const Icon(Icons.sensors, color: AppColors.primary),
            const SizedBox(width: 16),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance & Max Loss Row
              Row(
                children: [
                  Expanded(
                    child: BlocBuilder<TradingRoomBloc, TradingRoomState>(
                      builder: (context, state) {
                        final balance = state is TradingRoomLoaded ? state.account.balance : 0.0;
                        return _buildStatusCard(
                          'BALANCE',
                          '\$$balance',
                          isLive: true,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatusCard(
                      'MAX LOSS LOCK',
                      '-\$1,250.00',
                      textColor: AppColors.bear,
                      showProgress: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Chart Section
              Container(
                height: 350,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: BlocBuilder<TradingRoomBloc, TradingRoomState>(
                  builder: (context, state) {
                    if (state is TradingRoomLoaded) {
                      return KineticChart(
                        signal: state.currentSignal,
                        candles: state.candles,
                      );
                    }
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              
              // Order Execution Section
              Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AUTO-LOT OPTIMIZER',
                            style: TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '1.42 LOTS',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildRiskBtn('1% RISK', false),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildRiskBtn('2% RISK', true),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildTradeBtn('BUY', AppColors.primary),
                        const SizedBox(height: 8),
                        _buildTradeBtn('SELL', AppColors.bear),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Analysis Layers
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ACTIVE ANALYSIS LAYERS',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '5/5 ACTIVE',
                          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 8),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildLayerItem(Icons.warning_amber_rounded, 'Liquidity Trap Detected', AppColors.primary),
                    const SizedBox(height: 8),
                    _buildLayerItem(Icons.show_chart, 'Action Lines (Entry/SL/TP)', Colors.white54),
                  ],
                ),
              ),
              const SizedBox(height: 100), // Space for unified bottom nav
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(String title, String value, {bool isLive = false, Color? textColor, bool showProgress = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 8, fontWeight: FontWeight.bold)),
              if (isLive)
                Row(
                  children: [
                    Container(width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    const Text('LIVE', style: TextStyle(color: AppColors.primary, fontSize: 8, fontWeight: FontWeight.bold)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(color: textColor ?? Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (showProgress) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 0.15,
              backgroundColor: Colors.white10,
              color: AppColors.bear,
              minHeight: 2,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRiskBtn(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.black26,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: isActive ? AppColors.primary.withOpacity(0.3) : Colors.white10),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? AppColors.primary : Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildTradeBtn(String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(label == 'BUY' ? Icons.trending_up : Icons.trending_down, color: Colors.black, size: 16),
          Text(
            label,
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLayerItem(IconData icon, String label, Color iconColor) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
