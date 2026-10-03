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
  final int generation;
  const UpdateTradeHistory(this.trades, {required this.generation});

  @override
  List<Object?> get props => [trades, generation];
}

class JournalStreamFailed extends JournalEvent {
  final int generation;
  const JournalStreamFailed(this.generation);

  @override
  List<Object?> get props => [generation];
}
