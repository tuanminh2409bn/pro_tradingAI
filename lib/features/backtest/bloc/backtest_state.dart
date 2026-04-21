import 'package:equatable/equatable.dart';
import '../../../data/models/backtest_models.dart';

abstract class BacktestState extends Equatable {
  const BacktestState();

  @override
  List<Object?> get props => [];
}

class BacktestInitial extends BacktestState {}

class BacktestLoading extends BacktestState {}

class BacktestLoaded extends BacktestState {
  final BacktestSession session;
  final List<BacktestTrade> activeTrades;

  const BacktestLoaded({
    required this.session,
    this.activeTrades = const [],
  });

  BacktestLoaded copyWith({
    BacktestSession? session,
    List<BacktestTrade>? activeTrades,
  }) {
    return BacktestLoaded(
      session: session ?? this.session,
      activeTrades: activeTrades ?? this.activeTrades,
    );
  }

  @override
  List<Object?> get props => [session, activeTrades];
}

class BacktestError extends BacktestState {
  final String message;
  const BacktestError(this.message);

  @override
  List<Object?> get props => [message];
}
