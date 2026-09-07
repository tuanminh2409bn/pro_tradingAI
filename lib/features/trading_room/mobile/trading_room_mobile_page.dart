import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../../../data/models/trading_models.dart';
import '../../../data/repositories/trading_repository.dart';
import '../bloc/trading_room_bloc.dart';
import '../bloc/trading_room_event.dart';
import '../bloc/trading_room_state.dart';
import '../web/widgets/execution_panel.dart';
import '../web/widgets/kinetic_chart.dart';
import '../web/widgets/news_red_zone_binder.dart';

/// Day 6 mobile parity — TF matrix, ExecutionPanel (1 SL / 2-stage), Red Zone.
class TradingRoomMobilePage extends StatelessWidget {
  final String? userId;
  const TradingRoomMobilePage({super.key, this.userId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          TradingRoomBloc(tradingRepository: context.read<TradingRepository>())
            ..add(LoadTradingData(userId: userId)),
      child: NewsRedZoneBinder(
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
              BlocBuilder<TradingRoomBloc, TradingRoomState>(
                builder: (context, state) {
                  final equity = state is TradingRoomLoaded
                      ? state.account.equity
                      : 0.0;
                  final pnl = state is TradingRoomLoaded ? state.totalPnL : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'EQ \$${equity.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'P&L ${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: pnl >= 0
                                ? AppColors.primary
                                : AppColors.bear,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: BlocBuilder<TradingRoomBloc, TradingRoomState>(
            builder: (context, state) {
              if (state is TradingRoomError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        state.message,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => context.read<TradingRoomBloc>().add(
                          LoadTradingData(userId: userId),
                        ),
                        child: const Text('RETRY'),
                      ),
                    ],
                  ),
                );
              }
              if (state is! TradingRoomLoaded) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              return Column(
                children: [
                  if (state.newsRedZoneLabel != null)
                    _MobileRedZoneBanner(label: state.newsRedZoneLabel!),
                  _MobileModeTfBar(state: state),
                  _MobileStageBanner(signal: state.currentSignal),
                  Expanded(
                    child: KineticChart(
                      symbol: state.currentSymbol,
                      signal: state.currentSignal,
                      candles: state.candles,
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.42,
                    child: const SingleChildScrollView(child: ExecutionPanel()),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobileRedZoneBanner extends StatelessWidget {
  final String label;
  const _MobileRedZoneBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.bear.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        'RED ZONE · ${label.replaceFirst('NEWS ', '')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.bear,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MobileStageBanner extends StatelessWidget {
  final TradingSignal? signal;
  const _MobileStageBanner({required this.signal});

  @override
  Widget build(BuildContext context) {
    if (signal == null) return const SizedBox.shrink();
    final Color color;
    final String text;
    if (signal!.veto) {
      color = AppColors.bear;
      text = 'VETO — ENTRY FROZEN';
    } else if (!signal!.setupReady) {
      color = AppColors.accent;
      text = 'SOFT — WAITING ZONE';
    } else {
      color = AppColors.primary;
      text = 'HARD SETUP — READY';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: color.withValues(alpha: 0.12),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _MobileModeTfBar extends StatelessWidget {
  final TradingRoomLoaded state;
  const _MobileModeTfBar({required this.state});

  @override
  Widget build(BuildContext context) {
    final mode = state.tradingMode;
    final tfs = const [
      {'label': 'M5', 'value': '5'},
      {'label': 'M15', 'value': '15'},
      {'label': 'H1', 'value': '60'},
      {'label': 'H4', 'value': '240'},
      {'label': 'D1', 'value': '1440'},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        children: [
          Row(
            children: TradingMode.values.map((m) {
              final active = m == mode;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: () => context.read<TradingRoomBloc>().add(
                      ChangeTradingMode(m),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary.withValues(alpha: 0.15)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: active
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        m.displayName.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: active ? AppColors.primary : Colors.white54,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Row(
            children: tfs.map((tf) {
              final value = tf['value']!;
              final allowed = mode.allowsTimeframe(value);
              final active = state.currentTimeframe == value;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: InkWell(
                    onTap: !allowed
                        ? null
                        : () => context.read<TradingRoomBloc>().add(
                            ChangeTimeframe(value),
                          ),
                    child: Opacity(
                      opacity: allowed ? 1 : 0.35,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.entry.withValues(alpha: 0.2)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tf['label']!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: active ? AppColors.entry : Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
