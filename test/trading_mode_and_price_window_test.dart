import 'package:flutter_test/flutter_test.dart';
import 'package:protrading_ai/data/models/trading_models.dart';
import 'package:protrading_ai/features/trading_room/web/widgets/chart_price_window.dart';

void main() {
  group('TradingMode V2.1 matrix', () {
    test('scalping allows M5/M15/H1 only', () {
      final m = TradingMode.scalping;
      expect(m.timeframeLabels, ['M5', 'M15', 'H1']);
      expect(m.allowsTimeframe('5'), isTrue);
      expect(m.allowsTimeframe('15'), isTrue);
      expect(m.allowsTimeframe('60'), isTrue);
      expect(m.allowsTimeframe('M5'), isTrue);
      expect(m.allowsTimeframe('H1'), isTrue);
      expect(m.normalizeTimeframe('H1'), '60');
      expect(m.wireName, 'scalping');
      expect(m.allowsTimeframe('240'), isFalse);
      expect(m.allowsTimeframe('1440'), isFalse);
    });

    test('dayTrading and swingTrading lock correctly', () {
      expect(TradingMode.dayTrading.allowsTimeframe('15'), isTrue);
      expect(TradingMode.dayTrading.allowsTimeframe('H4'), isTrue);
      expect(TradingMode.dayTrading.wireName, 'day_trading');
      expect(TradingMode.dayTrading.allowsTimeframe('5'), isFalse);
      expect(TradingMode.swingTrading.allowsTimeframe('1440'), isTrue);
      expect(TradingMode.swingTrading.allowsTimeframe('D1'), isTrue);
      expect(TradingMode.swingTrading.wireName, 'swing');
      expect(TradingMode.swingTrading.allowsTimeframe('5'), isFalse);
    });
  });

  group('computePriceWindow', () {
    test('scaleY > 1 narrows the window around center', () {
      final base = computePriceWindow(autoMin: 100, autoMax: 200);
      final zoomed = computePriceWindow(autoMin: 100, autoMax: 200, scaleY: 2);
      expect(zoomed.range, closeTo(base.range / 2, 1e-9));
      expect((zoomed.min + zoomed.max) / 2, closeTo(150, 1e-9));
    });

    test('priceOffset shifts the window', () {
      final shifted = computePriceWindow(
        autoMin: 100,
        autoMax: 200,
        priceOffset: 10,
      );
      expect((shifted.min + shifted.max) / 2, closeTo(160, 1e-9));
    });
  });

  group('independent chart-axis scaling', () {
    test('horizontal time-axis drag changes only the X scale', () {
      final scaleX = computeTimeAxisDragScale(
        initialScale: 1,
        horizontalDelta: 90,
      );
      expect(scaleX, greaterThan(1));
      expect(computePriceAxisDragScale(initialScale: 1, verticalDelta: 0), 1);
    });

    test('vertical price-axis drag changes only the Y scale', () {
      final scaleY = computePriceAxisDragScale(
        initialScale: 1,
        verticalDelta: -90,
      );
      expect(scaleY, greaterThan(1));
      expect(computeTimeAxisDragScale(initialScale: 1, horizontalDelta: 0), 1);
    });
  });
}
