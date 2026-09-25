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
  final String? confirmationId;
  final String? rationale;
  final String? model;
  final String? provider;
  final String? licenseRef;
  final String? timeframe;
  final DateTime? confirmedAt;

  const RadarAsset({
    required this.symbol,
    required this.fullName,
    required this.price,
    required this.changePercent,
    required this.volatilityStatus,
    required this.hasAiConfirmation,
    required this.aiSignal,
    required this.sparklineData,
    this.confirmationId,
    this.rationale,
    this.model,
    this.provider,
    this.licenseRef,
    this.timeframe,
    this.confirmedAt,
  });

  bool get hasVerifiedAiConfirmation =>
      hasAiConfirmation &&
      (aiSignal == 'BUY' || aiSignal == 'SELL') &&
      confirmationId?.trim().isNotEmpty == true &&
      rationale?.trim().isNotEmpty == true &&
      model?.trim().isNotEmpty == true &&
      provider?.trim().isNotEmpty == true &&
      licenseRef?.trim().isNotEmpty == true &&
      timeframe?.trim().isNotEmpty == true &&
      confirmedAt != null;

  @override
  List<Object?> get props => [
    symbol,
    price,
    changePercent,
    aiSignal,
    confirmationId,
    confirmedAt,
  ];
}
