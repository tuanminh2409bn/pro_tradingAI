import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'referral_video_types.dart';

@JS('MediaRecorder')
external JSObject? get _mediaRecorder;
@JS('HTMLCanvasElement.prototype.captureStream')
external JSFunction? get _captureStream;
@JS('MediaRecorder.isTypeSupported')
external bool _isTypeSupported(String mimeType);

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
  external int get size;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}
@JS()
extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}
@JS('URL.createObjectURL')
external String _createObjectUrl(_Blob blob);
@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

@JS('Image')
extension type _Image._(JSObject _) implements JSObject {
  external factory _Image();
  external set src(String value);
  external int get naturalWidth;
  external int get naturalHeight;
  external JSPromise<JSAny?> decode();
}
@JS('document.createElement')
external _Canvas _createCanvas(String tag);
@JS()
extension type _Canvas(JSObject _) implements JSObject {
  external set width(int value);
  external set height(int value);
  external _Context? getContext(String kind);
  external _Stream captureStream(int frameRate);
}
@JS()
extension type _Context(JSObject _) implements JSObject {
  external void drawImage(_Image image, int x, int y);
  external set fillStyle(String value);
  external void fillRect(double x, double y, double width, double height);
}
@JS()
extension type _Stream(JSObject _) implements JSObject {
  external JSArray<_Track> getTracks();
}
@JS()
extension type _Track(JSObject _) implements JSObject {
  external void stop();
}
@JS('MediaRecorder')
extension type _Recorder._(JSObject _) implements JSObject {
  external factory _Recorder(_Stream stream, _RecorderOptions options);
  external String get state;
  external String get mimeType;
  external set ondataavailable(JSFunction? callback);
  external set onstop(JSFunction? callback);
  external set onerror(JSFunction? callback);
  external void start(int timeslice);
  external void stop();
}
@JS()
extension type _RecorderOptions._(JSObject _) implements JSObject {
  external factory _RecorderOptions({String mimeType, int videoBitsPerSecond});
}
@JS()
extension type _DataEvent(JSObject _) implements JSObject {
  external _Blob get data;
}
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

String? _supportedMimeType() {
  if (_mediaRecorder == null || _captureStream == null) return null;
  // An unspecified MP4 codec can select VP9, which many phone players reject.
  for (final mimeType in [
    'video/mp4;codecs=avc1.424028',
    'video/webm;codecs=vp8',
    'video/webm',
  ]) {
    if (_isTypeSupported(mimeType)) return mimeType;
  }
  return null;
}

bool isReferralVideoSupported() => _supportedMimeType() != null;

/// Records only original banner artwork. Never opens a device or uploads data.
Future<ReferralVideo?> renderReferralVideo(
  Uint8List bannerPng, {
  bool Function()? isCancelled,
}) async {
  final mimeType = _supportedMimeType();
  if (mimeType == null ||
      bannerPng.length < 8 ||
      bannerPng.length > 5 * 1024 * 1024 ||
      bannerPng[0] != 137 ||
      bannerPng[1] != 80 ||
      bannerPng[2] != 78 ||
      bannerPng[3] != 71 ||
      bannerPng[4] != 13 ||
      bannerPng[5] != 10 ||
      bannerPng[6] != 26 ||
      bannerPng[7] != 10 ||
      (isCancelled?.call() ?? false)) {
    return null;
  }
  final imageUrl = _createObjectUrl(
    _Blob(<JSAny>[bannerPng.toJS].toJS, _BlobOptions(type: 'image/png')),
  );
  final image = _Image()..src = imageUrl;
  _Canvas? canvas;
  _Stream? stream;
  _Recorder? recorder;
  try {
    await image.decode().toDart.timeout(const Duration(seconds: 5));
    if (isCancelled?.call() ?? false) return null;
    if (image.naturalWidth != 1200 || image.naturalHeight != 630) {
      throw StateError('Unexpected referral artwork dimensions');
    }
    canvas = _createCanvas('canvas')
      ..width = 1200
      ..height = 630;
    final context = canvas.getContext('2d');
    if (context == null) throw StateError('Canvas unavailable');
    context.drawImage(image, 0, 0);
    stream = canvas.captureStream(12);
    final activeRecorder = _Recorder(
      stream,
      _RecorderOptions(mimeType: mimeType, videoBitsPerSecond: 1500000),
    );
    recorder = activeRecorder;
    final chunks = <JSAny>[];
    final stopped = Completer<void>();
    var failed = false;
    var size = 0;
    activeRecorder.ondataavailable = ((_DataEvent event) {
      size += event.data.size;
      if (size > 20 * 1024 * 1024) {
        failed = true;
        if (activeRecorder.state != 'inactive') activeRecorder.stop();
      } else if (event.data.size > 0) {
        chunks.add(event.data);
      }
    }).toJS;
    activeRecorder.onstop = (() {
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;
    activeRecorder.onerror = (() {
      failed = true;
      if (!stopped.isCompleted) stopped.complete();
    }).toJS;
    activeRecorder.start(500);
    final elapsed = Stopwatch()..start();
    while (elapsed.elapsedMilliseconds < 6000 && !stopped.isCompleted) {
      if (isCancelled?.call() ?? false) return null;
      context.drawImage(image, 0, 0);
      context.fillStyle = '#26364D';
      context.fillRect(56, 604, 1088, 4);
      context.fillStyle = '#8EF0CE';
      context.fillRect(56, 604, 1088 * elapsed.elapsedMilliseconds / 6000, 4);
      await Future<void>.delayed(const Duration(milliseconds: 83));
    }
    if (failed || stopped.isCompleted) throw StateError('Recording failed');
    activeRecorder.stop();
    await stopped.future.timeout(const Duration(seconds: 3));
    if (failed || chunks.isEmpty) throw StateError('Video unavailable');
    if (isCancelled?.call() ?? false) return null;
    final result = _Blob(
      chunks.toJS,
      _BlobOptions(type: activeRecorder.mimeType),
    );
    final bytes = (await result.arrayBuffer().toDart.timeout(
      const Duration(seconds: 3),
    )).toDart.asUint8List();
    return ReferralVideo(bytes, activeRecorder.mimeType);
  } finally {
    if (recorder != null) {
      recorder.ondataavailable = null;
      recorder.onstop = null;
      recorder.onerror = null;
      if (recorder.state != 'inactive') recorder.stop();
    }
    if (stream != null) {
      for (final track in stream.getTracks().toDart) {
        track.stop();
      }
    }
    if (canvas != null) {
      canvas.width = 1;
      canvas.height = 1;
    }
    image.src = '';
    _revokeObjectUrl(imageUrl);
  }
}

Future<bool> downloadReferralVideo(ReferralVideo video, String filename) async {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(filename) || _body == null) {
    return false;
  }
  // Recheck mutable bytes before a download, including the container signature.
  try {
    ReferralVideo(video.bytes, video.mimeType);
  } on ArgumentError {
    return false;
  }
  final blob = _Blob(
    <JSAny>[video.bytes.toJS].toJS,
    _BlobOptions(type: video.mimeType),
  );
  final url = _createObjectUrl(blob);
  final anchor = _createAnchor('a')
    ..href = url
    ..download = '$filename.${video.extension}';
  try {
    _body!.appendChild(anchor);
    anchor.click();
    return true;
  } finally {
    anchor.remove();
    Timer(const Duration(seconds: 1), () => _revokeObjectUrl(url));
  }
}
