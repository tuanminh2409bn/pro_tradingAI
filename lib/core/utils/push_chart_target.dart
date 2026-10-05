class PushChartTarget {
  final String symbol;
  final String timeframe;
  final int closedAt;
  const PushChartTarget._(this.symbol, this.timeframe, this.closedAt);

  static PushChartTarget? fromUri(Uri uri) {
    final values = uri.queryParametersAll;
    const keys = ['tab', 'symbol', 'timeframe', 'closed_at'];
    if (keys.any((key) => values[key]?.length != 1)) return null;
    final symbol = values['symbol']!.single;
    final timeframe = values['timeframe']!.single;
    final closed = values['closed_at']!.single;
    if (values['tab']!.single != 'trading_room' ||
        !RegExp(r'^[A-Z0-9]{3,16}$').hasMatch(symbol) ||
        !{'M5', 'M15', 'H1', 'H4', 'D1'}.contains(timeframe) ||
        !RegExp(r'^[1-9][0-9]{0,12}$').hasMatch(closed)) {
      return null;
    }
    return PushChartTarget._(symbol, timeframe, int.parse(closed));
  }
}
