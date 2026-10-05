import 'dart:js_interop';
import 'package:firebase_core/firebase_core.dart';
import '../constants/local_qa_mode.dart';

@JS('protradingInitializeFirebaseEmulators')
external JSPromise<JSAny?> _prepare(
  JSAny options,
  JSString version,
  JSString host,
  JSNumber authPort,
  JSNumber firestorePort,
);

/// Connect before FlutterFire waits for a persisted Auth session to hydrate.
Future<void> prepareFirebaseQa(FirebaseOptions options) async {
  await _prepare(
    options.asMap.jsify()!,
    LocalQaMode.firebaseJsSdkVersion.toJS,
    LocalQaMode.host.toJS,
    LocalQaMode.authPort.toJS,
    LocalQaMode.firestorePort.toJS,
  ).toDart.timeout(const Duration(seconds: 20));
}
