import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/news_models.dart';

void main() {
  group('NewsScenario V2.1 contract', () {
    test('parses every required structured section', () {
      final scenario = NewsScenario.fromMap({
        'scenario_id': 'scenario-1',
        'assumptions': ['CPI prints above consensus'],
        'affected_assets': ['XAUUSD', 'EURUSD'],
        'bullish_path': {
          'conditions': ['USD selling follows the release'],
          'projected_reactions': ['XAUUSD volatility may expand'],
        },
        'bearish_path': {
          'conditions': ['USD demand strengthens'],
          'projected_reactions': ['XAUUSD may reject resistance'],
        },
        'invalidation': ['Release is revised'],
        'risk_notice': 'Scenario only; it cannot place an order.',
        'fallback': false,
      });

      expect(scenario.contractError, isNull);
      expect(scenario.scenarioId, 'scenario-1');
      expect(scenario.affectedAssets, ['XAUUSD', 'EURUSD']);
      expect(scenario.bullishPath.projectedReactions, hasLength(1));
      expect(scenario.bearishPath.conditions, hasLength(1));
      expect(scenario.isValid, isTrue);
    });

    test('fails closed when a nested trade instruction is present', () {
      final scenario = NewsScenario.fromMap({
        'scenario_id': 'scenario-unsafe',
        'assumptions': ['Measured assumption'],
        'affected_assets': ['XAUUSD'],
        'bullish_path': {
          'conditions': ['Condition'],
          'projected_reactions': [
            {'execute': 'BUY'},
          ],
        },
        'bearish_path': {
          'conditions': ['Condition'],
          'projected_reactions': ['Reaction'],
        },
        'invalidation': ['Invalidation'],
        'risk_notice': 'Scenario only.',
        'fallback': false,
      });

      expect(scenario.isValid, isFalse);
      expect(scenario.contractError, 'trade_instruction_forbidden');
      expect(scenario.affectedAssets, isEmpty);
    });

    test('accepts a structured fallback without inventing scenario paths', () {
      final scenario = NewsScenario.fromMap({
        'scenario_id': 'fallback-1',
        'assumptions': <String>[],
        'affected_assets': ['MARKET'],
        'bullish_path': {
          'conditions': <String>[],
          'projected_reactions': <String>[],
        },
        'bearish_path': {
          'conditions': <String>[],
          'projected_reactions': <String>[],
        },
        'invalidation': <String>[],
        'risk_notice': 'Scenario analysis is temporarily unavailable.',
        'fallback': true,
      });

      expect(scenario.contractError, isNull);
      expect(scenario.fallback, isTrue);
      expect(scenario.bullishPath.projectedReactions, isEmpty);
      expect(scenario.bearishPath.projectedReactions, isEmpty);
    });
  });
}
