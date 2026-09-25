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
  final List<BacktestBar> visibleBars;
  final int cursor;
  final int totalBars;
  final String historySource;

  const BacktestLoaded({
    required this.session,
    this.activeTrades = const [],
    required this.visibleBars,
    required this.cursor,
    required this.totalBars,
    required this.historySource,
  });

  BacktestLoaded copyWith({
    BacktestSession? session,
    List<BacktestTrade>? activeTrades,
    List<BacktestBar>? visibleBars,
    int? cursor,
    int? totalBars,
    String? historySource,
  }) {
    return BacktestLoaded(
      session: session ?? this.session,
      activeTrades: activeTrades ?? this.activeTrades,
      visibleBars: visibleBars ?? this.visibleBars,
      cursor: cursor ?? this.cursor,
      totalBars: totalBars ?? this.totalBars,
      historySource: historySource ?? this.historySource,
    );
  }

  @override
  List<Object?> get props => [
    session,
    activeTrades,
    visibleBars,
    cursor,
    totalBars,
    historySource,
  ];
}

class BacktestError extends BacktestState {
  final String message;
  const BacktestError(this.message);

  @override
  List<Object?> get props => [message];
}
