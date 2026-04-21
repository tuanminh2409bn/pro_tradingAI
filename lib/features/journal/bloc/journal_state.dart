import 'package:equatable/equatable.dart';
import '../../../data/models/journal_models.dart';

abstract class JournalState extends Equatable {
  const JournalState();

  @override
  List<Object?> get props => [];
}

class JournalInitial extends JournalState {}

class JournalLoading extends JournalState {}

class JournalLoaded extends JournalState {
  final List<TradeRecord> trades;
  final JournalStats stats;

  const JournalLoaded({
    required this.trades,
    required this.stats,
  });

  JournalLoaded copyWith({
    List<TradeRecord>? trades,
    JournalStats? stats,
  }) {
    return JournalLoaded(
      trades: trades ?? this.trades,
      stats: stats ?? this.stats,
    );
  }

  @override
  List<Object?> get props => [trades, stats];
}

class JournalError extends JournalState {
  final String message;
  const JournalError(this.message);

  @override
  List<Object?> get props => [message];
}
