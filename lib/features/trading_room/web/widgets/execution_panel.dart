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
  final List<bool> _tpActive = [true, true, false];
  late AnimationController _glowController;
  final TextEditingController _balanceController = TextEditingController();
  final TextEditingController _riskController = TextEditingController();
  final TextEditingController _maxLossController = TextEditingController();
  bool _isInitialized = false;
  int _lastPanelResetNonce = -1;

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
    super.dispose();
  }

  void _resetPanelForSymbol() {
    _tpActive[0] = true;
    _tpActive[1] = true;
    _tpActive[2] = false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TradingRoomBloc, TradingRoomState>(
      listenWhen: (prev, curr) {
        if (prev is! TradingRoomLoaded || curr is! TradingRoomLoaded)
          return false;
        return prev.panelResetNonce != curr.panelResetNonce ||
            prev.currentSymbol != curr.currentSymbol;
      },
      listener: (context, state) {
        if (state is TradingRoomLoaded) {
          setState(_resetPanelForSymbol);
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
                signal.symbol.toUpperCase() == state.currentSymbol.toUpperCase()
            ? signal
            : null;
        final hardSetup =
            matchedSignal != null &&
            matchedSignal.setupReady &&
            !matchedSignal.veto;
        final tradeLocked = matchedSignal?.veto == true;

        final isBuy = matchedSignal?.type == 'BUY' || matchedSignal == null;
        final currentPrice = state.candles.isNotEmpty
            ? state.candles.last.close
            : (state.symbolPrices[state.currentSymbol.toUpperCase()] ?? 0.0);
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
                if (signal != null &&
                    signal.symbol.toUpperCase() ==
                        state.currentSymbol.toUpperCase())
                  _buildStageBanner(signal),

                // ── Bid / Ask Price Display ──
                _buildBidAskDisplay(
                  bid,
                  ask,
                  spread,
                  digits,
                  state.currentSymbol,
                ),
                const SizedBox(height: 16),

                // Header
                _sectionTitle(context, context.tr('exec_engine')),
                const SizedBox(height: 10),
                _buildCapitalRiskInputs(context),
                const SizedBox(height: 16),

                // Lot Size + Risk
                _infoRow(
                  context,
                  context.tr('exec_suggested_lot'),
                  suggestedLot.toStringAsFixed(2),
                  AppColors.accent,
                ),
                const SizedBox(height: 6),
                _infoRow(
                  context,
                  context.tr('exec_risk'),
                  '\$${riskAmount.toStringAsFixed(2)} (${riskPct.toStringAsFixed(1)}%)',
                  riskPct > 3 ? AppColors.bear : AppColors.primary,
                ),
                const SizedBox(height: 4),
                _infoRow(
                  context,
                  context.tr('exec_entry'),
                  (signal != null &&
                          signal.symbol.toUpperCase() ==
                              state.currentSymbol.toUpperCase() &&
                          signal.setupReady &&
                          !signal.veto)
                      ? entryPrice.toStringAsFixed(digits)
                      : currentPrice.toStringAsFixed(digits),
                  Colors.white,
                ),

                const SizedBox(height: 16),

                // Stop Loss — SINGLE level only
                _sectionTitle(context, context.tr('exec_stop_loss')),
                const SizedBox(height: 8),
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
                _sectionTitle(context, context.tr('exec_take_profit')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: List.generate(3, (i) {
                    return GestureDetector(
                      onTap: () => setState(() => _tpActive[i] = !_tpActive[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 100,
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
                            Text(
                              'TP${i + 1}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _tpActive[i]
                                    ? AppColors.primary
                                    : Colors.white38,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              displayTPs[i].toStringAsFixed(digits),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _tpActive[i]
                                    ? AppColors.primary
                                    : Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 20),

                // ── Dual BUY / SELL Buttons ──
                if (state.isCutoffActive)
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
                              onTap: (state.isTradeExecuting || tradeLocked)
                                  ? null
                                  : () => _executeTrade(
                                      context,
                                      state,
                                      false,
                                      suggestedLot,
                                      entryPrice,
                                      selectedSLPrice,
                                      displayTPs,
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
                                    if (signal != null && !isBuy)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'AI ▼ ${signal.probability}%',
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
                              onTap: (state.isTradeExecuting || tradeLocked)
                                  ? null
                                  : () => _executeTrade(
                                      context,
                                      state,
                                      true,
                                      suggestedLot,
                                      entryPrice,
                                      selectedSLPrice,
                                      displayTPs,
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
                                    if (signal != null && isBuy)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'AI ▲ ${signal.probability}%',
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
                if (signal != null &&
                    signal.symbol.toUpperCase() ==
                        state.currentSymbol.toUpperCase())
                  _buildSignalCard(context, signal),
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
      body =
          signal.forecastText ??
          'HTF opposing supply/demand. Wait for clear structure.';
    } else if (!signal.setupReady) {
      color = AppColors.accent;
      title = 'SOFT ALERT — WAITING ZONE';
      body =
          signal.forecastText ??
          'Zones only. Entry/SL/TP unlock when setup_ready=true.';
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
    List<double> tps,
  ) {
    final activeTPs = <double>[];
    for (int i = 0; i < _tpActive.length && i < tps.length; i++) {
      if (_tpActive[i]) activeTPs.add(tps[i]);
    }

    context.read<TradingRoomBloc>().add(
      ExecuteTrade(
        type: isBuy ? 'BUY' : 'SELL',
        lotSize: lot,
        entryPrice: entry,
        slPrice: sl,
        tpPrices: activeTPs,
      ),
    );

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
      onTap: state.isAnalyzing
          ? null
          : () {
              context.read<TradingRoomBloc>().add(const RequestAnalysis());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.tr('analyzing_request'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
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

    final isVi = Localizations.localeOf(context).languageCode == 'vi';

    if (balance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isVi ? 'Số dư phải lớn hơn 0' : 'Balance must be greater than 0',
          ),
          backgroundColor: AppColors.bear,
        ),
      );
      return;
    }
    if (risk <= 0 || risk > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isVi
                ? 'Rủi ro không hợp lệ (0-100%)'
                : 'Invalid risk percentage (0-100%)',
          ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isVi
              ? 'Đã lưu cấu hình thành công!'
              : 'Configuration saved successfully!',
        ),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  // ─── Bid/Ask Helpers ─────────────────────────────────────────

  static String _formatSpreadPips(double spread, String symbol) {
    final s = symbol.toUpperCase();
    if (s.contains('XAU'))
      return (spread * 10).toStringAsFixed(1); // Gold: 1 pip = 0.1
    if (s.contains('JPY')) return (spread * 100).toStringAsFixed(1);
    if (s.contains('BTC')) return spread.toStringAsFixed(0);
    if (s.contains('ETH')) return spread.toStringAsFixed(1);
    if (s.contains('US30') || s.contains('US500') || s.contains('US100'))
      return spread.toStringAsFixed(1);
    return (spread * 10000).toStringAsFixed(1); // Forex: 1 pip = 0.0001
  }

  Widget _buildBidAskDisplay(
    double bid,
    double ask,
    double spread,
    int digits,
    String symbol,
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
                    bid.toStringAsFixed(digits),
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
                  _formatSpreadPips(spread, symbol),
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
                    ask.toStringAsFixed(digits),
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
