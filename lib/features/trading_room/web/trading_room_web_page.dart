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
import '../../../data/models/trading_models.dart';
import 'widgets/kinetic_chart.dart';
import 'widgets/execution_panel.dart';
import 'widgets/terminal_panel.dart';
import 'widgets/ai_chat_panel.dart';
import 'widgets/live_data_bar.dart';
import 'widgets/chart_tools_sidebar.dart';
import 'widgets/input_constraint_modal.dart';
import 'widgets/news_red_zone_binder.dart';

class TradingRoomWebPage extends StatefulWidget {
  final String? userId;
  final VoidCallback? onMenuPressed;
  const TradingRoomWebPage({super.key, this.userId, this.onMenuPressed});

  @override
  State<TradingRoomWebPage> createState() => _TradingRoomWebPageState();
}

class _TradingRoomWebPageState extends State<TradingRoomWebPage> {
  ChartTool _activeTool = ChartTool.pointer;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          TradingRoomBloc(tradingRepository: context.read<TradingRepository>())
            ..add(LoadTradingData(userId: widget.userId)),
      child: NewsRedZoneBinder(
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: BlocConsumer<TradingRoomBloc, TradingRoomState>(
            listenWhen: (prev, curr) {
              if (curr is TradingRoomLoaded) {
                final prevLoaded = prev is TradingRoomLoaded ? prev : null;
                final justLoaded =
                    prevLoaded == null || !prevLoaded.isRiskConfigLoaded;
                return curr.isRiskConfigLoaded &&
                    !curr.isRiskConfigured &&
                    justLoaded;
              }
              return false;
            },
            listener: (context, state) {
              if (state is TradingRoomLoaded &&
                  state.isRiskConfigLoaded &&
                  !state.isRiskConfigured) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  InputConstraintModal.show(context);
                });
              }
            },
            builder: (context, state) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final isMobile = constraints.maxWidth < 900;
                  return Column(
                    children: [
                      _WebTopNavbar(onMenuPressed: widget.onMenuPressed),
                      const LiveDataBar(),
                      if (state is TradingRoomLoaded &&
                          state.newsRedZoneLabel != null)
                        _NewsRedZoneBanner(label: state.newsRedZoneLabel!),
                      Expanded(
                        child: isMobile
                            ? _buildMobileLayout(context)
                            : _buildDesktopLayout(context),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return Row(
      children: [
        // Left: Chart Tools Sidebar — now connected
        ChartToolsSidebar(
          activeTool: _activeTool,
          onToolChanged: (tool) => setState(() => _activeTool = tool),
        ),
        // Center: Chart + Terminal
        Expanded(
          child: Column(
            children: [
              const _SubTabBar(),
              Expanded(child: _buildChartContainer()),
              const SizedBox(height: 220, child: TerminalPanel()),
            ],
          ),
        ),
        // Right: Execution Panel + AI Chat
        const SizedBox(width: 380, child: _ResizableRightPanel()),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          SizedBox(height: 400, child: _buildChartContainer()),
          const ExecutionPanel(),
          const SizedBox(height: 250, child: TerminalPanel()),
          const SizedBox(height: 300, child: AIChatPanel()),
        ],
      ),
    );
  }

  Widget _buildChartContainer() {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: BlocBuilder<TradingRoomBloc, TradingRoomState>(
        builder: (context, state) {
          if (state is TradingRoomLoaded) {
            return KineticChart(
              symbol: state.currentSymbol,
              candles: state.candles,
              signal: state.currentSignal,
              activeTool: _activeTool,
            );
          } else if (state is TradingRoomError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.bear,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${state.message}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.read<TradingRoomBloc>().add(
                      LoadTradingData(userId: widget.userId),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text('RETRY'),
                  ),
                ],
              ),
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

class _NewsRedZoneBanner extends StatelessWidget {
  final String label;
  const _NewsRedZoneBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.bear.withValues(alpha: 0.18),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.bear,
            size: 16,
          ),
          const SizedBox(width: 8),
          const Text(
            'RED ZONE',
            style: TextStyle(
              color: AppColors.bear,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label.replaceFirst('NEWS ', ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: () =>
                context.read<TradingRoomBloc>().add(const ClearNewsRedZone()),
            child: const Text('DISMISS', style: TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );
  }
}

// ─── All Symbols Data ───
const _symbolGroups = [
  _SymbolGroup(
    name: '🏆 Metals',
    symbols: [
      _Symbol('XAUUSD', '🥇 Gold / USD', 'XAUUSD'),
      _Symbol('XAGUSD', '🥈 Silver / USD', 'XAGUSD'),
      _Symbol('XPTUSD', 'Platinum / USD', 'XPTUSD'),
      _Symbol('XPDUSD', 'Palladium / USD', 'XPDUSD'),
    ],
  ),
  _SymbolGroup(
    name: '📈 Forex Majors',
    symbols: [
      _Symbol('EURUSD', '💶 EUR / USD', 'EURUSD'),
      _Symbol('GBPUSD', '💷 GBP / USD', 'GBPUSD'),
      _Symbol('USDJPY', '💴 USD / JPY', 'USDJPY'),
      _Symbol('USDCHF', '🇨🇭 USD / CHF', 'USDCHF'),
      _Symbol('AUDUSD', '🇦🇺 AUD / USD', 'AUDUSD'),
      _Symbol('USDCAD', '🇨🇦 USD / CAD', 'USDCAD'),
      _Symbol('NZDUSD', '🇳🇿 NZD / USD', 'NZDUSD'),
    ],
  ),
  _SymbolGroup(
    name: '📊 Forex Minors',
    symbols: [
      _Symbol('EURGBP', 'EUR / GBP', 'EURGBP'),
      _Symbol('EURJPY', 'EUR / JPY', 'EURJPY'),
      _Symbol('GBPJPY', '💷 GBP / JPY', 'GBPJPY'),
      _Symbol('EURAUD', 'EUR / AUD', 'EURAUD'),
      _Symbol('GBPAUD', 'GBP / AUD', 'GBPAUD'),
      _Symbol('AUDNZD', 'AUD / NZD', 'AUDNZD'),
      _Symbol('CADCHF', 'CAD / CHF', 'CADCHF'),
      _Symbol('AUDCAD', 'AUD / CAD', 'AUDCAD'),
      _Symbol('AUDCHF', 'AUD / CHF', 'AUDCHF'),
      _Symbol('NZDJPY', 'NZD / JPY', 'NZDJPY'),
    ],
  ),
  _SymbolGroup(
    name: '🛢️ Commodities',
    symbols: [
      _Symbol('USOIL', '🛢️ WTI Crude Oil', 'WTI'),
      _Symbol('UKOIL', '🛢️ Brent Crude', 'BRENT'),
      _Symbol('NGAS', '🔥 Natural Gas', 'NGAS'),
      _Symbol('CORN', '🌽 Corn', 'CORN'),
      _Symbol('WHEAT', '🌾 Wheat', 'WHEAT'),
      _Symbol('SOYBN', '🫘 Soybeans', 'SOYBN'),
      _Symbol('COPPER', '🔶 Copper', 'COPPER'),
    ],
  ),
  _SymbolGroup(
    name: '📉 Indices',
    symbols: [
      _Symbol('US30', '🗽 Dow Jones 30', 'US30'),
      _Symbol('US500', '🇺🇸 S&P 500', 'US500'),
      _Symbol('US100', '💻 Nasdaq 100', 'US100'),
      _Symbol('UK100', '🇬🇧 FTSE 100', 'UK100'),
      _Symbol('DE40', '🇩🇪 DAX 40', 'DE40'),
      _Symbol('JP225', '🇯🇵 Nikkei 225', 'JP225'),
      _Symbol('FR40', '🇫🇷 CAC 40', 'FR40'),
      _Symbol('AU200', '🇦🇺 ASX 200', 'AU200'),
      _Symbol('HK50', '🇭🇰 Hang Seng 50', 'HK50'),
      _Symbol('CHINA50', '🇨🇳 China A50', 'CHINA50'),
    ],
  ),
  _SymbolGroup(
    name: '₿ Crypto',
    symbols: [
      _Symbol('BTCUSD', '₿ Bitcoin / USD', 'BTC'),
      _Symbol('ETHUSD', '⟠ Ethereum / USD', 'ETH'),
      _Symbol('BNBUSD', '🟡 BNB / USD', 'BNB'),
      _Symbol('SOLUSD', '◎ Solana / USD', 'SOL'),
      _Symbol('XRPUSD', '🔷 XRP / USD', 'XRP'),
      _Symbol('ADAUSD', '🔵 Cardano / USD', 'ADA'),
      _Symbol('DOTUSD', 'Polkadot / USD', 'DOT'),
      _Symbol('LINKUSD', '🔗 Chainlink / USD', 'LINK'),
    ],
  ),
];

class _SymbolGroup {
  final String name;
  final List<_Symbol> symbols;
  const _SymbolGroup({required this.name, required this.symbols});
}

class _Symbol {
  final String value; // sent to bloc (e.g. XAUUSD)
  final String label; // displayed in UI
  final String short; // short ticker for tab
  const _Symbol(this.value, this.label, this.short);
}

// ─── Sub Tab Bar ───
class _SubTabBar extends StatelessWidget {
  const _SubTabBar();

  static const _timeframes = [
    {'value': '5', 'label': 'M5'},
    {'value': '15', 'label': 'M15'},
    {'value': '60', 'label': 'H1'},
    {'value': '240', 'label': 'H4'},
    {'value': '1440', 'label': 'D1'},
  ];

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingRoomBloc, TradingRoomState>(
      builder: (context, state) {
        String symbol = 'XAUUSD';
        String currentTf = '5';
        TradingMode mode = TradingMode.scalping;
        if (state is TradingRoomLoaded) {
          symbol = state.currentSymbol;
          currentTf = state.currentTimeframe;
          mode = state.tradingMode;
        }

        return Container(
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              _SubTab(
                label: context.tr('tr_tab_label'),
                isActive: true,
                activeColor: AppColors.primary,
              ),
              const SizedBox(width: 2),
              _SubTab(
                label: '$symbol ${_formatTimeframe(currentTf)}',
                isActive: false,
                activeColor: AppColors.secondary,
                isSymbolTab: true,
              ),
              const SizedBox(width: 8),
              // ── Vertical divider ──
              Container(
                width: 1,
                height: 20,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              const SizedBox(width: 6),
              // ── Timeframe selector — only mode TFs active (V2.1 P0#6) ──
              for (final tf in _timeframes) ...[
                _TimeframeButton(
                  label: tf['label']!,
                  isActive:
                      currentTf == tf['value'] ||
                      (tf['value'] == '1440' &&
                          (currentTf == 'D' || currentTf == '1D')),
                  isEnabled: mode.allowsTimeframe(tf['value']!),
                  onTap: () {
                    if (!mode.allowsTimeframe(tf['value']!)) return;
                    if (currentTf != tf['value']) {
                      context.read<TradingRoomBloc>().add(
                        ChangeTimeframe(tf['value']!),
                      );
                    }
                  },
                ),
                const SizedBox(width: 2),
              ],
              const Spacer(),
              // Symbol selector button
              Tooltip(
                message: 'Change Symbol',
                child: InkWell(
                  onTap: () => _showSymbolDialog(context),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz, color: Colors.white54, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Symbol',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSymbolDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => _SymbolSearchDialog(
        onSelected: (value) {
          context.read<TradingRoomBloc>().add(UpdateSymbol(value));
          Navigator.pop(ctx);
        },
      ),
    );
  }

  static String _formatTimeframe(String tf) {
    switch (tf) {
      case '1':
        return 'M1';
      case '5':
        return 'M5';
      case '15':
        return 'M15';
      case '60':
        return 'H1';
      case '240':
        return 'H4';
      case '1440':
        return 'D1';
      case 'D':
        return 'D1';
      case '1D':
        return 'D1';
      case '1W':
        return 'W1';
      default:
        return 'M$tf';
    }
  }
}

// ─── Timeframe Button ───
class _TimeframeButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isEnabled;
  final VoidCallback onTap;

  const _TimeframeButton({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    if (!isEnabled) {
      textColor = Colors.white12;
    } else if (isActive) {
      textColor = AppColors.primary;
    } else {
      textColor = Colors.white38;
    }
    return Opacity(
      opacity: isEnabled ? 1.0 : 0.35,
      child: InkWell(
        onTap: isEnabled ? onTap : null,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isActive && isEnabled
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isActive && isEnabled
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w900 : FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

class _SubTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final bool isSymbolTab;

  const _SubTab({
    required this.label,
    required this.isActive,
    required this.activeColor,
    this.isSymbolTab = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? activeColor.withValues(alpha: 0.08)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isActive ? activeColor : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSymbolTab) ...[
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isActive ? activeColor : Colors.white54,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top Navbar ───
class _WebTopNavbar extends StatelessWidget {
  final VoidCallback? onMenuPressed;
  const _WebTopNavbar({this.onMenuPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF111417),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          if (onMenuPressed != null)
            IconButton(
              onPressed: onMenuPressed,
              icon: const Icon(Icons.menu, color: Colors.white, size: 18),
            ),
          // Logo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.1),
                  AppColors.secondary.withValues(alpha: 0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.hexagon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'PROTRADING AI',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Account Status
          BlocBuilder<TradingRoomBloc, TradingRoomState>(
            builder: (context, state) {
              String status = context.tr('tr_connecting');
              Color statusColor = AppColors.accent;
              if (state is TradingRoomLoaded) {
                status = context.tr('tr_live');
                statusColor = AppColors.primary;
              }
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      status,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const Spacer(),
          // Link API Button
          TextButton.icon(
            onPressed: () => _showSyncDialog(context),
            icon: Icon(Icons.link, size: 16, color: AppColors.primary),
            label: Text(
              context.tr('tr_link_api'),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.notifications_none, color: Colors.white38, size: 18),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () =>
                context.read<AuthBloc>().add(AuthLogoutRequested()),
            icon: const Icon(Icons.logout, color: AppColors.bear, size: 16),
            tooltip: context.tr('tr_logout_tooltip'),
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
            context.tr('tr_link_broker_title'),
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
                context.tr('tr_link_broker_desc'),
                style: const TextStyle(color: AppColors.primary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: context.tr('tr_account_number'),
                  labelStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: context.tr('tr_investor_password'),
                  labelStyle: const TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: context.tr('tr_broker_server'),
                  labelStyle: const TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                context.tr('tr_cancel'),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr('tr_link_sending'))),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: Text(
                context.tr('tr_link_now'),
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

// ─── Resizable Right Panel (Execution + AI Chat) ───
class _ResizableRightPanel extends StatefulWidget {
  const _ResizableRightPanel();

  @override
  State<_ResizableRightPanel> createState() => _ResizableRightPanelState();
}

class _ResizableRightPanelState extends State<_ResizableRightPanel> {
  double _execFraction = 0.60;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalHeight = constraints.maxHeight;
        final execHeight = (totalHeight * _execFraction).clamp(
          totalHeight * 0.30,
          totalHeight * 0.85,
        );
        final chatHeight = totalHeight - execHeight - 6;

        return Column(
          children: [
            SizedBox(height: execHeight, child: const ExecutionPanel()),
            // Drag Handle
            GestureDetector(
              onVerticalDragStart: (_) => setState(() => _isDragging = true),
              onVerticalDragEnd: (_) => setState(() => _isDragging = false),
              onVerticalDragUpdate: (details) {
                setState(() {
                  final delta = details.delta.dy / totalHeight;
                  _execFraction = (_execFraction + delta).clamp(0.30, 0.85);
                });
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 12,
                  color: _isDragging
                      ? AppColors.primary.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.05),
                  child: Center(
                    child: Container(
                      width: 60,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _isDragging
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: chatHeight, child: const AIChatPanel()),
          ],
        );
      },
    );
  }
}

// ─── Symbol Search Dialog ─────────────────────────────────
class _SymbolSearchDialog extends StatefulWidget {
  final ValueChanged<String> onSelected;
  const _SymbolSearchDialog({required this.onSelected});

  @override
  State<_SymbolSearchDialog> createState() => _SymbolSearchDialogState();
}

class _SymbolSearchDialogState extends State<_SymbolSearchDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  List<_Symbol> get _filtered {
    if (_query.isEmpty) return [];
    final q = _query.toUpperCase();
    return _symbolGroups
        .expand((g) => g.symbols)
        .where(
          (s) =>
              s.value.contains(q) ||
              s.label.toUpperCase().contains(q) ||
              s.short.contains(q),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.isNotEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 60),
      child: Container(
        width: 560,
        height: 620,
        decoration: BoxDecoration(
          color: const Color(0xFF131722),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search symbol... (XAUUSD, Gold, BTC)',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v.trim()),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 18,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: isSearching ? _buildSearchResults() : _buildGroupedList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _filtered;
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              color: Colors.white.withValues(alpha: 0.2),
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              'No symbol found for "$_query"',
              style: TextStyle(color: Colors.white38, fontSize: 13),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) => _buildSymbolTile(results[i]),
    );
  }

  Widget _buildGroupedList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _symbolGroups.length,
      itemBuilder: (context, gi) {
        final group = _symbolGroups[gi];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text(
                group.name,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
            ...group.symbols.map((s) => _buildSymbolTile(s)),
            if (gi < _symbolGroups.length - 1)
              Divider(color: Colors.white.withValues(alpha: 0.04), height: 1),
          ],
        );
      },
    );
  }

  Widget _buildSymbolTile(_Symbol s) {
    return InkWell(
      onTap: () => widget.onSelected(s.value),
      hoverColor: AppColors.primary.withValues(alpha: 0.07),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            // Ticker badge
            Container(
              width: 70,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                s.short,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    s.value,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.white.withValues(alpha: 0.15),
              size: 12,
            ),
          ],
        ),
      ),
    );
  }
}
