// Idle in production. Dart invokes this only in an explicit Emulator build.
// FlutterFire otherwise hydrates Auth before main() can connect the emulator.
globalThis.protradingInitializeFirebaseEmulators = async function (
  options, version, host, authPort, firestorePort, loadSdk
) {
  if (!['127.0.0.1', 'localhost', '[::1]'].includes(globalThis.location.hostname) ||
      host !== '127.0.0.1' || authPort !== 9099 || firestorePort !== 8080 ||
      version !== '12.13.0') {
    throw new Error('Firebase Emulator bootstrap requires the local QA configuration.');
  }
  const base = `https://www.gstatic.com/firebasejs/${version}/`;
  const modules = await (loadSdk ? loadSdk() : Promise.all([
    import(`${base}firebase-app.js`),
    import(`${base}firebase-auth.js`),
    import(`${base}firebase-firestore-pipelines.js`),
    import(`${base}firebase-messaging.js`),
  ]));
  const [core, auth, firestore, messaging] = modules;
  if (core.SDK_VERSION !== version) throw new Error('Firebase QA SDK version mismatch.');
  const app = core.getApps().find(app => app.name === '[DEFAULT]') || core.initializeApp(options);
  // Match FlutterFire's initializeAuth options so it can reuse this instance.
  const authInstance = auth.initializeAuth(app, {
    errorMap: auth.debugErrorMap,
    persistence: [auth.indexedDBLocalPersistence, auth.browserLocalPersistence, auth.browserSessionPersistence],
    popupRedirectResolver: auth.browserPopupRedirectResolver,
  });
  auth.connectAuthEmulator(authInstance, `http://${host}:${authPort}`);
  firestore.connectFirestoreEmulator(firestore.getFirestore(app), host, firestorePort);
  Object.assign(globalThis, {
    firebase_core: core,
    firebase_auth: auth,
    firebase_firestore: firestore,
    firebase_messaging: messaging,
  });
};
