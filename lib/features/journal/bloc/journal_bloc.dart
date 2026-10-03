import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'journal_event.dart';
import 'journal_state.dart';
import '../../../data/repositories/journal_repository.dart';
import '../../../data/models/journal_models.dart';

class JournalBloc extends Bloc<JournalEvent, JournalState> {
  final JournalRepository _journalRepository;
  StreamSubscription<List<TradeRecord>>? _tradesSubscription;
  int _generation = 0;

  JournalBloc({required JournalRepository journalRepository})
    : _journalRepository = journalRepository,
      super(JournalInitial()) {
    on<LoadJournalData>(_onLoadJournalData);
    on<UpdateTradeHistory>(_onUpdateTradeHistory);
    on<JournalStreamFailed>(_onStreamFailed);
  }

  Future<void> _onLoadJournalData(
    LoadJournalData event,
    Emitter<JournalState> emit,
  ) async {
    final generation = ++_generation;
    emit(JournalLoading());
    try {
      final userId = event.userId;
      final previous = _tradesSubscription;
      _tradesSubscription = null;
      await previous?.cancel();
      if (isClosed || emit.isDone || generation != _generation) return;
      if (userId == null || userId.trim().isEmpty) {
        emit(
          JournalLoaded(trades: const [], stats: buildJournalStats(const [])),
        );
        return;
      }
      _tradesSubscription = _journalRepository
          .getTradeHistory(userId)
          .listen(
            (trades) {
              if (!isClosed && generation == _generation) {
                add(
                  UpdateTradeHistory(
                    List.unmodifiable(trades),
                    generation: generation,
                  ),
                );
              }
            },
            onError: (_) {
              if (!isClosed && generation == _generation) {
                add(JournalStreamFailed(generation));
              }
            },
          );
    } catch (_) {
      if (!isClosed && !emit.isDone && generation == _generation) {
        emit(const JournalError('common_data_unavailable'));
      }
    }
  }

  void _onStreamFailed(JournalStreamFailed event, Emitter<JournalState> emit) {
    if (event.generation != _generation) return;
    emit(const JournalError('common_data_unavailable'));
  }

  void _onUpdateTradeHistory(
    UpdateTradeHistory event,
    Emitter<JournalState> emit,
  ) {
    if (event.generation != _generation) return;
    try {
      final trades = List<TradeRecord>.unmodifiable(event.trades);
      emit(JournalLoaded(trades: trades, stats: buildJournalStats(trades)));
    } on FormatException {
      emit(const JournalError('common_data_unavailable'));
    }
  }

  @override
  Future<void> close() async {
    ++_generation;
    try {
      await _tradesSubscription?.cancel();
    } finally {
      await super.close();
    }
  }
}
