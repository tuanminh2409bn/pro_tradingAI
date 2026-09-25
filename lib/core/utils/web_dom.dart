import 'dart:js_interop';

@JS('document')
external _Document get _document;

@JS()
extension type _Document(JSObject _) implements JSObject {
  external _Iframe createElement(String name);
  external _IframeList querySelectorAll(String selector);
}

@JS()
extension type _IframeList(JSObject _) implements JSObject {
  external int get length;
  external _Iframe? item(int index);
}

@JS()
extension type _Iframe(JSObject _) implements JSObject {
  external set tabIndex(int value);
  external _Style get style;
  external set srcdoc(String value);
}

@JS()
extension type _Style(JSObject _) implements JSObject {
  external set width(String value);
  external set height(String value);
  external set border(String value);
  external set pointerEvents(String value);
}

Object createChartIframe(String html) {
  final iframe = _document.createElement('iframe')
    ..tabIndex = -1
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.border = 'none'
    ..srcdoc = html;
  return iframe;
}

/// Prevents chart iframes from taking pointer input while a Flutter dialog is open.
void setIframesInteractive(bool interactive) {
  final iframes = _document.querySelectorAll('iframe');
  for (var index = 0; index < iframes.length; index++) {
    iframes.item(index)?.style.pointerEvents = interactive ? 'auto' : 'none';
  }
}
