import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/colors.dart';
import '../../../core/localization/app_localizations.dart';
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
      create: (context) =>
          TradingRoomBloc(tradingRepository: context.read<TradingRepository>())
            ..add(LoadTradingData(userId: userId)),
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
                Expanded(child: _buildChartContainer()),
              ],
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(flex: 3, child: _OrderPanel()),
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
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
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
        double price = 0.0;
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
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: symbol,
                  dropdownColor: AppColors.surface,
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white54,
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      context.read<TradingRoomBloc>().add(
                        UpdateSymbol(newValue),
                      );
                    }
                  },
                  items: [
                    DropdownMenuItem(
                      value: 'XAUUSD',
                      child: Text(context.tr('xauusd_label')),
                    ),
                    DropdownMenuItem(
                      value: 'EURUSD',
                      child: Text(context.tr('eurusd_label')),
                    ),
                    DropdownMenuItem(
                      value: 'BTCUSD',
                      child: Text(context.tr('btcusd_label')),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.trending_up, color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                price > 0 ? '\$${price.toStringAsFixed(3)}' : context.tr('loading'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              _buildTimeframeBtn(
                context,
                '1M',
                '1',
                isActive:
                    state is TradingRoomLoaded && state.currentTimeframe == '1',
              ),
              _buildTimeframeBtn(
                context,
                '5M',
                '5',
                isActive:
                    state is TradingRoomLoaded && state.currentTimeframe == '5',
              ),
              _buildTimeframeBtn(
                context,
                '15M',
                '15',
                isActive:
                    state is TradingRoomLoaded &&
                    state.currentTimeframe == '15',
              ),
              _buildTimeframeBtn(
                context,
                '1H',
                '60',
                isActive:
                    state is TradingRoomLoaded &&
                    state.currentTimeframe == '60',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTimeframeBtn(
    BuildContext context,
    String label,
    String value, {
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: () {
        context.read<TradingRoomBloc>().add(ChangeTimeframe(value));
      },
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isActive ? AppColors.primary : Colors.white10,
          ),
        ),
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
}

class _OrderPanel extends StatefulWidget {
  const _OrderPanel();

  @override
  State<_OrderPanel> createState() => _OrderPanelState();
}

class _OrderPanelState extends State<_OrderPanel> {
  final TextEditingController _lotController = TextEditingController(
    text: '0.10',
  );

  @override
  void dispose() {
    _lotController.dispose();
    super.dispose();
  }

  void _handleTrade(BuildContext context, String type) {
    final lot = double.tryParse(_lotController.text) ?? 0.10;
    context.read<TradingRoomBloc>().add(ExecuteTrade(type: type, lotSize: lot));

    final msg = context.tr('order_executed').replaceAll('{type}', type).replaceAll('{lot}', lot.toString());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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
              Text(
                context.tr('execution_engine'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white54,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 24),
              _buildInputLabel(context.tr('lot_size')),
              TextField(
                controller: _lotController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: '0.10',
                  hintStyle: TextStyle(color: Colors.white24),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white10),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: _buildTradeBtn(
                      context,
                      context.tr('sell'),
                      AppColors.bear,
                      currentPrice,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTradeBtn(
                      context,
                      context.tr('buy'),
                      AppColors.primary,
                      currentPrice,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    context.read<TradingRoomBloc>().add(
                      const RequestAnalysis(),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr('analyzing_request'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: AppColors.primary,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: const Icon(Icons.analytics, color: Colors.black),
                  label: Text(
                    context.tr('analyze_data'),
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                context.tr('active_signals'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: Colors.white54,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 16),
              if (state is TradingRoomLoaded && state.currentSignal != null)
                _buildSignalCard(
                  state.currentSignal!.symbol,
                  '${state.currentSignal!.type} @ ${state.currentSignal!.entryPrice.toStringAsFixed(3)}',
                  '${state.currentSignal!.probability}% Prob.',
                )
              else
                Text(
                  context.tr('no_signals'),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 9,
        color: Colors.white38,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildTradeBtn(
    BuildContext context,
    String label,
    Color color,
    double price,
  ) {
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
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                fontSize: 14,
              ),
            ),
            if (price > 0)
              Text(
                price.toStringAsFixed(3),
                style: TextStyle(
                  color: color.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
              Text(
                symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                desc,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
          Text(
            prob,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
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
            child: BlocBuilder<TradingRoomBloc, TradingRoomState>(
              builder: (context, state) {
                String equity = '42,050.00';
                if (state is TradingRoomLoaded) {
                  equity = state.account.equity.toStringAsFixed(2);
                }
                return Row(
                  children: [
                    Text(
                      '${context.tr('equity')}: \$$equity',
                      style: const TextStyle(
                        color: Color(0xFFc3c6d8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () => _showSyncDialog(context),
                      icon: const Icon(
                        Icons.link,
                        size: 14,
                        color: AppColors.primary,
                      ),
                      label: Text(
                        context.tr('link_api'),
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: AppColors.primary.withOpacity(0.1),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const Icon(Icons.rss_feed, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 16),
          const Icon(Icons.notifications, color: Color(0xFFc3c6d8), size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 18),
          ),
        ],
      ),
    );
  }

  void _showSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(
            context.tr('link_broker_title'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('link_broker_desc'),
                style: const TextStyle(color: AppColors.primary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: context.tr('account_number'),
                  labelStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: context.tr('investor_password'),
                  labelStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: context.tr('broker_server'),
                  labelStyle: const TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                context.tr('cancel'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('sending_link_request'))),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: Text(
                context.tr('link_now'),
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
