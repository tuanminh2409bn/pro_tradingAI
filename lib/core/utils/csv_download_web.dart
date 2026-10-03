import 'dart:async';
import 'dart:js_interop';

import 'csv_download_types.dart';

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

bool get csvDownloadAvailable => _body != null;

/// Local file only. No history is uploaded or sent to an AI provider.
Future<bool> downloadJournalCsv(String csv, String filename) async {
  if (!csvDownloadAvailable || !validJournalCsvDownload(csv, filename)) {
    return false;
  }
  String? url;
  _Anchor? anchor;
  try {
    final blob = _Blob(
      <JSAny>[csv.toJS].toJS,
      _BlobOptions(type: 'text/csv;charset=utf-8;header=present'),
    );
    url = _createObjectUrl(blob);
    anchor = _createAnchor('a')
      ..href = url
      ..download = filename;
    _body!.appendChild(anchor);
    anchor.click();
    return true;
  } catch (_) {
    return false;
  } finally {
    anchor?.remove();
    final objectUrl = url;
    if (objectUrl != null) {
      Timer(const Duration(seconds: 1), () => _revokeObjectUrl(objectUrl));
    }
  }
}
