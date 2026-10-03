import '../../../data/models/journal_models.dart';

enum JournalTradeSide { all, long, short }

enum JournalTradeOutcome { all, profit, loss, flat }

class JournalTradeFilter {
  final String? symbol;
  final JournalTradeSide side;
  final JournalTradeOutcome outcome;

  const JournalTradeFilter({
    this.symbol,
    this.side = JournalTradeSide.all,
    this.outcome = JournalTradeOutcome.all,
  });

  bool get isActive =>
      symbol != null ||
      side != JournalTradeSide.all ||
      outcome != JournalTradeOutcome.all;

  List<TradeRecord> apply(List<TradeRecord> trades) => trades
      .where((trade) {
        if (symbol != null && trade.symbol != symbol) return false;
        if (side == JournalTradeSide.long && trade.action != 'LONG') {
          return false;
        }
        if (side == JournalTradeSide.short && trade.action != 'SHORT') {
          return false;
        }
        if (outcome != JournalTradeOutcome.all && !trade.netProfit.isFinite) {
          return false;
        }
        return switch (outcome) {
          JournalTradeOutcome.all => true,
          JournalTradeOutcome.profit => trade.netProfit > 0,
          JournalTradeOutcome.loss => trade.netProfit < 0,
          JournalTradeOutcome.flat => trade.netProfit == 0,
        };
      })
      .toList(growable: false);
}

/// Closed allowlist for the owner's loaded records; no raw document or UID.
String encodeJournalCsv(List<TradeRecord> trades) {
  final output = StringBuffer();
  const headers = [
    'closeTimeUtc',
    'symbol',
    'action',
    'lotSize',
    'entryPrice',
    'exitPrice',
    'netProfit',
    'executionMode',
    'swap',
    'commission',
    'slippage',
    'metricCurrency',
    'metricSource',
  ];
  // Use explicit CRLF rather than the platform's newline convention.
  output.write('\uFEFF${headers.map(_csvText).join(',')}\r\n');
  for (final trade in trades) {
    final metrics = trade.brokerMetrics;
    final proven =
        metrics != null &&
        metrics.source.trim().isNotEmpty &&
        metrics.currency.trim().isNotEmpty &&
        [
          metrics.swap,
          metrics.commission,
          metrics.slippage,
        ].any((value) => value != null && value.isFinite);
    output.write(
      [
        _csvText(trade.closeTime.toUtc().toIso8601String()),
        _csvText(trade.symbol),
        _csvText(trade.action),
        _csvNumber(trade.lotSize),
        _csvNumber(trade.entryPrice),
        _csvNumber(trade.exitPrice),
        _csvNumber(trade.netProfit),
        _csvText(trade.executionMode ?? ''),
        _csvNumber(proven ? metrics.swap : null),
        _csvNumber(proven ? metrics.commission : null),
        _csvNumber(proven ? metrics.slippage : null),
        _csvText(proven ? metrics.currency : ''),
        _csvText(proven ? metrics.source : ''),
      ].join(','),
    );
    output.write('\r\n');
  }
  return output.toString();
}

String _csvNumber(double? value) =>
    value != null && value.isFinite ? value.toString() : '';

String _csvText(String value) {
  // Spreadsheet-facing CSV: text is never intentionally a formula. Numeric
  // columns are formatted separately, so a genuine negative loss stays numeric.
  final formula = RegExp(r'^[\s\uFEFF]*[=+\-@＝＋－＠]').hasMatch(value);
  final escaped = '${formula ? '\t' : ''}$value'.replaceAll('"', '""');
  return '"$escaped"';
}
