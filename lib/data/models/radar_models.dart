import 'package:equatable/equatable.dart';

class RadarAsset extends Equatable {
  final String symbol;
  final String fullName;
  final double price;
  final double changePercent;
  final String volatilityStatus; // 'HIGH', 'STABLE', 'LOW'
  final bool hasAiConfirmation;
  final String aiSignal; // 'BUY', 'SELL', 'NEUTRAL'
  final List<double> sparklineData;

  const RadarAsset({
    required this.symbol,
    required this.fullName,
    required this.price,
    required this.changePercent,
    required this.volatilityStatus,
    required this.hasAiConfirmation,
    required this.aiSignal,
    required this.sparklineData,
  });

  @override
  List<Object?> get props => [symbol, price, changePercent, aiSignal];
}
