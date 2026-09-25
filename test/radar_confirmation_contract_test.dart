import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/radar_models.dart';

RadarAsset asset({
  bool declared = true,
  String? confirmationId = 'radar-123',
  String? rationale = 'Measured volume expansion at a validated barrier.',
  String? model = 'deepseek-chat',
  String? provider = 'approved-market-provider',
  String? licenseRef = 'license-1',
  String? timeframe = 'M15',
  DateTime? confirmedAt,
}) => RadarAsset(
  symbol: 'XAUUSD',
  fullName: 'Gold',
  price: 2500,
  changePercent: 1,
  volatilityStatus: 'HIGH',
  hasAiConfirmation: declared,
  aiSignal: 'BUY',
  sparklineData: const [],
  confirmationId: confirmationId,
  rationale: rationale,
  model: model,
  provider: provider,
  licenseRef: licenseRef,
  timeframe: timeframe,
  confirmedAt: confirmedAt ?? DateTime.utc(2026, 9, 17),
);

void main() {
  test('Radar confirmation requires complete provenance', () {
    expect(asset().hasVerifiedAiConfirmation, isTrue);
    expect(asset(provider: null).hasVerifiedAiConfirmation, isFalse);
    expect(asset(rationale: '').hasVerifiedAiConfirmation, isFalse);
    expect(asset(declared: false).hasVerifiedAiConfirmation, isFalse);
  });
}
