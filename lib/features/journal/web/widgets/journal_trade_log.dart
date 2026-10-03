import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/utils/csv_download.dart';
import '../../../../data/models/journal_models.dart';
import '../journal_trade_export.dart';

class JournalTradeLog extends StatefulWidget {
  final List<TradeRecord> trades;
  final String? scopeId;
  final Future<bool> Function(String csv, String filename)? download;

  const JournalTradeLog({
    super.key,
    required this.trades,
    this.scopeId,
    this.download,
  });

  @override
  State<JournalTradeLog> createState() => _JournalTradeLogState();
}

class _JournalTradeLogState extends State<JournalTradeLog> {
  JournalTradeFilter _filter = const JournalTradeFilter();
  bool _exporting = false;
  String? _feedback;
  int _scopeEpoch = 0;

  @override
  void didUpdateWidget(covariant JournalTradeLog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scopeId != widget.scopeId) {
      _scopeEpoch++;
      _filter = const JournalTradeFilter();
      _exporting = false;
      _feedback = null;
    }
  }

  Future<void> _chooseFilter() async {
    final epoch = _scopeEpoch;
    final symbols = {
      ...widget.trades.map((trade) => trade.symbol),
      if (_filter.symbol != null) _filter.symbol!,
    }.toList()..sort();
    var symbol = _filter.symbol ?? '';
    var side = _filter.side;
    var outcome = _filter.outcome;
    final chosen = await showDialog<JournalTradeFilter>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDraft) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(context.tr('journal_filter')),
          scrollable: true,
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const ValueKey('journal-filter-symbol'),
                  initialValue: symbol,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: context.tr('symbol')),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(context.tr('journal_filter_all')),
                    ),
                    for (final value in symbols.where(
                      (value) => value.isNotEmpty,
                    ))
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => setDraft(() => symbol = value ?? ''),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<JournalTradeSide>(
                  key: const ValueKey('journal-filter-side'),
                  initialValue: side,
                  decoration: InputDecoration(labelText: context.tr('action')),
                  items: [
                    DropdownMenuItem(
                      value: JournalTradeSide.all,
                      child: Text(context.tr('journal_filter_all')),
                    ),
                    const DropdownMenuItem(
                      value: JournalTradeSide.long,
                      child: Text('LONG'),
                    ),
                    const DropdownMenuItem(
                      value: JournalTradeSide.short,
                      child: Text('SHORT'),
                    ),
                  ],
                  onChanged: (value) =>
                      setDraft(() => side = value ?? JournalTradeSide.all),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<JournalTradeOutcome>(
                  key: const ValueKey('journal-filter-outcome'),
                  initialValue: outcome,
                  decoration: InputDecoration(labelText: context.tr('net_pl')),
                  items: [
                    for (final value in JournalTradeOutcome.values)
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          context.tr(switch (value) {
                            JournalTradeOutcome.all => 'journal_filter_all',
                            JournalTradeOutcome.profit =>
                              'journal_heatmap_profit',
                            JournalTradeOutcome.loss => 'journal_heatmap_loss',
                            JournalTradeOutcome.flat => 'journal_filter_flat',
                          }),
                        ),
                      ),
                  ],
                  onChanged: (value) => setDraft(
                    () => outcome = value ?? JournalTradeOutcome.all,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('journal-filter-cancel'),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(context.tr('cancel')),
            ),
            FilledButton(
              key: const ValueKey('journal-filter-apply'),
              onPressed: () => Navigator.pop(
                dialogContext,
                JournalTradeFilter(
                  symbol: symbol.isEmpty ? null : symbol,
                  side: side,
                  outcome: outcome,
                ),
              ),
              child: Text(context.tr('journal_filter_apply')),
            ),
          ],
        ),
      ),
    );
    if (!mounted || epoch != _scopeEpoch || chosen == null) return;
    setState(() {
      _filter = chosen;
      _feedback = null;
    });
  }

  Future<void> _export(List<TradeRecord> visible) async {
    if (_exporting || visible.isEmpty) return;
    final epoch = _scopeEpoch;
    setState(() {
      _exporting = true;
      _feedback = null;
    });
    try {
      final csv = encodeJournalCsv(visible);
      final date = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final queued = await (widget.download ?? downloadJournalCsv)(
        csv,
        'protrading-journal-$date.csv',
      );
      if (!mounted || epoch != _scopeEpoch) return;
      setState(
        () => _feedback = queued ? 'journal_csv_ready' : 'journal_csv_failed',
      );
    } catch (_) {
      if (mounted && epoch == _scopeEpoch) {
        setState(() => _feedback = 'journal_csv_failed');
      }
    } finally {
      if (mounted && epoch == _scopeEpoch) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter.apply(widget.trades);
    final supported = widget.download != null || csvDownloadAvailable;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('journal_trade_log'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Semantics(
                      label: context.tr('journal_rows_shown'),
                      child: Text(
                        '${visible.length} / ${widget.trades.length}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('journal-export-csv'),
                      onPressed: !_exporting && visible.isNotEmpty && supported
                          ? () => _export(visible)
                          : null,
                      icon: const Icon(Icons.download, size: 16),
                      label: Text(context.tr('journal_export_csv')),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('journal-filter'),
                      onPressed: _exporting || widget.trades.isEmpty
                          ? null
                          : _chooseFilter,
                      icon: const Icon(Icons.filter_list, size: 16),
                      label: Text(context.tr('journal_filter')),
                    ),
                    if (_filter.isActive)
                      TextButton(
                        key: const ValueKey('journal-filter-reset'),
                        onPressed: _exporting
                            ? null
                            : () => setState(() {
                                _filter = const JournalTradeFilter();
                                _feedback = null;
                              }),
                        child: Text(context.tr('journal_filter_reset')),
                      ),
                  ],
                ),
                if (!supported || _feedback != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr(_feedback ?? 'journal_csv_unsupported'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                context.tr(
                  widget.trades.isEmpty
                      ? 'journal_no_trades_recorded'
                      : 'journal_no_filtered_trades',
                ),
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _TradeTable(trades: visible),
            ),
        ],
      ),
    );
  }
}

