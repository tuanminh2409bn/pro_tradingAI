// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

// ─── TradingView symbol mapping (matches server.py TV_SYMBOL_MAP) ───────────
const _tvSymbolMap = {
  'XAUUSD': 'OANDA:XAUUSD',
  'XAGUSD': 'OANDA:XAGUSD',
  'EURUSD': 'OANDA:EURUSD',
  'GBPUSD': 'OANDA:GBPUSD',
  'USDJPY': 'OANDA:USDJPY',
  'USDCHF': 'OANDA:USDCHF',
  'AUDUSD': 'OANDA:AUDUSD',
  'USDCAD': 'OANDA:USDCAD',
  'NZDUSD': 'OANDA:NZDUSD',
  'EURGBP': 'OANDA:EURGBP',
  'EURJPY': 'OANDA:EURJPY',
  'GBPJPY': 'OANDA:GBPJPY',
  'EURAUD': 'OANDA:EURAUD',
  'GBPAUD': 'OANDA:GBPAUD',
  'BTCUSD': 'BITSTAMP:BTCUSD',
  'ETHUSD': 'BITSTAMP:ETHUSD',
  'BNBUSD': 'BINANCE:BNBUSDT',
  'SOLUSD': 'BINANCE:SOLUSDT',
  'XRPUSD': 'BITSTAMP:XRPUSD',
  'US30':   'FOREXCOM:DJI',
  'US500':  'FOREXCOM:SPX500',
  'US100':  'FOREXCOM:NAS100',
  'UK100':  'FOREXCOM:UK100',
  'DE40':   'FOREXCOM:DE40',
  'JP225':  'FOREXCOM:JPN225',
  'USOIL':  'NYMEX:CL1!',
  'UKOIL':  'ICEEUR:B1!',
  'XPTUSD': 'OANDA:XPTUSD',
};

String _toTvSymbol(String symbol) =>
    _tvSymbolMap[symbol.toUpperCase()] ?? 'OANDA:${symbol.toUpperCase()}';

/// Build the TradingView Widget HTML document injected into the iframe
String _buildTvHtml(String symbol, String interval) {
  final tvSym = _toTvSymbol(symbol);
  // Map our timeframe strings to TradingView interval format
  // TV uses: 1, 5, 15, 60, 240, D, W, M
  final tvInterval = interval == '1440' ? 'D' : interval;

  return '''<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: 100%; height: 100%; overflow: hidden; background: #111417; }
.tradingview-widget-container { width: 100%; height: 100%; }
#tv_chart { width: 100%; height: 100%; }
</style>
</head>
<body>
<div class="tradingview-widget-container">
  <div id="tv_chart"></div>
</div>
<script type="text/javascript" src="https://s3.tradingview.com/tv.js"></script>
<script type="text/javascript">
new TradingView.widget({
  "container_id":        "tv_chart",
  "autosize":            true,
  "symbol":              "$tvSym",
  "interval":            "$tvInterval",
  "timezone":            "Asia/Ho_Chi_Minh",
  "theme":               "dark",
  "style":               "1",
  "locale":              "vi_VN",
  "toolbar_bg":          "#111417",
  "backgroundColor":     "rgba(17, 20, 23, 1)",
  "gridColor":           "rgba(255, 255, 255, 0.04)",
  "enable_publishing":   false,
  "allow_symbol_change": false,
  "hide_side_toolbar":   true,
  "withdateranges":      true,
  "save_image":          false,
  "show_popup_button":   false,
  "hide_legend":         false,
  "studies":             ["Volume@tv-basicstudies"],
  "studies_overrides": {
    "volume.volume.color.0": "#ef535080",
    "volume.volume.color.1": "#26a69a80"
  }
});
</script>
</body>
</html>''';
}

// ─── TradingViewChart Widget ──────────────────────────────────────────────────

class TradingViewChart extends StatefulWidget {
  final String symbol;
  final String interval;

  const TradingViewChart({
    required this.symbol,
    required this.interval,
    super.key,
  });

  @override
  State<TradingViewChart> createState() => _TradingViewChartState();
}

class _TradingViewChartState extends State<TradingViewChart> {
  late String _viewId;
  bool _registered = false;

  @override
  void initState() {
    super.initState();
    _viewId = _generateViewId(widget.symbol, widget.interval);
    _registerView(_viewId, widget.symbol, widget.interval);
  }

  @override
  void didUpdateWidget(TradingViewChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If symbol or interval changed, create a new view with a fresh id
    if (oldWidget.symbol != widget.symbol || oldWidget.interval != widget.interval) {
      final newId = _generateViewId(widget.symbol, widget.interval);
      _registerView(newId, widget.symbol, widget.interval);
      if (mounted) setState(() => _viewId = newId);
    }
  }

  String _generateViewId(String symbol, String interval) {
    // Timestamp ensures unique ID even for repeated symbol changes
    return 'tv-chart-${symbol.toLowerCase()}-$interval-${DateTime.now().millisecondsSinceEpoch}';
  }

  void _registerView(String viewId, String symbol, String interval) {
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
      final iframe = html.IFrameElement()
        ..tabIndex = -1             // Prevent focus-stealing from Flutter UI
        ..style.width  = '100%'
        ..style.height = '100%'
        ..style.border = 'none'
        ..srcdoc = _buildTvHtml(symbol, interval);
      return iframe;
    });
    _registered = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_registered) return const SizedBox.shrink();
    return HtmlElementView(viewType: _viewId);
  }
}
