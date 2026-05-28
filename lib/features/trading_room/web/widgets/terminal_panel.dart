import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../data/models/trading_models.dart';
import '../../bloc/trading_room_bloc.dart';
import '../../bloc/trading_room_event.dart';
import '../../bloc/trading_room_state.dart';

class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key});

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TradingRoomBloc, TradingRoomState>(
      builder: (context, state) {
        if (state is! TradingRoomLoaded) {
          return const SizedBox(height: 200);
        }

        final openPositions =
            state.positions.where((p) => p.status == 'OPEN').toList();
        final closedPositions =
            state.positions.where((p) => p.status == 'CLOSED').toList();

        return Container(
          height: 200,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.9),
            border: Border(
              top: BorderSide(color: AppColors.primary.withValues(alpha: 0.15)),
            ),
          ),
          child: Column(
            children: [
              // ── Tab Bar ──
              _buildTabBar(context),
              // ── Tab Content ──
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTradeTab(context, openPositions),
                    _buildExposureTab(context, openPositions),
                    _buildHistoryTab(context, closedPositions),
                  ],
                ),
              ),
              // ── Footer ──
              _buildFooter(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(BuildContext context) {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primary,
        unselectedLabelColor: Colors.white38,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        indicatorWeight: 2,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.2,
        ),
        tabs: [
          Tab(text: context.tr('terminal_tab_trade')),
          Tab(text: context.tr('terminal_tab_exposure')),
          Tab(text: context.tr('terminal_tab_history')),
        ],
      ),
    );
  }

  Widget _buildTradeTab(BuildContext context, List<Position> positions) {
    if (positions.isEmpty) {
      return Center(
        child: Text(
          context.tr('terminal_no_positions'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 28,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          columnSpacing: 16,
          horizontalMargin: 12,
          headingTextStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
          dataTextStyle: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontFamily: 'monospace',
          ),
          columns: [
            DataColumn(label: Text(context.tr('terminal_col_order'))),
            DataColumn(label: Text(context.tr('terminal_col_time'))),
            DataColumn(label: Text(context.tr('terminal_col_type'))),
            DataColumn(label: Text(context.tr('terminal_col_size'))),
            DataColumn(label: Text(context.tr('terminal_col_symbol'))),
            DataColumn(label: Text(context.tr('terminal_col_price'))),
            DataColumn(label: Text(context.tr('terminal_col_sl'))),
            DataColumn(label: Text(context.tr('terminal_col_tp'))),
            DataColumn(label: Text(context.tr('terminal_col_profit'))),
            DataColumn(label: Text(context.tr('terminal_col_action'))),
          ],
          rows: positions.map((p) => _buildTradeRow(context, p)).toList(),
        ),
      ),
    );
  }

  DataRow _buildTradeRow(BuildContext context, Position position) {
    final isBuy = position.type == 'BUY';
    final profitColor = position.profit >= 0 ? AppColors.bull : AppColors.bear;
    final typeColor = isBuy ? AppColors.bull : AppColors.bear;
    final timeStr = position.openTime != null
        ? '${position.openTime!.hour.toString().padLeft(2, '0')}:${position.openTime!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return DataRow(
      cells: [
        DataCell(Text('#${position.id.substring(0, 6).toUpperCase()}')),
        DataCell(Text(timeStr)),
        DataCell(Text(
          position.type,
          style: TextStyle(color: typeColor, fontWeight: FontWeight.w700),
        )),
        DataCell(Text(position.lotSize.toStringAsFixed(2))),
        DataCell(Text(position.symbol)),
        DataCell(Text(position.openPrice.toStringAsFixed(5))),
        DataCell(Text(
          position.sl > 0 ? position.sl.toStringAsFixed(5) : '---',
          style: const TextStyle(color: AppColors.bear),
        )),
        DataCell(Text(
          position.tp > 0 ? position.tp.toStringAsFixed(5) : '---',
          style: const TextStyle(color: AppColors.tp),
        )),
        DataCell(Text(
          '${position.profit >= 0 ? '+' : ''}\$${position.profit.toStringAsFixed(2)}',
          style: TextStyle(color: profitColor, fontWeight: FontWeight.w700),
        )),
        DataCell(
          _buildCloseButton(context, position.id),
        ),
      ],
    );
  }

  Widget _buildCloseButton(BuildContext context, String positionId) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          context.read<TradingRoomBloc>().add(ClosePosition(positionId));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.bear.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.bear.withValues(alpha: 0.4)),
          ),
          child: Text(
            context.tr('terminal_close_btn'),
            style: const TextStyle(
              color: AppColors.bear,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExposureTab(BuildContext context, List<Position> positions) {
    if (positions.isEmpty) {
      return Center(
        child: Text(
          context.tr('terminal_no_exposure'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
        ),
      );
    }

    // Group by symbol
    final Map<String, _ExposureSummary> exposure = {};
    for (final p in positions) {
      final key = p.symbol;
      if (!exposure.containsKey(key)) {
        exposure[key] = _ExposureSummary();
      }
      final e = exposure[key]!;
      if (p.type == 'BUY') {
        e.longLots += p.lotSize;
        e.longCount++;
      } else {
        e.shortLots += p.lotSize;
        e.shortCount++;
      }
      e.totalPnL += p.profit;
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: exposure.entries.map((entry) {
            final sym = entry.key;
            final e = entry.value;
            final netLots = e.longLots - e.shortLots;
            final pnlColor = e.totalPnL >= 0 ? AppColors.bull : AppColors.bear;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
              ),
              child: Row(
                children: [
                  // Symbol
                  SizedBox(
                    width: 80,
                    child: Text(
                      sym,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  // Long
                  _exposureCell(
                      context.tr('terminal_long'),
                      '${e.longCount}x ${e.longLots.toStringAsFixed(2)}',
                      AppColors.bull),
                  const SizedBox(width: 16),
                  // Short
                  _exposureCell(
                      context.tr('terminal_short'),
                      '${e.shortCount}x ${e.shortLots.toStringAsFixed(2)}',
                      AppColors.bear),
                  const SizedBox(width: 16),
                  // Net
                  _exposureCell(
                      context.tr('terminal_net'),
                      '${netLots >= 0 ? '+' : ''}${netLots.toStringAsFixed(2)}',
                      netLots >= 0 ? AppColors.bull : AppColors.bear),
                  const Spacer(),
                  // PnL
                  Text(
                    '${e.totalPnL >= 0 ? '+' : ''}\$${e.totalPnL.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: pnlColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _exposureCell(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                color: color, fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildHistoryTab(BuildContext context, List<Position> closedPositions) {
    if (closedPositions.isEmpty) {
      return Center(
        child: Text(
          context.tr('terminal_no_history'),
          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 14),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowHeight: 28,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          columnSpacing: 16,
          horizontalMargin: 12,
          headingTextStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
          dataTextStyle: const TextStyle(
            color: Colors.white54,
            fontSize: 14,
            fontFamily: 'monospace',
          ),
          columns: [
            DataColumn(label: Text(context.tr('terminal_col_order'))),
            DataColumn(label: Text(context.tr('terminal_col_symbol'))),
            DataColumn(label: Text(context.tr('terminal_col_type'))),
            DataColumn(label: Text(context.tr('terminal_col_size'))),
            DataColumn(label: Text(context.tr('terminal_col_open'))),
            DataColumn(label: Text(context.tr('terminal_col_close'))),
            DataColumn(label: Text(context.tr('terminal_col_profit'))),
          ],
          rows: closedPositions.map((p) {
            final profitColor =
                p.profit >= 0 ? AppColors.bull : AppColors.bear;
            return DataRow(cells: [
              DataCell(Text('#${p.id.substring(0, 6).toUpperCase()}')),
              DataCell(Text(p.symbol)),
              DataCell(Text(p.type,
                  style: TextStyle(
                      color: p.type == 'BUY' ? AppColors.bull : AppColors.bear,
                      fontWeight: FontWeight.w600))),
              DataCell(Text(p.lotSize.toStringAsFixed(2))),
              DataCell(Text(p.openPrice.toStringAsFixed(5))),
              DataCell(Text(p.currentPrice.toStringAsFixed(5))),
              DataCell(Text(
                '${p.profit >= 0 ? '+' : ''}\$${p.profit.toStringAsFixed(2)}',
                style: TextStyle(
                    color: profitColor, fontWeight: FontWeight.w700),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context, TradingRoomLoaded state) {
    final totalPnL = state.totalPnL;
    final pnlColor = totalPnL >= 0 ? AppColors.bull : AppColors.bear;
    final count = state.positions.where((p) => p.status == 'OPEN').length;

    final balance = state.riskConfig?.balance ?? state.account.balance;
    final equity = state.account.equity > 0 ? state.account.equity : balance;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: Row(
        children: [
          _footerItem(context.tr('terminal_balance'),
              '\$${balance.toStringAsFixed(2)}', Colors.white70),
          const SizedBox(width: 24),
          _footerItem(context.tr('terminal_equity'),
              '\$${equity.toStringAsFixed(2)}', AppColors.accent),
          const SizedBox(width: 24),
          _footerItem(
            context.tr('terminal_total_pnl'),
            '${totalPnL >= 0 ? '+' : ''}\$${totalPnL.toStringAsFixed(2)}',
            pnlColor,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count ${context.tr("terminal_open_label")}',
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerItem(String label, String value, Color valueColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}

// Helper class for exposure grouping
class _ExposureSummary {
  int longCount = 0;
  int shortCount = 0;
  double longLots = 0;
  double shortLots = 0;
  double totalPnL = 0;
}
