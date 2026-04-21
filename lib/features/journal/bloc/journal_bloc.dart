import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'journal_event.dart';
import 'journal_state.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../../data/models/journal_models.dart';

class JournalBloc extends Bloc<JournalEvent, JournalState> {
  final JournalRepository _journalRepository;
  StreamSubscription? _tradesSubscription;
  StreamSubscription? _statsSubscription;

  JournalBloc({required JournalRepository journalRepository})
      : _journalRepository = journalRepository,
        super(JournalInitial()) {
    on<LoadJournalData>(_onLoadJournalData);
    on<UpdateTradeHistory>(_onUpdateTradeHistory);
    on<UpdateJournalStats>(_onUpdateJournalStats);
  }

  Future<void> _onLoadJournalData(LoadJournalData event, Emitter<JournalState> emit) async {
    emit(JournalLoading());
    try {
      final userId = event.userId;
      
      _tradesSubscription?.cancel();
      _statsSubscription?.cancel();

      if (userId != null && userId.isNotEmpty) {
        _tradesSubscription = _journalRepository.getTradeHistory(userId).listen(
          (trades) => add(UpdateTradeHistory(trades)),
          onError: (e) => print('JournalBloc: Trades error: $e'),
        );

        _statsSubscription = _journalRepository.getJournalStats(userId).listen(
          (stats) => add(UpdateJournalStats(stats)),
          onError: (e) => print('JournalBloc: Stats error: $e'),
        );
      }

      // Emit initial Loaded state immediately with mock/empty data
      emit(const JournalLoaded(
        trades: [],
        stats: JournalStats(totalProfit: 0.0, winRate: 0.0, profitFactor: 0.0, rrRatio: '0:0', equityData: []),
      ));
    } catch (e) {
      emit(JournalError(e.toString()));
    }
  }

  void _onUpdateTradeHistory(UpdateTradeHistory event, Emitter<JournalState> emit) {
    if (state is JournalLoaded) {
      emit((state as JournalLoaded).copyWith(trades: event.trades));
    }
  }

  void _onUpdateJournalStats(UpdateJournalStats event, Emitter<JournalState> emit) {
    if (state is JournalLoaded) {
      emit((state as JournalLoaded).copyWith(stats: event.stats));
    }
  }

  @override
  Future<void> close() {
    _tradesSubscription?.cancel();
    _statsSubscription?.cancel();
    return super.close();
  }
}
