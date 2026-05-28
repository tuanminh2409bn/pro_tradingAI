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
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return TradeRecord(
          symbol: data['symbol'] ?? '',
          action: data['action'] ?? 'LONG',
          lotSize: (data['lotSize'] ?? 0).toDouble(),
          entryPrice: (data['entryPrice'] ?? 0).toDouble(),
          exitPrice: (data['exitPrice'] ?? 0).toDouble(),
          netProfit: (data['netProfit'] ?? 0).toDouble(),
          closeTime: (data['closeTime'] as Timestamp).toDate(),
          swap: (data['swap'] ?? 0).toDouble(),
          slippage: (data['slippage'] ?? 0).toDouble(),
        );
      }).toList();
    });
  }

  Stream<JournalStats> getJournalStats(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('trades')
        .orderBy('closeTime', descending: false)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        return const JournalStats(
          totalProfit: 0.0,
          winRate: 0.0,
          profitFactor: 0.0,
          rrRatio: '0:0',
          equityData: [],
          totalTrades: 0,
          bestTrade: 0.0,
          worstTrade: 0.0,
          avgProfit: 0.0,
          aiInsight: 'No trades recorded yet. Start trading to see AI performance insights.',
          heatmapData: [],
        );
      }

      final trades = snapshot.docs.map((doc) {
        final data = doc.data();
        return TradeRecord(
          symbol: data['symbol'] ?? '',
          action: data['action'] ?? 'LONG',
          lotSize: (data['lotSize'] ?? 0).toDouble(),
          entryPrice: (data['entryPrice'] ?? 0).toDouble(),
          exitPrice: (data['exitPrice'] ?? 0).toDouble(),
          netProfit: (data['netProfit'] ?? 0).toDouble(),
          closeTime: (data['closeTime'] as Timestamp).toDate(),
          swap: (data['swap'] ?? 0).toDouble(),
          slippage: (data['slippage'] ?? 0).toDouble(),
        );
      }).toList();

      return _computeStats(trades);
    });
  }

  JournalStats _computeStats(List<TradeRecord> trades) {
    if (trades.isEmpty) {
      return const JournalStats(
        totalProfit: 0.0,
        winRate: 0.0,
        profitFactor: 0.0,
        rrRatio: '0:0',
        equityData: [],
        totalTrades: 0,
        bestTrade: 0.0,
        worstTrade: 0.0,
        avgProfit: 0.0,
        aiInsight: 'No trades recorded yet. Start trading to see AI performance insights.',
        heatmapData: [],
      );
    }

    final totalTrades = trades.length;
    final winningTrades = trades.where((t) => t.netProfit > 0).toList();
    final losingTrades = trades.where((t) => t.netProfit <= 0).toList();

    // Win Rate
    final winRate = (winningTrades.length / totalTrades) * 100;

    // Total Profit
    final totalProfit = trades.fold<double>(0.0, (sum, t) => sum + t.netProfit);

    // Average Profit
    final avgProfit = totalProfit / totalTrades;

    // Best & Worst Trade
    final bestTrade = trades.map((t) => t.netProfit).reduce((a, b) => a > b ? a : b);
    final worstTrade = trades.map((t) => t.netProfit).reduce((a, b) => a < b ? a : b);

    // Profit Factor = gross profit / gross loss
    final grossProfit = winningTrades.fold<double>(0.0, (sum, t) => sum + t.netProfit);
    final grossLoss = losingTrades.fold<double>(0.0, (sum, t) => sum + t.netProfit.abs());
    final profitFactor = grossLoss > 0 ? grossProfit / grossLoss : grossProfit > 0 ? double.infinity : 0.0;

    // Average R:R Ratio
    final avgWin = winningTrades.isNotEmpty
        ? winningTrades.fold<double>(0.0, (sum, t) => sum + t.netProfit) / winningTrades.length
        : 0.0;
    final avgLoss = losingTrades.isNotEmpty
        ? losingTrades.fold<double>(0.0, (sum, t) => sum + t.netProfit.abs()) / losingTrades.length
        : 0.0;
    final rrRatio = avgLoss > 0 ? '1:${(avgWin / avgLoss).toStringAsFixed(2)}' : '1:0.00';

    // Equity Curve (cumulative P&L from chronological trades)
    final equityData = <double>[];
    double cumulative = 0.0;
    for (final trade in trades) {
      cumulative += trade.netProfit;
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
    final aiInsight = _generateAIInsight(
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
      profitFactor: profitFactor.isFinite ? profitFactor : 0.0,
      rrRatio: rrRatio,
      equityData: equityData,
      totalTrades: totalTrades,
      bestTrade: bestTrade,
      worstTrade: worstTrade,
      avgProfit: avgProfit,
      aiInsight: aiInsight,
      heatmapData: heatmapMap.values.toList(),
    );
  }

  String _generateAIInsight({
    required int totalTrades,
    required double winRate,
    required double totalProfit,
    required double bestTrade,
    required double worstTrade,
    required double profitFactor,
    required List<TradeRecord> trades,
  }) {
    final buffer = StringBuffer();

    // Performance summary
    if (totalProfit > 0) {
      buffer.write('Strong performance with \$${totalProfit.toStringAsFixed(2)} total profit across $totalTrades trades. ');
    } else {
      buffer.write('Portfolio is down \$${totalProfit.abs().toStringAsFixed(2)} across $totalTrades trades. Focus on risk management. ');
    }

    // Win rate insight
    if (winRate >= 60) {
      buffer.write('Your ${winRate.toStringAsFixed(1)}% win rate is excellent — maintain your edge. ');
    } else if (winRate >= 45) {
      buffer.write('Win rate at ${winRate.toStringAsFixed(1)}% is acceptable but can be improved with better entries. ');
    } else {
      buffer.write('Win rate of ${winRate.toStringAsFixed(1)}% is below average — consider reviewing your entry criteria. ');
    }

    // Recent trend (last 7 trades)
    if (trades.length >= 7) {
      final recentTrades = trades.sublist(trades.length - 7);
      final recentWins = recentTrades.where((t) => t.netProfit > 0).length;
      final recentWinRate = (recentWins / 7) * 100;
      final diff = recentWinRate - winRate;
      if (diff > 5) {
        buffer.write('Your win rate improved by ${diff.toStringAsFixed(1)}% in the last 7 trades — momentum is building. ');
      } else if (diff < -5) {
        buffer.write('Recent 7 trades show a ${diff.abs().toStringAsFixed(1)}% drop in win rate — consider taking a break. ');
      }
    }

    // Profit factor
    if (profitFactor.isFinite && profitFactor > 2.0) {
      buffer.write('Profit factor of ${profitFactor.toStringAsFixed(2)} indicates a robust strategy.');
    } else if (profitFactor.isFinite && profitFactor < 1.0) {
      buffer.write('Profit factor below 1.0 — losses are exceeding gains. Tighten stop losses.');
    }

    return buffer.toString();
  }
}
