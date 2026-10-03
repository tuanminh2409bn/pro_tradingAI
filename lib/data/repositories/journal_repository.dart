import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/journal_models.dart';

class JournalRepository {
  final FirebaseFirestore _firestore;

  JournalRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Stream<List<TradeRecord>> getTradeHistory(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('trades')
        .orderBy('closeTime', descending: true)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return <TradeRecord>[];
          }
          return snapshot.docs
              .map((doc) => TradeRecord.fromFirestoreMap(doc.data()))
              .whereType<TradeRecord>()
              .toList()
            ..sort((left, right) => right.closeTime.compareTo(left.closeTime));
        });
  }

  Stream<JournalStats> getJournalStats(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('trades')
        .snapshots()
        .map((snapshot) {
          final trades =
              snapshot.docs
                  .map((doc) => TradeRecord.fromFirestoreMap(doc.data()))
                  .whereType<TradeRecord>()
                  .toList()
                ..sort((a, b) => a.closeTime.compareTo(b.closeTime));

          return buildJournalStats(trades);
        });
  }
}

/// Uses one immutable owner snapshot; no network, LLM or invented risk scores.
JournalStats buildJournalStats(List<TradeRecord> source) {
  final trades = List<TradeRecord>.of(source)
    ..sort((left, right) => left.closeTime.compareTo(right.closeTime));
  if (trades.any((trade) => !trade.netProfit.isFinite)) {
    throw const FormatException('Journal performance is not finite.');
  }
  if (trades.isEmpty) {
    return const JournalStats(
      totalProfit: 0.0,
      winRate: 0.0,
      profitFactor: null,
      rrRatio: '—',
      equityData: [],
      totalTrades: 0,
      bestTrade: 0.0,
      worstTrade: 0.0,
      avgProfit: 0.0,
      aiInsight: '__NO_TRADES__',
      heatmapData: [],
    );
  }

  final totalTrades = trades.length;
  final winningTrades = trades.where((t) => t.netProfit > 0).toList();
  final losingTrades = trades.where((t) => t.netProfit < 0).toList();

  // Win Rate
  final winRate = (winningTrades.length / totalTrades) * 100;

  // Total Profit
  final totalProfit = trades.fold<double>(
    0.0,
    (total, trade) => total + trade.netProfit,
  );

  // Average Profit
  final avgProfit = totalProfit / totalTrades;

  // Best & Worst Trade
  final bestTrade = trades
      .map((t) => t.netProfit)
      .reduce((a, b) => a > b ? a : b);
  final worstTrade = trades
      .map((t) => t.netProfit)
      .reduce((a, b) => a < b ? a : b);

  // Profit Factor = gross profit / gross loss
  final grossProfit = winningTrades.fold<double>(
    0.0,
    (total, trade) => total + trade.netProfit,
  );
  final grossLoss = losingTrades.fold<double>(
    0.0,
    (total, trade) => total + trade.netProfit.abs(),
  );
  if (!totalProfit.isFinite || !grossProfit.isFinite || !grossLoss.isFinite) {
    throw const FormatException('Journal performance overflowed.');
  }
  final rawProfitFactor = grossLoss > 0 ? grossProfit / grossLoss : null;
  final profitFactor = rawProfitFactor?.isFinite == true
      ? rawProfitFactor
      : null;

  // Average R:R Ratio
  final avgWin = winningTrades.isNotEmpty
      ? winningTrades.fold<double>(
              0.0,
              (total, trade) => total + trade.netProfit,
            ) /
            winningTrades.length
      : 0.0;
  final avgLoss = losingTrades.isNotEmpty
      ? losingTrades.fold<double>(
              0.0,
              (total, trade) => total + trade.netProfit.abs(),
            ) /
            losingTrades.length
      : 0.0;
  final rawPayoff = avgWin > 0 && avgLoss > 0 ? avgWin / avgLoss : null;
  final payoffRatio = rawPayoff?.isFinite == true ? rawPayoff : null;
  final rrRatio = payoffRatio != null
      ? '1:${payoffRatio.toStringAsFixed(2)}'
      : '—';

  // Equity Curve (cumulative P&L from chronological trades)
  final equityData = <double>[];
  double cumulative = 0.0;
  for (final trade in trades) {
    cumulative += trade.netProfit;
    if (!cumulative.isFinite) {
      throw const FormatException('Journal performance overflowed.');
    }
    equityData.add(cumulative);
  }

  // Heatmap: group by dayOfWeek x hour
  final heatmapMap = <String, HeatmapEntry>{};
  for (final trade in trades) {
    final day = trade.closeTime.weekday; // 1=Mon, 7=Sun
    final hour = trade.closeTime.hour;
    final key = '$day-$hour';
    if (heatmapMap.containsKey(key)) {
      final existing = heatmapMap[key]!;
      heatmapMap[key] = HeatmapEntry(
        dayOfWeek: day,
        hourSlot: hour,
        totalPnL: existing.totalPnL + trade.netProfit,
        tradeCount: existing.tradeCount + 1,
      );
    } else {
      heatmapMap[key] = HeatmapEntry(
        dayOfWeek: day,
        hourSlot: hour,
        totalPnL: trade.netProfit,
        tradeCount: 1,
      );
    }
  }

  // AI Insight generation from real data
  final aiInsight = buildJournalInsight(
    totalTrades: totalTrades,
    winRate: winRate,
    totalProfit: totalProfit,
    bestTrade: bestTrade,
    worstTrade: worstTrade,
    profitFactor: profitFactor,
    trades: trades,
  );

  return JournalStats(
    totalProfit: totalProfit,
    winRate: winRate,
    profitFactor: profitFactor,
    rrRatio: rrRatio,
    payoffRatio: payoffRatio,
    winningTrades: winningTrades.length,
    losingTrades: losingTrades.length,
    breakEvenTrades: totalTrades - winningTrades.length - losingTrades.length,
    lossConcentration: _journalLossConcentration(trades),
    equityData: List.unmodifiable(equityData),
    totalTrades: totalTrades,
    bestTrade: bestTrade,
    worstTrade: worstTrade,
    avgProfit: avgProfit,
    aiInsight: aiInsight,
    heatmapData: heatmapMap.values.toList(),
  );
}

