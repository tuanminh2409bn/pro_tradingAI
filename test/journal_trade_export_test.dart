import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/core/utils/csv_download.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/features/journal/web/journal_trade_export.dart';

TradeRecord record({
  String symbol = 'EURUSD',
  String action = 'LONG',
  double profit = 20,
  BrokerTradeMetrics? metrics,
}) => TradeRecord(
  symbol: symbol,
  action: action,
  lotSize: 0.15,
  entryPrice: 1.1234567,
  exitPrice: 1.1234568,
  netProfit: profit,
  closeTime: DateTime.parse('2026-10-04T13:00:00+07:00'),
  executionMode: 'paper',
  brokerMetrics: metrics,
);

void main() {
  test('filter intersects fields and never mutates source or order', () {
    final longWin = record();
    final shortLoss = record(action: 'SHORT', profit: -12.34);
    final flat = record(symbol: 'BTCUSD', profit: 0);
    final source = [longWin, shortLoss, flat];
    expect(const JournalTradeFilter().apply(source), source);
    expect(
      const JournalTradeFilter(
        symbol: 'EURUSD',
        side: JournalTradeSide.short,
        outcome: JournalTradeOutcome.loss,
      ).apply(source),
      [shortLoss],
    );
    expect(
      const JournalTradeFilter(outcome: JournalTradeOutcome.flat).apply(source),
      [flat],
    );
    expect(
      const JournalTradeFilter(
        outcome: JournalTradeOutcome.profit,
      ).apply(source),
      [longWin],
    );
    expect(const JournalTradeFilter(symbol: 'XAUUSD').apply(source), isEmpty);
    expect(source, [longWin, shortLoss, flat]);
    expect(const JournalTradeFilter().isActive, isFalse);
    expect(
      const JournalTradeFilter(side: JournalTradeSide.long).isActive,
      isTrue,
    );
  });

  test('CSV preserves UTC, precision, negative values and absent metrics', () {
    final csv = encodeJournalCsv([record(profit: -12.34)]);
    final lines = csv.substring(1).split('\r\n');
    expect(csv.startsWith('\uFEFF'), isTrue);
    expect(lines.length, 3);
    expect(lines[0], contains('closeTimeUtc'));
    expect(lines[1], contains('2026-10-04T06:00:00.000Z'));
    expect(lines[1], contains(',1.1234567,1.1234568,-12.34'));
    expect(lines[1], endsWith(',"paper",,,,"",""'));
    expect(csv, isNot(contains('userId')));
    expect(csv, isNot(contains('token')));
  });

  test('CSV quotes provenance without converting missing fees into zero', () {
    final csv = encodeJournalCsv([
      record(
        metrics: const BrokerTradeMetrics(
          swap: -1.25,
          commission: 0,
          slippage: null,
          source: 'deal,"history"\nverified',
          currency: 'USD',
        ),
      ),
    ]);
    expect(csv, contains('-1.25,0.0,,"USD","deal,""history""\nverified"'));
  });

  test(
    'spreadsheet formulas in text are inert without altering numeric losses',
    () {
      for (final text in [
        '=1+2',
        '+1+2',
        '-1+2',
        '@SUM(A1)',
        '  =1',
        '＝1',
        '＋1',
        '－1',
        '＠A1',
        '\t=1',
        '\r\n=1',
      ]) {
        final csv = encodeJournalCsv([record(symbol: text, profit: -12.34)]);
        expect(csv, contains('"\t$text"'));
        expect(csv, contains(',-12.34,"paper"'));
      }
    },
  );

  test('non-finite measurements and unproven broker metadata stay absent', () {
    expect(
      const JournalTradeFilter(
        outcome: JournalTradeOutcome.profit,
      ).apply([record(profit: double.infinity)]),
      isEmpty,
    );
    final csv = encodeJournalCsv([
      record(
        profit: double.nan,
        metrics: const BrokerTradeMetrics(
          swap: double.infinity,
          commission: 0,
          slippage: 0,
          source: '',
          currency: 'USD',
        ),
      ),
    ]);
    expect(csv, isNot(contains('NaN')));
    expect(csv, isNot(contains('Infinity')));
    expect(csv, isNot(contains('"USD"')));
    expect(csv, isNot(contains(',0.0,0.0,')));
  });

  test(
    'download rejects paths, non-CSV data and UTF-8 payloads above limit',
    () {
      final csv = encodeJournalCsv([record()]);
      const filename = 'protrading-journal-2026-10-04.csv';
      expect(validJournalCsvDownload(csv, filename), isTrue);
      expect(validJournalCsvDownload(csv, '../$filename'), isFalse);
      expect(validJournalCsvDownload(csv, '$filename\n'), isFalse);
      expect(validJournalCsvDownload(csv, 'history.html'), isFalse);
      expect(
        validJournalCsvDownload('<script>bad</script>\r\n', filename),
        isFalse,
      );
      expect(
        validJournalCsvDownload(
          '\uFEFF"closeTimeUtc",${'ế' * (4 * 1024 * 1024)}\r\n',
          filename,
        ),
        isFalse,
      );
    },
  );
}
