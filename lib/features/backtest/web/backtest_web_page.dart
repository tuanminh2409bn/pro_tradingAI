import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../../auth/bloc/auth_event.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../data/repositories/backtest_repository.dart';
import '../../../data/repositories/trading_repository.dart';
import '../../../data/models/trading_models.dart';
import '../../trading_room/web/widgets/kinetic_chart.dart';
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
        TradingRepository? tradingRepository;
        return BacktestBloc(
          backtestRepository: context.read<BacktestRepository>(),
          historyStream: (symbol) {
            final history = tradingRepository ??= TradingRepository();
            history.changeSymbol(symbol);
            return history.getCandleStream(symbol);
          },
          disposeHistory: () => tradingRepository?.dispose(),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Column(
          children: [
            _WebTopNavbar(onMenuPressed: onMenuPressed),
            Expanded(
              child: BlocBuilder<BacktestBloc, BacktestState>(
                builder: (context, state) {
                  if (state is BacktestInitial) {
                    return _BacktestSetup(userId: userId);
                  }
                  if (state is BacktestLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  if (state is BacktestError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr(state.message),
                            style: const TextStyle(color: AppColors.bear),
                          ),
                          TextButton(
                            onPressed: () => context.read<BacktestBloc>().add(
                              OpenBacktestSetup(),
                            ),
                            child: Text(context.tr('backtest_setup')),
                          ),
                        ],
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
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  if (constraints.maxWidth < 800) {
                                    return Column(
                                      children: [
                                        SizedBox(
                                          height: 300,
                                          width: double.infinity,
                                          child: _buildTradingPanel(
                                            context,
                                            state,
                                          ),
                                        ),
                                        Expanded(
                                          child: _buildChartCanvas(
                                            context,
                                            state,
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                  return Row(
                                    children: [
                                      _buildTradingPanel(context, state),
                                      Expanded(
                                        child: _buildChartCanvas(
                                          context,
                                          state,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        if (session.isLocked)
                          _buildDisciplineLockOverlay(context, state),
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
              context.tr('backtest_symbol'),
              session.symbol,
              subtitle: context.tr('backtest_training'),
            ),
            const SizedBox(width: 40),
            _buildHeaderMetric(
              context.tr('backtest_initial_balance'),
              '${session.initialBalance.toStringAsFixed(2)} ${_currency(state)}',
              icon: Icons.account_balance_wallet,
            ),
          ],
        ),
        _buildPlaybackControls(context, state),
        Row(
          children: [
            _buildHeaderMetric(
              context.tr('backtest_equity'),
              '${session.equity.toStringAsFixed(2)} ${_currency(state)}',
              isNumeric: true,
              textAlign: CrossAxisAlignment.end,
            ),
            const SizedBox(width: 24),
            _buildHeaderMetric(
              context.tr('backtest_open_pnl'),
              '${session.openPL.toStringAsFixed(2)} ${_currency(state)}',
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
            onPressed: state.cursor == 0 || !state.canRewind
                ? null
                : () => context.read<BacktestBloc>().add(
                    const SeekReplayCursor(0),
                  ),
            icon: const Icon(Icons.first_page, size: 18),
          ),
          IconButton(
            tooltip: context.tr('backtest_previous_candle'),
            onPressed: state.cursor == 0 || !state.canRewind
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
            enabled: state.isSaved && !session.isLocked,
            child: Tooltip(
              message: context.tr(
                session.isPlaying ? 'backtest_pause' : 'backtest_play',
              ),
              excludeFromSemantics: true,
              child: InkWell(
                onTap: !state.isSaved || session.isLocked
                    ? null
                    : () => context.read<BacktestBloc>().add(TogglePlayback()),
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
            onPressed:
                state.cursor >= state.totalBars - 1 ||
                    !state.isSaved ||
                    session.isLocked
                ? null
                : () => context.read<BacktestBloc>().add(
                    const StepReplayCursor(1),
                  ),
            icon: const Icon(Icons.fast_forward, size: 18),
          ),
          const SizedBox(width: 8),
          const VerticalDivider(color: Colors.white10, indent: 8, endIndent: 8),
          const SizedBox(width: 8),
          Text(
            context.tr('backtest_speed'),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: Colors.white38,
            ),
          ),
          const SizedBox(width: 8),
          _buildSpeedBtn(
            context,
            '1X',
            isActive: session.speed == 1,
            speed: 1,
            enabled: state.isSaved && !session.isLocked,
          ),
          _buildSpeedBtn(
            context,
            '5X',
            isActive: session.speed == 5,
            speed: 5,
            enabled: state.isSaved && !session.isLocked,
          ),
          _buildSpeedBtn(
            context,
            '10X',
            isActive: session.speed == 10,
            speed: 10,
            enabled: state.isSaved && !session.isLocked,
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
    required bool enabled,
  }) {
    return InkWell(
      onTap: !enabled
          ? null
          : () => context.read<BacktestBloc>().add(UpdateSpeed(speed)),
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

  String _currency(BacktestLoaded state) {
    final symbol = state.session.symbol;
    return symbol.length >= 6 ? symbol.substring(symbol.length - 3) : '';
  }

  Widget _buildTradingPanel(BuildContext context, BacktestLoaded state) {
    final activeTrades = state.activeTrades;
    final currentPrice = state.visibleBars.last.close;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: Colors.white10)),
      ),
      child: ListView(
        children: [
          Text(
            context.tr('backtest_replay_status'),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.primary,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 24),
          _buildInputLabel(context.tr('backtest_closed_price')),
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
          Text(
            context.tr('backtest_execution_basis'),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          if (state.errorKey != null)
            Text(
              context.tr(state.errorKey!),
              style: const TextStyle(color: AppColors.bear),
            ),
          if (!state.isSaved)
            TextButton(
              onPressed: () =>
                  context.read<BacktestBloc>().add(RetryBacktestSave()),
              child: Text(context.tr('backtest_retry_save')),
            ),
          _BacktestOrderControls(
            enabled: state.isSaved && !state.session.isLocked,
          ),
          TextButton(
            onPressed: !state.isSaved || state.session.isLocked
                ? null
                : () => context.read<BacktestBloc>().add(OpenBacktestSetup()),
            child: Text(context.tr('backtest_setup')),
          ),
          const SizedBox(height: 16),
          for (final trade in activeTrades)
            Column(
              children: [
                _buildActiveTradeItem(
                  '${trade.type} ${trade.volume}',
                  '${trade.profit.toStringAsFixed(2)} ${_currency(state)}',
                  trade.profit >= 0,
                ),
                TextButton(
                  onPressed: !state.isSaved || state.session.isLocked
                      ? null
                      : () => context.read<BacktestBloc>().add(
                          CloseBacktestTrade(trade.id!),
                        ),
                  child: Text(
                    '${context.tr('backtest_close_trade')} ${trade.type}',
                  ),
                ),
              ],
            ),
          for (final trade in state.closedTrades.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildActiveTradeItem(
                '${context.tr('backtest_closed')} ${trade.side.name.toUpperCase()}',
                '${trade.realizedPnl.toStringAsFixed(2)} ${_currency(state)}',
                trade.realizedPnl >= 0,
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
          Positioned.fill(
            bottom: 105,
            child: KineticChart(
              key: ValueKey('backtest:${session.id}'),
              symbol: session.symbol,
              candles: state.visibleBars
                  .map(
                    (bar) => Candle(
                      timestamp: DateTime.fromMillisecondsSinceEpoch(
                        bar.timestamp * 1000,
                        isUtc: true,
                      ),
                      open: bar.open,
                      high: bar.high,
                      low: bar.low,
                      close: bar.close,
                      volume: bar.volume,
                    ),
                  )
                  .toList(),
              now: () => DateTime.fromMillisecondsSinceEpoch(
                state.visibleBars.last.timestamp * 1000,
                isUtc: true,
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
                  onChanged: !state.canRewind
                      ? null
                      : (value) => context.read<BacktestBloc>().add(
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

  Widget _buildDisciplineLockOverlay(
    BuildContext context,
    BacktestLoaded state,
  ) {
    final review = state.pendingReview!;
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
              Text(
                context.tr('backtest_review_required'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context
                    .tr('backtest_review_summary')
                    .replaceAll(
                      '{loss}',
                      '${review.lossAmount.toStringAsFixed(2)} ${_currency(state)}',
                    )
                    .replaceAll('{count}', review.closedTradeCount.toString()),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: !state.isSaved
                      ? () => context.read<BacktestBloc>().add(
                          RetryBacktestSave(),
                        )
                      : () => context.read<BacktestBloc>().add(
                          AcknowledgeBacktestReview(review.id),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white10,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: Text(
                    context.tr(
                      state.isSaved
                          ? 'backtest_acknowledge'
                          : 'backtest_retry_save',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
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

class _BacktestSetup extends StatefulWidget {
  final String? userId;
  const _BacktestSetup({required this.userId});
  @override
  State<_BacktestSetup> createState() => _BacktestSetupState();
}

class _BacktestSetupState extends State<_BacktestSetup> {
  final _form = GlobalKey<FormState>();
  final _symbol = TextEditingController(text: 'BTCUSD');
  final _balance = TextEditingController(text: '10000');
  final _loss = TextEditingController(text: '5');
  bool _createNew = false;

  @override
  void dispose() {
    _symbol.dispose();
    _balance.dispose();
    _loss.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('backtest_setup'),
                style: const TextStyle(color: AppColors.primary, fontSize: 22),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('backtest_resume_hint'),
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _symbol,
                decoration: InputDecoration(
                  labelText: context.tr('backtest_symbol'),
                ),
                validator: (value) =>
                    RegExp(
                      r'^[A-Z]{6,9}$',
                    ).hasMatch((value ?? '').trim().toUpperCase())
                    ? null
                    : context.tr('backtest_invalid_action'),
              ),
              TextFormField(
                controller: _balance,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('backtest_initial_balance'),
                ),
                validator: (value) {
                  final number = double.tryParse(value ?? '');
                  return number != null && number.isFinite && number > 0
                      ? null
                      : context.tr('backtest_invalid_action');
                },
              ),
              TextFormField(
                controller: _loss,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('backtest_max_loss'),
                ),
                validator: (value) {
                  final number = double.tryParse(value ?? '');
                  return number != null &&
                          number.isFinite &&
                          number > 0 &&
                          number <= 100
                      ? null
                      : context.tr('backtest_invalid_action');
                },
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _createNew,
                title: Text(context.tr('backtest_new_session')),
                onChanged: (value) =>
                    setState(() => _createNew = value ?? false),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  context.read<BacktestBloc>().add(
                    StartBacktestSession(
                      _symbol.text.trim().toUpperCase(),
                      double.parse(_balance.text),
                      userId: widget.userId,
                      maxLossPercent: double.parse(_loss.text),
                      createNew: _createNew,
                    ),
                  );
                },
                child: Text(context.tr('backtest_start_resume')),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BacktestOrderControls extends StatefulWidget {
  final bool enabled;
  const _BacktestOrderControls({required this.enabled});
  @override
  State<_BacktestOrderControls> createState() => _BacktestOrderControlsState();
}

class _BacktestOrderControlsState extends State<_BacktestOrderControls> {
  final _quantity = TextEditingController(text: '1');
  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: _quantity,
        enabled: widget.enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: context.tr('backtest_quantity')),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final side in ['BUY', 'SELL'])
            Expanded(
              child: FilledButton(
                onPressed: !widget.enabled
                    ? null
                    : () {
                        context.read<BacktestBloc>().add(
                          ExecuteBacktestTrade(
                            side,
                            double.tryParse(_quantity.text) ?? 0,
                          ),
                        );
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: side == 'BUY'
                      ? AppColors.bull
                      : AppColors.bear,
                ),
                child: Text(side),
              ),
            ),
        ],
      ),
    ],
  );
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
