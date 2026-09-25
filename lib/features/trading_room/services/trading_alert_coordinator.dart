import 'package:equatable/equatable.dart';
import '../../../data/models/trading_models.dart';

enum TradingAlertLevel { waitingZone, hardSetup }

class TradingAlertEvent extends Equatable {
  final TradingAlertLevel level;
  final String chartId;
  final String symbol;
  final bool vibrate;
  final bool siren;

  const TradingAlertEvent({
    required this.level,
    required this.chartId,
    required this.symbol,
    required this.vibrate,
    required this.siren,
  });

  @override
  List<Object?> get props => [level, chartId, symbol, vibrate, siren];
}

/// Pure transition detector. Platform notification, sound, and vibration
/// adapters consume these events only after permissions and opt-in are checked.
class TradingAlertCoordinator {
  String? _activeChartId;
  final Set<TradingAlertLevel> _emitted = {};

  List<TradingAlertEvent> evaluate({
    required TradingSignal? signal,
    required double currentPrice,
    required bool alertsEnabled,
  }) {
    final chartId = signal?.chartId;
    if (signal == null ||
        chartId == null ||
        chartId.isEmpty ||
        !alertsEnabled ||
        signal.veto ||
        currentPrice <= 0) {
      return const [];
    }
    if (_activeChartId != chartId) {
      _activeChartId = chartId;
      _emitted.clear();
    }

    if (signal.setupReady && signal.canExecute) {
      return _emitOnce(
        signal,
        chartId,
        TradingAlertLevel.hardSetup,
        vibrate: true,
        siren: true,
      );
    }
    if (!signal.setupReady && _touchesWaitingZone(signal, currentPrice)) {
      return _emitOnce(
        signal,
        chartId,
        TradingAlertLevel.waitingZone,
        vibrate: true,
        siren: false,
      );
    }
    return const [];
  }

  List<TradingAlertEvent> _emitOnce(
    TradingSignal signal,
    String chartId,
    TradingAlertLevel level, {
    required bool vibrate,
    required bool siren,
  }) {
    if (!_emitted.add(level)) return const [];
    return [
      TradingAlertEvent(
        level: level,
        chartId: chartId,
        symbol: signal.symbol,
        vibrate: vibrate,
        siren: siren,
      ),
    ];
  }

  bool _touchesWaitingZone(TradingSignal signal, double price) {
    for (final layer in signal.layers) {
      if (layer['items'] is! List) continue;
      for (final raw in layer['items'] as List) {
        if (raw is! Map) continue;
        final type = raw['type'] ?? raw['kind'];
        if (type != 'solid_box' &&
            type != 'bordered_box' &&
            type != 'ghost_box') {
          continue;
        }
        final top = raw['y_top'] ?? raw['price_top'];
        final bottom = raw['y_bottom'] ?? raw['price_bottom'];
        if (top is! num || bottom is! num) continue;
        final lower = top.toDouble() < bottom.toDouble()
            ? top.toDouble()
            : bottom.toDouble();
        final upper = top.toDouble() > bottom.toDouble()
            ? top.toDouble()
            : bottom.toDouble();
        if (price >= lower && price <= upper) return true;
      }
    }
    return false;
  }
}
