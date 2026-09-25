/// Enables isolated Firebase Auth and Firestore Emulators in a local Web build.
/// The release default is disabled.
class LocalQaMode {
  static const bool enabled = bool.fromEnvironment(
    'PROTRADING_USE_FIREBASE_EMULATORS',
  );

  static const String host = '127.0.0.1';
  static const int authPort = 9099;
  static const int firestorePort = 8080;
}
