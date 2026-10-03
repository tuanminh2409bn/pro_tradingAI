const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../../web/flutter_bootstrap.js'), 'utf8')
  .replace('{{flutter_js}}', '')
  .replace('{{flutter_build_config}}', '')
  .replace('{{flutter_service_worker_version}}', '"release-qa"');

async function run(serviceWorker) {
  let loads = 0;
  let reloads = 0;
  const context = {URL, document: {baseURI: 'https://qa.example/'},
    navigator: serviceWorker ? {serviceWorker} : {}, console: {warn() {}},
    _flutter: {buildConfig: {builds: [{mainJsPath: 'main.dart.js'}]}, loader: {load() { loads++; }}},
    location: {reload() { reloads++; }}};
  context.window = context;
  await vm.runInNewContext(source, context);
  return {loads, reloads, entrypoint: context._flutter.buildConfig.builds[0].mainJsPath};
}

test('a browser without workers loads the release-specific entrypoint', async () => {
  assert.deepEqual(await run(), {loads: 1, reloads: 0, entrypoint: 'main.dart.js?build=release-qa'});
});

test('legacy migration reloads once and preserves the FCM registration', async () => {
  const legacy = {scriptURL: 'https://qa.example/flutter_service_worker.js?v=old'};
  const fcm = {scriptURL: 'https://qa.example/firebase-messaging-sw.js'};
  let legacyRemoved = 0;
  let fcmRemoved = 0;
  const legacyRegistration = {active: legacy, async unregister() { legacyRemoved++; return true; }};
  const fcmRegistration = {active: fcm, async unregister() { fcmRemoved++; return true; }};
  const migration = await run({controller: legacy, getRegistrations: async () => [legacyRegistration, fcmRegistration]});
  assert.equal(migration.reloads, 1); assert.equal(migration.loads, 0);
  assert.equal(legacyRemoved, 1); assert.equal(fcmRemoved, 0);
  const nextLoad = await run({controller: fcm, getRegistrations: async () => [fcmRegistration]});
  assert.equal(nextLoad.reloads, 0); assert.equal(nextLoad.loads, 1);
  assert.equal(fcmRemoved, 0);
});

test('worker API failure still starts the current release', async () => {
  const result = await run({getRegistrations: async () => { throw new Error('Worker API unavailable'); }});
  assert.equal(result.loads, 1); assert.equal(result.reloads, 0);
  assert.equal(result.entrypoint, 'main.dart.js?build=release-qa');
});
