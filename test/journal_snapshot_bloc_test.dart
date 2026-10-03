import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/journal_models.dart';
import 'package:protrading_ai/data/repositories/journal_repository.dart';
import 'package:protrading_ai/features/journal/bloc/journal_bloc.dart';
import 'package:protrading_ai/features/journal/bloc/journal_event.dart';
import 'package:protrading_ai/features/journal/bloc/journal_state.dart';

TradeRecord _trade(double pnl) => TradeRecord(
  symbol: 'EURUSD',
  action: 'LONG',
  lotSize: 0.1,
  entryPrice: 1.1,
  exitPrice: 1.2,
  netProfit: pnl,
  closeTime: DateTime.utc(2026, 10, 4),
  executionMode: 'paper',
);

class _SnapshotRepository implements JournalRepository {
  final histories = <String, StreamController<List<TradeRecord>>>{};
  var statsReads = 0;

  @override
  Stream<List<TradeRecord>> getTradeHistory(String userId) => histories
      .putIfAbsent(userId, () => StreamController.broadcast(sync: true))
      .stream;

  @override
  Stream<JournalStats> getJournalStats(String userId) {
    statsReads++;
    return Stream.value(buildJournalStats([_trade(999)]));
  }

  Future<void> dispose() async {
    for (final controller in histories.values) {
      await controller.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Future<void> _drain() async {
  for (var turn = 0; turn < 3; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('table and stats are atomic from one owner history snapshot', () async {
    final repo = _SnapshotRepository();
    final bloc = JournalBloc(journalRepository: repo);
    try {
      bloc.add(const LoadJournalData(userId: 'owner-one'));
      await _drain();
      final records = [_trade(42)];
      repo.histories['owner-one']!.add(records);
      await _drain();
      final loaded = bloc.state as JournalLoaded;
      expect(loaded.trades.single.netProfit, 42);
      expect(loaded.stats.totalProfit, 42);
      expect(loaded.stats.totalTrades, loaded.trades.length);
      expect(repo.statsReads, 0);
      records.clear();
      expect(loaded.trades.length, 1);
    } finally {
      await bloc.close();
      await repo.dispose();
    }
  });

  test(
    'waits for data and does not present a fabricated empty snapshot',
    () async {
      final repo = _SnapshotRepository();
      final bloc = JournalBloc(journalRepository: repo);
      try {
        bloc.add(const LoadJournalData(userId: 'owner-one'));
        await _drain();
        expect(bloc.state, isA<JournalLoading>());
        repo.histories['owner-one']!.add([]);
        await _drain();
        final loaded = bloc.state as JournalLoaded;
        expect(loaded.stats.totalTrades, 0);
        expect(loaded.stats.profitFactor, isNull);
        expect(repo.statsReads, 0);
      } finally {
        await bloc.close();
        await repo.dispose();
      }
    },
  );

  test(
    'queued data/error from previous owner cannot replace current snapshot',
    () async {
      final repo = _SnapshotRepository();
      final bloc = JournalBloc(journalRepository: repo);
      try {
        bloc.add(const LoadJournalData(userId: 'owner-one'));
        await _drain();
        repo.histories['owner-one']!.add([_trade(11)]);
        await _drain();
        bloc.add(const LoadJournalData(userId: 'owner-two'));
        await _drain();
        expect(repo.histories['owner-one']!.hasListener, isFalse);
        expect(bloc.state, isA<JournalLoading>());
        repo.histories['owner-two']!.add([_trade(22)]);
        await _drain();
        bloc.add(UpdateTradeHistory([_trade(111)], generation: 1));
        bloc.add(const JournalStreamFailed(1));
        await _drain();
        final loaded = bloc.state as JournalLoaded;
        expect(loaded.trades.single.netProfit, 22);
        expect(loaded.stats.totalProfit, 22);
      } finally {
        await bloc.close();
        await repo.dispose();
      }
    },
  );

  test(
    'reload of the same owner rejects results from the earlier request',
    () async {
      final repo = _SnapshotRepository();
      final bloc = JournalBloc(journalRepository: repo);
      try {
        bloc.add(const LoadJournalData(userId: 'owner-one'));
        await _drain();
        bloc.add(const LoadJournalData(userId: 'owner-one'));
        await _drain();
        bloc.add(UpdateTradeHistory([_trade(-111)], generation: 1));
        await _drain();
        expect(bloc.state, isA<JournalLoading>());
        repo.histories['owner-one']!.add([_trade(33)]);
        await _drain();
        expect((bloc.state as JournalLoaded).stats.totalProfit, 33);
      } finally {
        await bloc.close();
        await repo.dispose();
      }
    },
  );

  test(
    'stream and invalid-performance failures recover without sensitive errors or fake data',
    () async {
      final repo = _SnapshotRepository();
      final bloc = JournalBloc(journalRepository: repo);
      try {
        bloc.add(const LoadJournalData(userId: 'owner-one'));
        await _drain();
        final source = repo.histories['owner-one']!;
        source.addError(StateError('private-provider-details'));
        await _drain();
        expect((bloc.state as JournalError).message, 'common_data_unavailable');
        source.add([_trade(double.nan)]);
        await _drain();
        expect(bloc.state, isA<JournalError>());
        source.add([_trade(7)]);
        await _drain();
        expect((bloc.state as JournalLoaded).stats.totalProfit, 7);
        await bloc.close();
        expect(source.hasListener, isFalse);
        source.add([_trade(999)]);
        await _drain();
        expect((bloc.state as JournalLoaded).stats.totalProfit, 7);
      } finally {
        if (!bloc.isClosed) await bloc.close();
        await repo.dispose();
      }
    },
  );

  test('anonymous owner does not query repositories', () async {
    final repo = _SnapshotRepository();
    final bloc = JournalBloc(journalRepository: repo);
    try {
      bloc.add(const LoadJournalData());
      await _drain();
      expect((bloc.state as JournalLoaded).trades, isEmpty);
      expect(repo.histories, isEmpty);
      expect(repo.statsReads, 0);
    } finally {
      await bloc.close();
      await repo.dispose();
    }
  });
}
