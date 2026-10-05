const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../web/firebase-messaging-sw.js'), 'utf8');

function worker() {
  let background, click;
  const displayed = [], opened = [];
  const context = {URL, importScripts() {}, firebase: {initializeApp() {}, messaging() {
    return {onBackgroundMessage(handler) { background = handler; }};
  }}, self: {location: {origin: 'https://qa.example'}, addEventListener(type, handler) {
    assert.equal(type, 'notificationclick'); click = handler;
  }, registration: {async showNotification(title, options) { displayed.push({title, options}); }},
  clients: {async matchAll() { return []; }, async openWindow(url) { opened.push(url); }}}};
  vm.runInNewContext(source, context);
  return {background, displayed, opened, async click(data) {
    let pending, stopped = false, closed = false;
    click({stopImmediatePropagation() { stopped = true; }, notification: {data, close() { closed = true; }}, waitUntil(promise) { pending = promise; }});
    await pending; assert.equal(stopped && closed, true);
  }};
}

test('SDK notification messages are displayed once; incomplete data does not invent a trade', async () => {
  const w = worker();
  await w.background({notification: {title: 'Approved signal', body: 'Measured signal'}, data: {symbol: 'ETHUSD'}});
  await w.background({data: {symbol: 'ETHUSD'}});
  assert.equal(w.displayed.length, 0);
  await w.background({messageId: 'qa-message', data: {title: 'Measured signal', body: 'Details', symbol: 'ETHUSD'}});
  assert.equal(w.displayed.length, 1);
  assert.equal(w.displayed[0].options.tag, 'qa-message');
  assert.equal(source.includes('console.log'), false);
});

test('click targets are same-origin and accept only structured chart data', async () => {
  const w = worker();
  await w.click({FCM_MSG: {data: {tab: 'trading_room', symbol: 'ETHUSD', timeframe: 'H4', closed_at: '1791158400', url: 'https://evil.test/'}}});
  const target = new URL(w.opened[0]);
  assert.equal(target.origin, 'https://qa.example');
  assert.equal(target.searchParams.get('symbol'), 'ETHUSD');
  assert.equal(target.searchParams.get('timeframe'), 'H4');
  for (const change of [{symbol: '../admin'}, {timeframe: 'M1'}, {closed_at: '-1'}, {tab: 'admin'}]) {
    await w.click({tab: 'trading_room', symbol: 'ETHUSD', timeframe: 'H4', closed_at: '1791158400', ...change});
    assert.equal(w.opened.at(-1), 'https://qa.example/');
  }
});
