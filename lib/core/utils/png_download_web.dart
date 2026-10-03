import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
}

@JS()
extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

@JS('URL.createObjectURL')
external String _createObjectUrl(_Blob blob);
@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);
@JS('document.createElement')
external _Anchor _createAnchor(String tag);
@JS('document.body')
external _Body? get _body;

@JS()
extension type _Body(JSObject _) implements JSObject {
  external void appendChild(_Anchor anchor);
}
@JS()
extension type _Anchor(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
  external void remove();
}

/// Downloads the locally rendered PNG; no referral data is uploaded.
Future<bool> downloadPng(Uint8List bytes, String filename) async {
  if (bytes.length < 8 ||
      bytes.length > 5 * 1024 * 1024 ||
      !RegExp(r'^[A-Za-z0-9_-]{1,100}\.png$').hasMatch(filename) ||
      _body == null) {
    return false;
  }
  final blob = _Blob(<JSAny>[bytes.toJS].toJS, _BlobOptions(type: 'image/png'));
  final url = _createObjectUrl(blob);
  final anchor = _createAnchor('a')
    ..href = url
    ..download = filename;
  try {
    _body!.appendChild(anchor);
    anchor.click();
    return true;
  } finally {
    anchor.remove();
    Timer(const Duration(seconds: 1), () => _revokeObjectUrl(url));
  }
}
