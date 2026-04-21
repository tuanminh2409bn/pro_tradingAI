import 'package:equatable/equatable.dart';
import '../../../data/models/journal_models.dart';

abstract class JournalEvent extends Equatable {
  const JournalEvent();

  @override
  List<Object?> get props => [];
}

class LoadJournalData extends JournalEvent {
  final String? userId;
  const LoadJournalData({this.userId});

  @override
  List<Object?> get props => [userId];
}

class UpdateTradeHistory extends JournalEvent {
  final List<TradeRecord> trades;
  const UpdateTradeHistory(this.trades);

  @override
  List<Object?> get props => [trades];
}

class UpdateJournalStats extends JournalEvent {
  final JournalStats stats;
  const UpdateJournalStats(this.stats);

  @override
  List<Object?> get props => [stats];
}
