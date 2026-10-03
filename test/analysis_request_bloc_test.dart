import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/data/repositories/trading_repository.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_bloc.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_event.dart';
import 'package:protrading_ai/features/trading_room/bloc/trading_room_state.dart';

class _Repository extends Fake implements TradingRepository {
  final pending = Completer<void>();
  int requestCount = 0;

  @override
  Future<void> requestAnalysis(
    String symbol,
    String timeframe, {
    String userId = '',
    String? tradingMode,
  }) {
    requestCount++;
    return pending.future;
  }

  @override
  void changeTimeframe(String timeframe) {}
}

class _LoadedBloc extends TradingRoomBloc {
  _LoadedBloc(_Repository repository) : super(tradingRepository: repository) {
    emit(
      const TradingRoomLoaded(
        account: TradingAccount(
          balance: 0,
          equity: 0,
          margin: 0,
          leverage: 0,
          status: 'UNAVAILABLE',
        ),
        currentSymbol: 'BTCUSD',
        currentTimeframe: '5',
      ),
    );
  }
}

void main() {
  test(
    'backend quota rejection stops the spinner and reports the reason',
    () async {
      final repository = _Repository();
      final bloc = _LoadedBloc(repository);
      addTearDown(bloc.close);
      bloc.add(const RequestAnalysis());
      await bloc.stream.firstWhere(
        (state) => state is TradingRoomLoaded && state.isAnalyzing,
      );
      repository.pending.completeError(
        const AnalysisRequestFailure('quota_exhausted'),
      );
      final result =
          await bloc.stream.firstWhere(
                (state) =>
                    state is TradingRoomLoaded && state.actionResultNonce == 1,
              )
              as TradingRoomLoaded;
      expect(result.isAnalyzing, isFalse);
      expect(result.actionSucceeded, isFalse);
      expect(result.actionMessageKey, 'tr_analysis_quota_exhausted');
    },
  );

  test(
    'signal refresh and repeated clicks cannot duplicate a pending request',
    () async {
      final repository = _Repository();
      final bloc = _LoadedBloc(repository);
      addTearDown(bloc.close);
      bloc.add(const RequestAnalysis());
      await bloc.stream.firstWhere(
        (state) => state is TradingRoomLoaded && state.isAnalyzing,
      );
      bloc.add(const UpdateSignals([]));
      bloc.add(const RequestAnalysis());
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as TradingRoomLoaded).isAnalyzing, isTrue);
      expect(repository.requestCount, 1);
      repository.pending.complete();
      final result =
          await bloc.stream.firstWhere(
                (state) =>
                    state is TradingRoomLoaded && state.actionResultNonce == 1,
              )
              as TradingRoomLoaded;
      expect(result.isAnalyzing, isFalse);
      expect(result.actionSucceeded, isTrue);
    },
  );

  test(
    'a result for the old timeframe cannot change the new chart state',
    () async {
      final repository = _Repository();
      final bloc = _LoadedBloc(repository);
      addTearDown(bloc.close);
      bloc.add(const RequestAnalysis());
      await bloc.stream.firstWhere(
        (state) => state is TradingRoomLoaded && state.isAnalyzing,
      );
      bloc.add(const ChangeTimeframe('15'));
      final changed =
          await bloc.stream.firstWhere(
                (state) =>
                    state is TradingRoomLoaded &&
                    state.currentTimeframe == '15',
              )
              as TradingRoomLoaded;
      expect(changed.isAnalyzing, isFalse);
      repository.pending.completeError(
        const AnalysisRequestFailure('quota_exhausted'),
      );
      await Future<void>.delayed(Duration.zero);
      expect((bloc.state as TradingRoomLoaded).actionResultNonce, 0);
      expect((bloc.state as TradingRoomLoaded).currentTimeframe, '15');
    },
  );
}
