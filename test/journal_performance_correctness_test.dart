import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/data/repositories/journal_repository.dart';
import 'package:protrading_ai/features/journal/web/journal_trade_export.dart';

void main() {
  TradeRecord trade(double pnl, {DateTime? closed}) => TradeRecord(
    symbol: 'EURUSD',
    action: 'LONG',
    lotSize: 0.1,
    entryPrice: 1.1,
    exitPrice: 1.2,
    netProfit: pnl,
    closeTime: closed ?? DateTime.utc(2026, 10, 4),
    executionMode: 'paper',
  );

  Map<String, dynamic> document() => {
    'symbol': 'EURUSD',
    'action': 'LONG',
    'lotSize': 0.1,
    'entryPrice': 1.1,
    'exitPrice': 1.2,
    'netProfit': 10,
    'closeTime': DateTime.utc(2026, 10, 4, 6),
    'status': 'CLOSED',
  };

  test('unknown trade size remains blank in CSV', () {
    final data = document()..remove('lotSize');
    final record = TradeRecord.fromFirestoreMap(data)!;
    final row = encodeJournalCsv([record]).split('\r\n')[1].split(',');
    expect(record.lotSize, 0);
    expect(row[3], '');
    expect(row[6], '10.0');
  });

  test('all wins never become zero Profit Factor', () {
    final stats = buildJournalStats([trade(10), trade(20)]);
    expect(stats.profitFactor, isNull);
    expect(stats.rrRatio, '—');
  });

  test('break-even is not an average losing trade', () {
    final stats = buildJournalStats([trade(10), trade(-10), trade(0)]);
    expect(stats.profitFactor, 1);
    expect(stats.rrRatio, '1:1.00');
    expect(stats.winRate, closeTo(100 / 3, 0.00001));
  });

  test('all-flat and empty ratios are unavailable', () {
    for (final records in <List<TradeRecord>>[
      [],
      [trade(0), trade(0)],
    ]) {
      final stats = buildJournalStats(records);
      expect(stats.profitFactor, isNull);
      expect(stats.rrRatio, '—');
    }
  });

  test('non-finite or overflowed performance fails without fake zero data', () {
    for (final records in [
      [trade(double.nan)],
      [trade(double.infinity)],
      [trade(1e308), trade(1e308)],
    ]) {
      expect(() => buildJournalStats(records), throwsFormatException);
    }
  });

  test(
    'missing closeTime does not invent a closing date from now/openTime',
    () {
      final data = document()..remove('closeTime');
      data['openTime'] = DateTime.utc(2026, 10, 1);
      expect(TradeRecord.fromFirestoreMap(data), isNull);
    },
  );

  test('missing profit is not a measured break-even', () {
    final data = document()..remove('netProfit');
    expect(TradeRecord.fromFirestoreMap(data), isNull);
  });

  test('malformed numeric values are skipped without throwing', () {
    for (final value in [
      null,
      'bad',
      true,
      <String>[],
      double.nan,
      double.infinity,
    ]) {
      final data = document()..['entryPrice'] = value;
      expect(TradeRecord.fromFirestoreMap(data), isNull);
    }
  });

  test('explicit offset closeTime is parsed exactly', () {
    final data = document()..['closeTime'] = '2026-10-04T06:00:00+07:00';
    expect(
      TradeRecord.fromFirestoreMap(data)?.closeTime,
      DateTime.utc(2026, 10, 3, 23),
    );
  });

  test(
    'sample ratios and win/loss/flat counts use measured nonzero groups',
    () {
      final stats = buildJournalStats([
        trade(20),
        trade(10),
        trade(-10),
        trade(0),
      ]);
      expect(stats.profitFactor, 3);
      expect(stats.payoffRatio, 1.5);
      expect(stats.winningTrades, 2);
      expect(stats.losingTrades, 1);
      expect(stats.breakEvenTrades, 1);
      expect(stats.avgProfit, 5);
      expect(stats.lossConcentration?.totalPnL, -10);
    },
  );

  test(
    'loss-only sample has true zero PF and unavailable average-win ratio',
    () {
      final stats = buildJournalStats([trade(-5), trade(-10), trade(0)]);
      expect(stats.profitFactor, 0);
      expect(stats.payoffRatio, isNull);
      expect(stats.losingTrades, 2);
      expect(stats.breakEvenTrades, 1);
    },
  );

  test('equity sorts a copy chronologically and cannot be mutated', () {
    final newer = trade(-5, closed: DateTime.utc(2026, 10, 4, 10));
    final older = trade(10, closed: DateTime.utc(2026, 10, 3, 10));
    final input = [newer, older];
    final stats = buildJournalStats(input);
    expect(input.first, newer);
    expect(stats.equityData, [10, 5]);
    expect(() => stats.equityData.add(123), throwsUnsupportedError);
  });

  test('ratio overflow stays unavailable despite a real losing sample', () {
    final stats = buildJournalStats([trade(1e300), trade(-1e-300)]);
    expect(stats.profitFactor, isNull);
    expect(stats.payoffRatio, isNull);
    expect(stats.losingTrades, 1);
  });

  test(
    'calendar overflow, missing timezone and invalid size/action are rejected',
    () {
      for (final time in [
        '2026-02-30T06:00:00Z',
        '2026-10-04T24:00:00Z',
        '2026-10-04T06:00:00',
        '2026-10-04T06:00:00+24:00',
        'not-a-date',
      ]) {
        expect(
          TradeRecord.fromFirestoreMap(document()..['closeTime'] = time),
          isNull,
        );
      }
      expect(
        TradeRecord.fromFirestoreMap(document()..['lotSize'] = 'bad'),
        isNull,
      );
      expect(
        TradeRecord.fromFirestoreMap(document()..['action'] = 'unknown'),
        isNull,
      );
    },
  );
}