/// Web heatmap uses the same UTC clock as the behavioral insight. The source
/// list stays owner-scoped at the repository boundary; this helper performs no I/O.
List<HeatmapEntry> buildJournalHeatmap(List<TradeRecord> trades) {
  final grouped = <String, HeatmapEntry>{};
  for (final trade in trades) {
    if (!trade.netProfit.isFinite) continue;
    final closed = trade.closeTime.toUtc();
    final key = '${closed.weekday}-${closed.hour}';
    final previous = grouped[key];
    grouped[key] = HeatmapEntry(
      dayOfWeek: closed.weekday,
      hourSlot: closed.hour,
      totalPnL: (previous?.totalPnL ?? 0) + trade.netProfit,
      tradeCount: (previous?.tradeCount ?? 0) + 1,
    );
  }
  return grouped.values.where((entry) => entry.totalPnL.isFinite).toList();
}

String buildJournalInsight({
  required int totalTrades,
  required double winRate,
  required double totalProfit,
  required double bestTrade,
  required double worstTrade,
  required double? profitFactor,
  required List<TradeRecord> trades,
}) {
  final buffer = StringBuffer();

  if (!totalProfit.isFinite ||
      !winRate.isFinite ||
      !bestTrade.isFinite ||
      !worstTrade.isFinite) {
    throw const FormatException('Journal performance is not finite.');
  }
  // Legacy English formatter. Web renders its localized structured summary.
  buffer.write(
    '$totalTrades measured closed trades; recorded net P&L '
    '${totalProfit.toStringAsFixed(2)}; win rate ${winRate.toStringAsFixed(1)}%. ',
  );

  // Recent trend (last 7 trades)
  if (trades.length >= 7) {
    final recentTrades = trades.sublist(trades.length - 7);
    final recentWins = recentTrades.where((t) => t.netProfit > 0).length;
    final recentWinRate = (recentWins / 7) * 100;
    final diff = recentWinRate - winRate;
    buffer.write(
      'Recent 7 trades win rate ${recentWinRate.toStringAsFixed(1)}%; '
      'difference ${diff.toStringAsFixed(1)} percentage points. ',
    );
  }

  final worst = _journalLossConcentration(trades);
  if (worst != null) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final hour = worst.hourSlot.toString().padLeft(2, '0');
    final tradeLabel = worst.tradeCount == 1 ? 'trade' : 'trades';
    buffer.write(
      'Measured loss concentration: ${weekdays[worst.dayOfWeek - 1]} '
      '$hour:00 UTC, ${worst.tradeCount} measured losing $tradeLabel, '
      '${worst.totalPnL.toStringAsFixed(2)} net P&L. ',
    );
  }

  // Profit factor
  if (profitFactor != null && profitFactor.isFinite) {
    buffer.write('Recorded profit factor ${profitFactor.toStringAsFixed(2)}.');
  }

  return buffer.toString();
}

HeatmapEntry? _journalLossConcentration(List<TradeRecord> trades) {
  final grouped = <(int, int), HeatmapEntry>{};
  for (final trade in trades) {
    if (!trade.netProfit.isFinite || trade.netProfit >= 0) continue;
    final closed = trade.closeTime.toUtc();
    final key = (closed.weekday, closed.hour);
    final previous = grouped[key];
    final pnl = (previous?.totalPnL ?? 0) + trade.netProfit;
    if (!pnl.isFinite) {
      throw const FormatException('Journal performance overflowed.');
    }
    grouped[key] = HeatmapEntry(
      dayOfWeek: closed.weekday,
      hourSlot: closed.hour,
      totalPnL: pnl,
      tradeCount: (previous?.tradeCount ?? 0) + 1,
    );
  }
  if (grouped.isEmpty) return null;
  final slots = grouped.values.toList()
    ..sort((left, right) {
      final byLoss = left.totalPnL.compareTo(right.totalPnL);
      if (byLoss != 0) return byLoss;
      final byDay = left.dayOfWeek.compareTo(right.dayOfWeek);
      return byDay != 0 ? byDay : left.hourSlot.compareTo(right.hourSlot);
    });
  return slots.first;
}
