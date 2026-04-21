import 'package:equatable/equatable.dart';
import '../../../data/models/backtest_models.dart';

abstract class BacktestEvent extends Equatable {
  const BacktestEvent();

  @override
  List<Object?> get props => [];
}

class StartBacktestSession extends BacktestEvent {
  final String symbol;
  final double initialBalance;
  const StartBacktestSession(this.symbol, this.initialBalance);

  @override
  List<Object?> get props => [symbol, initialBalance];
}

class TogglePlayback extends BacktestEvent {}

class UpdateSpeed extends BacktestEvent {
  final int speed;
  const UpdateSpeed(this.speed);

  @override
  List<Object?> get props => [speed];
}

class ExecuteBacktestTrade extends BacktestEvent {
  final String type;
  final double lotSize;
  const ExecuteBacktestTrade(this.type, this.lotSize);

  @override
  List<Object?> get props => [type, lotSize];
}

class UpdateBacktestTrades extends BacktestEvent {
  final List<BacktestTrade> trades;
  const UpdateBacktestTrades(this.trades);

  @override
  List<Object?> get props => [trades];
}
