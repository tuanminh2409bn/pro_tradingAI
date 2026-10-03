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
  final String? userId;
  final double maxLossPercent;
  final bool createNew;
  const StartBacktestSession(
    this.symbol,
    this.initialBalance, {
    this.userId,
    this.maxLossPercent = 5,
    this.createNew = false,
  });

  @override
  List<Object?> get props => [
    symbol,
    initialBalance,
    userId,
    maxLossPercent,
    createNew,
  ];
}

class OpenBacktestSetup extends BacktestEvent {}

class RetryBacktestSave extends BacktestEvent {}

class CloseBacktestTrade extends BacktestEvent {
  final String tradeId;
  const CloseBacktestTrade(this.tradeId);
  @override
  List<Object?> get props => [tradeId];
}

class AcknowledgeBacktestReview extends BacktestEvent {
  final String reviewId;
  const AcknowledgeBacktestReview(this.reviewId);
  @override
  List<Object?> get props => [reviewId];
}

class ReplayTick extends BacktestEvent {}

class SeekReplayCursor extends BacktestEvent {
  final int cursor;
  const SeekReplayCursor(this.cursor);

  @override
  List<Object?> get props => [cursor];
}

class StepReplayCursor extends BacktestEvent {
  final int direction;
  const StepReplayCursor(this.direction);

  @override
  List<Object?> get props => [direction];
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
