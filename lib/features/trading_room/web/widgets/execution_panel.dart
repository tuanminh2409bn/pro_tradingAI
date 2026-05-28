import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/trading_models.dart';
import '../../bloc/trading_room_bloc.dart';
import '../../bloc/trading_room_event.dart';
import '../../bloc/trading_room_state.dart';

class ExecutionPanel extends StatefulWidget {
  const ExecutionPanel({super.key});

  @override
  State<ExecutionPanel> createState() => _ExecutionPanelState();
}

class _ExecutionPanelState extends State<ExecutionPanel> with SingleTickerProviderStateMixin {
  int _selectedSL = 1; // 0=SL1 Tight, 1=SL2 Normal, 2=SL3 Wide
  final List<bool> _tpActive = [true, true, false, false];
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingRoomBloc, TradingRoomState>(
      builder: (context, state) {
        if (state is! TradingRoomLoaded) return const SizedBox.shrink();
        
        final signal = state.currentSignal;
        final riskConfig = state.riskConfig;
        final isBuy = signal?.type == 'BUY' || signal == null;
        final currentPrice = state.candles.isNotEmpty ? state.candles.last.close : 0.0;
        final entryPrice = signal?.entryPrice ?? currentPrice;
        
        // Calculate SL levels
        final slDistance = signal != null 
            ? (entryPrice - signal.slPrice).abs() 
            : currentPrice * 0.002; // 0.2% default
        final slTight = isBuy ? entryPrice - slDistance * 0.7 : entryPrice + slDistance * 0.7;
        final slNormal = signal?.slPrice ?? (isBuy ? entryPrice - slDistance : entryPrice + slDistance);
        final slWide = isBuy ? entryPrice - slDistance * 1.5 : entryPrice + slDistance * 1.5;
        final slPrices = [slTight, slNormal, slWide];
        final selectedSLPrice = slPrices[_selectedSL];
        
        // Calculate TP levels
        final tpPrices = signal?.tpPrices ?? [];
        final defaultTPs = List.generate(4, (i) {
          final mult = (i + 1) * 1.0;
          return isBuy 
              ? entryPrice + slDistance * mult * 1.5
              : entryPrice - slDistance * mult * 1.5;
        });
        final displayTPs = List.generate(4, (i) => 
          i < tpPrices.length ? tpPrices[i] : defaultTPs[i]);

        // Calculate lot size
        double suggestedLot = 0.10;
        double riskAmount = 0.0;
        double riskPct = 0.0;
        if (riskConfig != null && slDistance > 0) {
          riskPct = riskConfig.riskPerTrade;
          riskAmount = riskConfig.balance * riskPct / 100;
          final pipValue = 10.0; // For XAUUSD, 1 lot = $10/pip
          suggestedLot = riskAmount / (slDistance * pipValue);
          suggestedLot = (suggestedLot * 100).roundToDouble() / 100; // Round to 2 decimals
          if (suggestedLot < 0.01) suggestedLot = 0.01;
          if (suggestedLot > 100) suggestedLot = 100;
        }

        // SL labels using localization
        final slLabels = [
          context.tr('exec_sl_tight'),
          context.tr('exec_sl_normal'),
          context.tr('exec_sl_wide'),
        ];

        return Container(
          width: 380,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ANALYZE AI Button (prominent) ──
                _buildAnalyzeButton(context, state),
                const SizedBox(height: 16),
                // Header
                _sectionTitle(context, context.tr('exec_engine')),
                const SizedBox(height: 12),
                
                // Lot Size + Risk
                _infoRow(context, context.tr('exec_suggested_lot'), suggestedLot.toStringAsFixed(2), AppColors.accent),
                const SizedBox(height: 6),
                _infoRow(context, context.tr('exec_risk'), '\$${riskAmount.toStringAsFixed(2)} (${riskPct.toStringAsFixed(1)}%)', 
                    riskPct > 3 ? AppColors.bear : AppColors.primary),
                const SizedBox(height: 4),
                _infoRow(context, context.tr('exec_entry'), entryPrice.toStringAsFixed(2), Colors.white),
                
                const SizedBox(height: 16),
                
                // Stop Loss Section
                _sectionTitle(context, context.tr('exec_stop_loss')),
                const SizedBox(height: 8),
                Row(
                  children: List.generate(3, (i) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSL = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedSL == i 
                                ? AppColors.bear.withValues(alpha: 0.15) 
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _selectedSL == i 
                                  ? AppColors.bear.withValues(alpha: 0.5) 
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(slLabels[i], style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.bold,
                                color: _selectedSL == i ? AppColors.bear : Colors.white38,
                              )),
                              const SizedBox(height: 2),
                              Text(slPrices[i].toStringAsFixed(2), style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold,
                                color: _selectedSL == i ? AppColors.bear : Colors.white54,
                              )),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                
                const SizedBox(height: 16),
                
                // Take Profit Section
                _sectionTitle(context, context.tr('exec_take_profit')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: List.generate(4, (i) {
                    return GestureDetector(
                      onTap: () => setState(() => _tpActive[i] = !_tpActive[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 80,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _tpActive[i] 
                              ? AppColors.primary.withValues(alpha: 0.1) 
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _tpActive[i] 
                                ? AppColors.primary.withValues(alpha: 0.5) 
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text('TP${i + 1}', style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold,
                              color: _tpActive[i] ? AppColors.primary : Colors.white38,
                            )),
                            const SizedBox(height: 2),
                            Text(displayTPs[i].toStringAsFixed(2), style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.bold,
                              color: _tpActive[i] ? AppColors.primary : Colors.white54,
                            )),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
                
                const SizedBox(height: 20),
                
                // Execute Button
                AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    final glowOpacity = state.isCutoffActive ? 0.0 : _glowController.value * 0.3;
                    return GestureDetector(
                      onTap: state.isCutoffActive || state.isTradeExecuting
                          ? null
                          : () => _executeTrade(context, state, isBuy, suggestedLot, 
                              entryPrice, selectedSLPrice, displayTPs),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: state.isCutoffActive 
                                ? [Colors.grey.shade800, Colors.grey.shade700]
                                : isBuy 
                                    ? [AppColors.primary.withValues(alpha: 0.8), AppColors.primary]
                                    : [AppColors.bear.withValues(alpha: 0.8), AppColors.bear],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: state.isCutoffActive ? [] : [
                            BoxShadow(
                              color: (isBuy ? AppColors.primary : AppColors.bear)
                                  .withValues(alpha: glowOpacity),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            if (state.isTradeExecuting)
                              const SizedBox(
                                height: 20, width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white,
                                ),
                              )
                            else ...[
                              Text(
                                state.isCutoffActive 
                                    ? context.tr('exec_locked')
                                    : isBuy 
                                        ? context.tr('exec_execute_long') 
                                        : context.tr('exec_execute_short'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: state.isCutoffActive ? Colors.white38 : Colors.black,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                state.isCutoffActive 
                                    ? context.tr('exec_max_loss')
                                    : signal != null 
                                        ? 'SIGNAL: ${signal.probability}% CONFIDENCE'
                                        : context.tr('exec_manual'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: state.isCutoffActive 
                                      ? Colors.white24 
                                      : Colors.black.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                
                const SizedBox(height: 16),
                
                // Trading Mode Dropdown
                _sectionTitle(context, context.tr('exec_trading_mode')),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<TradingMode>(
                      value: state.tradingMode,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white38),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      onChanged: (mode) {
                        if (mode != null) {
                          context.read<TradingRoomBloc>().add(ChangeTradingMode(mode));
                        }
                      },
                      items: TradingMode.values.map((mode) => DropdownMenuItem(
                        value: mode,
                        child: Text(mode.displayName),
                      )).toList(),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Time Matrix
                Row(
                  children: List.generate(state.tradingMode.timeframeLabels.length, (i) {
                    final tf = state.tradingMode.timeframes[i];
                    final label = state.tradingMode.timeframeLabels[i];
                    final isActive = state.currentTimeframe == tf;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => context.read<TradingRoomBloc>().add(ChangeTimeframe(tf)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive 
                                ? AppColors.secondary.withValues(alpha: 0.15) 
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isActive 
                                  ? AppColors.secondary 
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Center(
                            child: Text(label, style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold,
                              color: isActive ? AppColors.secondary : Colors.white54,
                            )),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                
                const SizedBox(height: 20),
                
                // Active Signals Section
                if (signal != null) ...[
                  _sectionTitle(context, context.tr('exec_active_signal')),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (isBuy ? AppColors.primary : AppColors.bear).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(signal.symbol, style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13,
                            )),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isBuy ? AppColors.primary : AppColors.bear).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(signal.type, style: TextStyle(
                                color: isBuy ? AppColors.primary : AppColors.bear,
                                fontSize: 10, fontWeight: FontWeight.w900,
                              )),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _infoRow(context, context.tr('exec_entry'), signal.entryPrice.toStringAsFixed(2), Colors.white70),
                        _infoRow(context, context.tr('exec_probability'), '${signal.probability}%', AppColors.accent),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _executeTrade(BuildContext context, TradingRoomLoaded state, bool isBuy,
      double lot, double entry, double sl, List<double> tps) {
    final activeTPs = <double>[];
    for (int i = 0; i < _tpActive.length; i++) {
      if (_tpActive[i]) activeTPs.add(tps[i]);
    }
    
    context.read<TradingRoomBloc>().add(ExecuteTrade(
      type: isBuy ? 'BUY' : 'SELL',
      lotSize: lot,
      entryPrice: entry,
      slPrice: sl,
      tpPrices: activeTPs,
    ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${isBuy ? "BUY" : "SELL"} order submitted: $lot lots @ ${entry.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isBuy ? AppColors.primary : AppColors.bear,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildAnalyzeButton(BuildContext context, TradingRoomLoaded state) {
    return GestureDetector(
      onTap: state.isAnalyzing ? null : () {
        context.read<TradingRoomBloc>().add(const RequestAnalysis());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('analyzing_request'),
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
            ),
            backgroundColor: AppColors.primary,
            duration: const Duration(seconds: 3),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: state.isAnalyzing
                ? [Colors.grey.shade800, Colors.grey.shade700]
                : [AppColors.secondary, const Color(0xFF9370DB)], // Solid Pale Orchid to Medium Purple
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: state.isAnalyzing ? [] : [
            BoxShadow(
              color: AppColors.secondary.withValues(alpha: 0.4),
              blurRadius: 16,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (state.isAnalyzing)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
              )
            else
              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              state.isAnalyzing ? context.tr('ai_analyzing') : context.tr('analyze_data'),
              style: TextStyle(
                color: state.isAnalyzing ? Colors.white30 : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(title, style: TextStyle(
      fontSize: 13, fontWeight: FontWeight.w900,
      color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1.2,
    ));
  }

  Widget _infoRow(BuildContext context, String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(
            color: Colors.white54, fontSize: 14,
          )),
          Text(value, style: TextStyle(
            color: valueColor, fontSize: 16, fontWeight: FontWeight.bold,
          )),
        ],
      ),
    );
  }
}