class _TradeTable extends StatelessWidget {
  final List<TradeRecord> trades;
  const _TradeTable({required this.trades});

  @override
  Widget build(BuildContext context) => Table(
    columnWidths: {
      for (var i = 0; i < 10; i++) i: const IntrinsicColumnWidth(),
    },
    children: [
      _row([
        context.tr('symbol'),
        context.tr('action'),
        context.tr('journal_execution_mode'),
        context.tr('size'),
        context.tr('entry'),
        context.tr('exit'),
        context.tr('swap'),
        context.tr('commission'),
        context.tr('slippage'),
        context.tr('net_pl'),
      ], header: true),
      for (final trade in trades)
        _row([
          trade.symbol,
          trade.action,
          context.tr(
            trade.isPaperTrade
                ? 'journal_paper_record'
                : trade.executionMode == 'broker'
                ? 'journal_broker_record'
                : 'journal_mode_unavailable',
          ),
          '${trade.lotSize} ${context.tr('journal_lots')}',
          _price(trade.entryPrice),
          _price(trade.exitPrice),
          _metric(trade.swap, trade),
          _metric(trade.commission, trade),
          _metric(trade.slippage, trade, decimalPlaces: 5),
          '${trade.netProfit >= 0 ? '+' : ''}\$${trade.netProfit.toStringAsFixed(2)}',
        ], positive: trade.netProfit >= 0),
    ],
  );

  String _price(double value) => value.isFinite ? value.toString() : '—';

  String _metric(double? value, TradeRecord trade, {int decimalPlaces = 2}) {
    final source = trade.metricSource;
    final currency = trade.metricCurrency;
    if (value == null ||
        !value.isFinite ||
        source == null ||
        source.trim().isEmpty ||
        currency == null ||
        currency.trim().isEmpty) {
      return '—';
    }
    return '${value.toStringAsFixed(decimalPlaces)} $currency\n$source';
  }

  TableRow _row(List<String> cells, {bool header = false, bool? positive}) =>
      TableRow(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
          ),
        ),
        children: [
          for (final cell in cells)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                cell,
                style: TextStyle(
                  fontSize: header ? 12 : 14,
                  fontWeight: header ? FontWeight.w900 : FontWeight.normal,
                  color: header
                      ? Colors.white38
                      : cell.contains('\$') && positive != null
                      ? positive
                            ? AppColors.primary
                            : AppColors.bear
                      : Colors.white70,
                ),
              ),
            ),
        ],
      );
}
