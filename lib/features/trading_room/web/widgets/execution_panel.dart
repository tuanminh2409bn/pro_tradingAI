import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ExecutionPanelState extends State<ExecutionPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  final TextEditingController _balanceController = TextEditingController();
  final TextEditingController _riskController = TextEditingController();
  final TextEditingController _maxLossController = TextEditingController();
  final List<TextEditingController> _tpAllocationControllers = [
    TextEditingController(text: '30'),
    TextEditingController(text: '30'),
    TextEditingController(text: '40'),
  ];
  bool _isInitialized = false;
  int _lastPanelResetNonce = -1;
  int _lastActionResultNonce = 0;

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
    _balanceController.dispose();
    _riskController.dispose();
    _maxLossController.dispose();
    for (final controller in _tpAllocationControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _resetPanelForSymbol() {
    _tpAllocationControllers[0].text = '30';
    _tpAllocationControllers[1].text = '30';
    _tpAllocationControllers[2].text = '40';
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TradingRoomBloc, TradingRoomState>(
      listenWhen: (prev, curr) {
        if (prev is! TradingRoomLoaded || curr is! TradingRoomLoaded) {
          return false;
        }
        return prev.panelResetNonce != curr.panelResetNonce ||
            prev.currentSymbol != curr.currentSymbol ||
            prev.actionResultNonce != curr.actionResultNonce;
      },
      listener: (context, state) {
        if (state is TradingRoomLoaded) {
          if (state.panelResetNonce != _lastPanelResetNonce) {
            setState(_resetPanelForSymbol);
          }
          if (state.actionResultNonce != _lastActionResultNonce) {
            _lastActionResultNonce = state.actionResultNonce;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(context.tr(state.actionMessageKey)),
                backgroundColor: state.actionSucceeded
                    ? AppColors.primary
                    : AppColors.bear,
              ),
            );
          }
        }
      },
      builder: (context, state) {
        if (state is! TradingRoomLoaded) return const SizedBox.shrink();

        final signal = state.currentSignal;
        final riskConfig = state.riskConfig;
        final meta = SymbolMeta.of(state.currentSymbol);

        if (state.panelResetNonce != _lastPanelResetNonce) {
          _lastPanelResetNonce = state.panelResetNonce;
        }

        if (riskConfig != null && !_isInitialized) {
          _balanceController.text = riskConfig.balance.toStringAsFixed(0);
          _riskController.text = riskConfig.riskPerTrade.toStringAsFixed(1);
          _maxLossController.text = riskConfig.maxDailyLoss.toStringAsFixed(1);
          _isInitialized = true;
        }
        final matchedSignal =
            signal != null &&
                signal.contractError == null &&
                (isSignalForCurrentChart(state, signal) ||
                    (signal.chartId == null &&
                        !signal.canExecute &&
                        signal.symbol.toUpperCase() ==
                            state.currentSymbol.toUpperCase()))
            ? signal
            : null;
        final hardSetup = matchedSignal != null && matchedSignal.canExecute;

        final isBuy = matchedSignal?.type == 'BUY' || matchedSignal == null;
        final currentPrice = state.candles.isNotEmpty
            ? state.candles.last.close
            : (state.symbolPrices[state.currentSymbol.toUpperCase()] ?? 0.0);
        final hasMarketPrice = currentPrice.isFinite && currentPrice > 0;
        final entryPrice = hardSetup ? matchedSignal.entryPrice : currentPrice;

        // ── Bid/Ask from SymbolMeta (not leftover foreign symbol) ──
        final spread = meta.typicalSpread;
        final bid = currentPrice - spread / 2;
        final ask = currentPrice + spread / 2;
        final digits = meta.digits;

        // Single SL only (V2.1 P0#10)
        final slDistance = hardSetup
            ? (entryPrice - matchedSignal.slPrice).abs()
            : currentPrice * 0.002;
        final selectedSLPrice = hardSetup
            ? matchedSignal.slPrice
            : (isBuy ? entryPrice - slDistance : entryPrice + slDistance);

        // Calculate TP levels (max 3 per PDF)
        final tpPrices = hardSetup ? matchedSignal.tpPrices : <double>[];
        final defaultTPs = List.generate(3, (i) {
          final mult = (i + 1) * 1.0;
          return isBuy
              ? entryPrice + slDistance * mult * 1.5
              : entryPrice - slDistance * mult * 1.5;
        });
        final displayTPs = List.generate(
          3,
          (i) => i < tpPrices.length ? tpPrices[i] : defaultTPs[i],
        );

        // Calculate lot size using symbol pip value
        double suggestedLot = 0.10;
        double riskAmount = 0.0;
        double riskPct = 0.0;
        if (riskConfig != null && slDistance > 0 && meta.pipSize > 0) {
          riskPct = riskConfig.riskPerTrade;
          riskAmount = riskConfig.balance * riskPct / 100;
          final slPips = slDistance / meta.pipSize;
          suggestedLot = slPips > 0
              ? riskAmount / (slPips * meta.pipValuePerLot)
              : meta.minLot;
          suggestedLot = (suggestedLot / meta.lotStep).round() * meta.lotStep;
          if (suggestedLot < meta.minLot) suggestedLot = meta.minLot;
          if (suggestedLot > meta.maxLot) suggestedLot = meta.maxLot;
        }

        final allocationPercentages = _tpAllocationControllers
            .map((controller) => double.tryParse(controller.text.trim()))
            .toList(growable: false);
        final allocationTotal = allocationPercentages.fold<double>(
          0,
          (total, percentage) => total + (percentage ?? 0),
        );
        TakeProfitAllocationPlan? takeProfitPlan;
        String? allocationError;
        if (hardSetup) {
          if (allocationPercentages.any((percentage) => percentage == null) ||
              (allocationTotal - 100).abs() > 1e-6) {
            allocationError = context.tr('exec_tp_allocation_invalid');
          } else {
            try {
              takeProfitPlan = TakeProfitAllocationPlan.create(
                totalVolume: suggestedLot,
                targetPrices: displayTPs,
                percentages: allocationPercentages.cast<double>(),
                lotStep: meta.lotStep,
                minLot: meta.minLot,
              );
            } on ArgumentError {
              allocationError = context.tr('exec_tp_volume_too_small');
            }
          }
        }
        final tradeLocked = !hardSetup || takeProfitPlan == null;

        return Container(
          width: 380,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              left: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── ANALYZE AI Button (prominent) ──
                _buildAnalyzeButton(context, state),
                const SizedBox(height: 12),
                if (matchedSignal != null) _buildStageBanner(matchedSignal),

                // ── Bid / Ask Price Display ──
                _buildBidAskDisplay(
                  bid,
                  ask,
                  spread,
                  digits,
                  state.currentSymbol,
                  hasMarketPrice,
                ),
                const SizedBox(height: 16),

                // Header
                _sectionTitle(context, context.tr('exec_engine')),
                const SizedBox(height: 10),
                _buildCapitalRiskInputs(context),
                const SizedBox(height: 16),

                // Lot Size + Risk
                if (hardSetup)
                  _infoRow(
                    context,
                    context.tr('exec_suggested_lot'),
                    suggestedLot.toStringAsFixed(2),
                    AppColors.accent,
                  ),
                const SizedBox(height: 6),
                if (hardSetup)
                  _infoRow(
                    context,
                    context.tr('exec_risk'),
                    '\$${riskAmount.toStringAsFixed(2)} (${riskPct.toStringAsFixed(1)}%)',
                    riskPct > 3 ? AppColors.bear : AppColors.primary,
                  ),
                const SizedBox(height: 4),
                if (hardSetup)
                  _infoRow(
                    context,
                    context.tr('exec_entry'),
                    entryPrice.toStringAsFixed(digits),
                    Colors.white,
                  ),

                const SizedBox(height: 16),

                // Stop Loss — SINGLE level only
                if (hardSetup)
                  _sectionTitle(context, context.tr('exec_stop_loss')),
                const SizedBox(height: 8),
                if (hardSetup)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.bear.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.bear.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'SL',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.bear,
                          ),
                        ),
                        Text(
                          selectedSLPrice.toStringAsFixed(digits),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.bear,
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),

                // Take Profit Section (TP1–TP3)
                if (hardSetup)
                  _sectionTitle(context, context.tr('exec_take_profit')),
                const SizedBox(height: 8),
                if (hardSetup)
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: List.generate(3, (i) {
                      final selected = state.selectedTakeProfitIndex == i;
                      final opacity =
                          state.selectedTakeProfitIndex == 2 && i < 2
                          ? 0.4
                          : 1.0;
                      return GestureDetector(
                        onTap: () => context.read<TradingRoomBloc>().add(
                          SelectTakeProfit(i),
                        ),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: opacity,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 100,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.primary.withValues(alpha: 0.1)
                                  : Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary.withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'TP${i + 1}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayTPs[i].toStringAsFixed(digits),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                if (hardSetup) const SizedBox(height: 10),
                if (hardSetup)
                  Row(
                    children: List.generate(3, (i) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: i < 2 ? 6 : 0),
                          child: TextField(
                            key: ValueKey('tp-allocation-${i + 1}'),
                            controller: _tpAllocationControllers[i],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d{0,3}(\.\d{0,2})?$'),
                              ),
                            ],
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: 'TP${i + 1} %',
                              labelStyle: const TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                              suffixText: '%',
                              suffixStyle: const TextStyle(
                                color: Colors.white38,
                                fontSize: 10,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.03),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.08),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                if (hardSetup) const SizedBox(height: 6),
                if (hardSetup)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.tr('exec_tp_allocation'),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        '${context.tr('exec_tp_total')}: ${allocationTotal.toStringAsFixed(allocationTotal == allocationTotal.roundToDouble() ? 0 : 1)}%',
                        style: TextStyle(
                          color: allocationError == null
                              ? AppColors.primary
                              : AppColors.bear,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (hardSetup && allocationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      allocationError,
                      style: const TextStyle(
                        color: AppColors.bear,
                        fontSize: 10,
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // ── Dual BUY / SELL Buttons ──
                if (!hardSetup)
                  const SizedBox.shrink()
                else if (state.isCutoffActive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          context.tr('exec_locked'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white38,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('exec_max_loss'),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white24,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  AnimatedBuilder(
                    animation: _glowController,
                    builder: (context, child) {
                      final glow = _glowController.value * 0.3;
                      return Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('execute-sell'),
                              onTap:
                                  (state.isTradeExecuting ||
                                      tradeLocked ||
                                      isBuy)
                                  ? null
                                  : () => _executeTrade(
                                      context,
                                      state,
                                      false,
                                      suggestedLot,
                                      entryPrice,
                                      selectedSLPrice,
                                      takeProfitPlan!,
                                    ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.bear.withValues(alpha: 0.85),
                                      AppColors.bear,
                                    ],
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(8),
                                    bottomLeft: Radius.circular(8),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.bear.withValues(
                                        alpha: glow,
                                      ),
                                      blurRadius: 16,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          Icons.arrow_downward,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        const Text(
                                          'SELL',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      bid.toStringAsFixed(digits),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white70,
                                      ),
                                    ),
                                    if (!isBuy)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          matchedSignal.probabilityAvailable
                                              ? 'AI ▼ ${matchedSignal.probability}%'
                                              : 'AI ▼',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.accent,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 36,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D1117),
                              border: Border.symmetric(
                                horizontal: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.05),
                                ),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  _formatSpreadPips(
                                    spread,
                                    state.currentSymbol,
                                  ),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'pip',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.white30,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              key: const ValueKey('execute-buy'),
                              onTap:
                                  (state.isTradeExecuting ||
                                      tradeLocked ||
                                      !isBuy)
                                  ? null
                                  : () => _executeTrade(
                                      context,
                                      state,
                                      true,
                                      suggestedLot,
                                      entryPrice,
                                      selectedSLPrice,
                                      takeProfitPlan!,
                                    ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primary.withValues(alpha: 0.85),
                                    ],
                                  ),
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(8),
                                    bottomRight: Radius.circular(8),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primary.withValues(
                                        alpha: glow,
                                      ),
                                      blurRadius: 16,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const Text(
                                          'BUY',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.black,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.arrow_upward,
                                          color: Colors.black,
                                          size: 14,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      ask.toStringAsFixed(digits),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    if (isBuy)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          matchedSignal.probabilityAvailable
                                              ? 'AI ▲ ${matchedSignal.probability}%'
                                              : 'AI ▲',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.black87,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),

                const SizedBox(height: 20),
                _buildModeAndTfSection(context, state),
                const SizedBox(height: 16),
                if (matchedSignal != null)
                  _buildSignalCard(context, matchedSignal),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStageBanner(TradingSignal signal) {
    final Color color;
    final String title;
    final String body;
    if (signal.veto) {
      color = AppColors.bear;
      title = 'VETO — ENTRY FROZEN';
      body = 'HTF opposing supply/demand. Wait for clear structure.';
    } else if (!signal.setupReady) {
      color = AppColors.accent;
      title = 'SOFT ALERT — WAITING ZONE';
      body = 'Zones only. Entry/SL/TP unlock when setup_ready=true.';
    } else {
      color = AppColors.primary;
      title = 'HARD SETUP — READY';
      body = 'Entry / SL / TP unlocked for this candle cycle.';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeAndTfSection(BuildContext context, TradingRoomLoaded state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
              items: TradingMode.values
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(mode.displayName),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(state.tradingMode.timeframeLabels.length, (
            i,
          ) {
            final tf = state.tradingMode.timeframes[i];
            final label = state.tradingMode.timeframeLabels[i];
            final isActive =
                state.currentTimeframe == tf ||
                (tf == '1440' &&
                    (state.currentTimeframe == 'D' ||
                        state.currentTimeframe == '1D'));
            return Expanded(
              child: GestureDetector(
                onTap: () =>
                    context.read<TradingRoomBloc>().add(ChangeTimeframe(tf)),
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
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isActive ? AppColors.secondary : Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSignalCard(BuildContext context, TradingSignal signal) {
    final isBuy = signal.type == 'BUY';
    final digits = SymbolMeta.of(signal.symbol).digits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, context.tr('exec_active_signal')),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (isBuy ? AppColors.primary : AppColors.bear).withValues(
                alpha: 0.2,
              ),
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    signal.symbol,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (isBuy ? AppColors.primary : AppColors.bear)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      signal.type,
                      style: TextStyle(
                        color: isBuy ? AppColors.primary : AppColors.bear,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (signal.veto || !signal.setupReady)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    signal.veto ? 'Status: VETO' : 'Status: SOFT (no Layer 4)',
                    style: TextStyle(
                      color: signal.veto ? AppColors.bear : AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (signal.setupReady && !signal.veto) ...[
                _infoRow(
                  context,
                  context.tr('exec_entry'),
                  signal.entryPrice.toStringAsFixed(digits),
                  Colors.white70,
                ),
                _infoRow(
                  context,
                  'SL',
                  signal.slPrice.toStringAsFixed(digits),
                  AppColors.bear,
                ),
              ],
              if (signal.probabilityAvailable)
                _infoRow(
                  context,
                  context.tr('exec_probability'),
                  '${signal.probability}%',
                  AppColors.accent,
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _executeTrade(
    BuildContext context,
    TradingRoomLoaded state,
    bool isBuy,
    double lot,
    double entry,
    double sl,
    TakeProfitAllocationPlan takeProfitPlan,
  ) {
    context.read<TradingRoomBloc>().add(
      ExecuteTrade(
        signalChartId: state.currentSignal?.chartId ?? '',
        type: isBuy ? 'BUY' : 'SELL',
        lotSize: lot,
        entryPrice: entry,
        slPrice: sl,
        tpPrices: takeProfitPlan.legs
            .map((leg) => leg.targetPrice)
            .toList(growable: false),
        takeProfitPlan: takeProfitPlan,
      ),
    );
  }

  Widget _buildAnalyzeButton(BuildContext context, TradingRoomLoaded state) {
    return GestureDetector(
      onTap: state.isAnalyzing || state.isCutoffActive
          ? null
          : () {
              context.read<TradingRoomBloc>().add(const RequestAnalysis());
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: state.isAnalyzing
                ? [Colors.grey.shade800, Colors.grey.shade700]
                : [
                    AppColors.secondary,
                    const Color(0xFF9370DB),
                  ], // Solid Pale Orchid to Medium Purple
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: state.isAnalyzing
              ? []
              : [
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
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            else
              const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Text(
              state.isAnalyzing
                  ? context.tr('ai_analyzing')
                  : context.tr('analyze_data'),
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
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: Colors.white.withValues(alpha: 0.4),
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _infoRow(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapitalRiskInputs(BuildContext context) {
    final isVi = Localizations.localeOf(context).languageCode == 'vi';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _smallInputField(
                  label: isVi ? 'SỐ DƯ (\$)' : 'BALANCE (\$)',
                  controller: _balanceController,
                  icon: Icons.account_balance_wallet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _smallInputField(
                  label: isVi ? 'RỦI RO (%)' : 'RISK (%)',
                  controller: _riskController,
                  icon: Icons.percent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _smallInputField(
                  label: isVi ? 'LỖ TỐI ĐA (%)' : 'MAX LOSS (%)',
                  controller: _maxLossController,
                  icon: Icons.warning_amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              isVi ? 'LƯU CẤU HÌNH' : 'SAVE CONFIG',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallInputField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
            ],
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                color: AppColors.primary.withValues(alpha: 0.8),
                size: 13,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.01),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 0,
              ),
              isDense: true,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _handleSave() {
    final balance = double.tryParse(_balanceController.text) ?? 0;
    final risk = double.tryParse(_riskController.text) ?? 1.0;
    final maxLoss = double.tryParse(_maxLossController.text) ?? 5.0;

    if (balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('risk_config_balance_error')),
          backgroundColor: AppColors.bear,
        ),
      );
      return;
    }
    if (risk < 0.1 || risk > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('risk_config_risk_error')),
          backgroundColor: AppColors.bear,
        ),
      );
      return;
    }
    if (maxLoss < 1 || maxLoss > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('risk_config_max_loss_error')),
          backgroundColor: AppColors.bear,
        ),
      );
      return;
    }

    final config = RiskConfig(
      balance: balance,
      riskPerTrade: risk,
      maxDailyLoss: maxLoss,
    );

    context.read<TradingRoomBloc>().add(SaveRiskConfig(config));
  }

  // ─── Bid/Ask Helpers ─────────────────────────────────────────

  static String _formatSpreadPips(double spread, String symbol) {
    final s = symbol.toUpperCase();
    if (s.contains('XAU')) {
      return (spread * 10).toStringAsFixed(1); // Gold: 1 pip = 0.1
    }
    if (s.contains('JPY')) return (spread * 100).toStringAsFixed(1);
    if (s.contains('BTC')) return spread.toStringAsFixed(0);
    if (s.contains('ETH')) return spread.toStringAsFixed(1);
    if (s.contains('US30') || s.contains('US500') || s.contains('US100')) {
      return spread.toStringAsFixed(1);
    }
    return (spread * 10000).toStringAsFixed(1); // Forex: 1 pip = 0.0001
  }

  Widget _buildBidAskDisplay(
    double bid,
    double ask,
    double spread,
    int digits,
    String symbol,
    bool hasMarketPrice,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          // Bid (Sell price)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bear.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.bear.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'BID',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: AppColors.bear.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasMarketPrice ? bid.toStringAsFixed(digits) : '—',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.bear,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Spread indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                const Text(
                  'SPREAD',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.white30,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasMarketPrice ? _formatSpreadPips(spread, symbol) : '—',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.white54,
                  ),
                ),
                const Text(
                  'pips',
                  style: TextStyle(fontSize: 7, color: Colors.white24),
                ),
              ],
            ),
          ),
          // Ask (Buy price)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'ASK',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: AppColors.primary.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasMarketPrice ? ask.toStringAsFixed(digits) : '—',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
