const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('web/firebase-qa-bootstrap.js', 'utf8');

function setup(hostname = '127.0.0.1') {
  const calls = [];
  const app = {name: '[DEFAULT]'};
  const context = {location: {hostname}};
  vm.runInNewContext(source, context);
  const modules = [
    {SDK_VERSION: '12.13.0', getApps: () => [], initializeApp: options => {calls.push('app'); assert.equal(options.projectId, 'qa'); return app;}},
    {indexedDBLocalPersistence: 'indexedDB', browserLocalPersistence: 'local', browserSessionPersistence: 'session', debugErrorMap: 'errors', browserPopupRedirectResolver: 'popup',
      initializeAuth: (value, options) => {
        assert.equal(value, app);
        assert.equal(options.errorMap, 'errors');
        assert.deepEqual(Array.from(options.persistence), ['indexedDB', 'local', 'session']);
        assert.equal(options.popupRedirectResolver, 'popup');
        calls.push('auth'); return {};
      }, connectAuthEmulator: (_, origin) => calls.push(origin)},
    {getFirestore: () => ({}), connectFirestoreEmulator: (_, host, port) => calls.push(`${host}:${port}`)},
    {},
  ];
  return {context, modules, calls, initialize: () => context.protradingInitializeFirebaseEmulators({projectId:'qa'}, '12.13.0', '127.0.0.1', 9099, 8080, async () => modules)};
}

test('QA SDK connects Auth before FlutterFire can hydrate; production stays idle', async () => {
  const {context, calls, modules, initialize} = setup();
  assert.deepEqual(calls, []);
  assert.equal(context.firebase_core, undefined);
  await initialize();
  assert.deepEqual(calls, ['app', 'auth', 'http://127.0.0.1:9099', '127.0.0.1:8080']);
  assert.equal(context.firebase_core, modules[0]);
  assert.equal(context.firebase_auth, modules[1]);
  assert.equal(context.firebase_firestore, modules[2]);
  assert.equal(context.firebase_messaging, modules[3]);
});

test('a production hostname rejects QA before importing SDKs or initializing an app', async () => {
  const {calls, initialize} = setup('protrading-ai-2026.web.app');
  await assert.rejects(initialize(), /local QA configuration/);
  assert.deepEqual(calls, []);
});

test('a mismatched SDK fails closed before Auth initialization', async () => {
  const {calls, modules, initialize} = setup();
  modules[0].SDK_VERSION = 'different';
  await assert.rejects(initialize(), /version mismatch/);
  assert.deepEqual(calls, []);
});
