// TradingView Chart Widget — platform-aware export.
// On Web: renders TradingView's official chart widget via iframe.
// On mobile: renders a placeholder.
export 'tv_chart_stub.dart' if (dart.library.html) 'tv_chart_web.dart';
