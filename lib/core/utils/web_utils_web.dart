// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Enables or disables pointer-event handling on ALL iframes in the page.
/// Call setIframesInteractive(false) before opening a Flutter dialog that
/// overlaps the TradingView chart (an iframe), and call setIframesInteractive(true)
/// in the .then() callback to restore interactivity.
///
/// This prevents the iframe from stealing focus/events from Flutter's dialog layer.
void setIframesInteractive(bool interactive) {
  final iframes = html.document.querySelectorAll('iframe');
  for (final el in iframes) {
    if (el is html.IFrameElement) {
      el.style.pointerEvents = interactive ? 'auto' : 'none';
    }
  }
}
