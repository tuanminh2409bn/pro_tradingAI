// Register before Firebase, which otherwise installs its own click handler.
self.addEventListener('notificationclick', event => {
  event.stopImmediatePropagation();
  event.notification.close();
  const raw = event.notification.data || {};
  const data = raw.FCM_MSG?.data || raw;
  const target = new URL('/', self.location.origin);
  if (data.tab === 'trading_room' && /^[A-Z0-9]{3,16}$/.test(data.symbol || '') &&
      ['M5', 'M15', 'H1', 'H4', 'D1'].includes(data.timeframe) &&
      /^[1-9][0-9]{0,12}$/.test(data.closed_at || '')) {
    for (const key of ['tab', 'symbol', 'timeframe', 'closed_at']) target.searchParams.set(key, data[key]);
  }
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of windows) {
      if (new URL(client.url).origin !== target.origin) continue;
      const navigated = await client.navigate(target.href);
      if (navigated) return navigated.focus();
    }
    return self.clients.openWindow(target.href);
  })());
});

importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.1/firebase-messaging-compat.js");

// Initialize the Firebase app in the service worker
firebase.initializeApp({
  apiKey: "AIzaSyBwJDH7FB_VbZj4Z-KwZESeqcLrbxoAb4Y",
  appId: "1:22073478183:web:196301514afe83b4fd9202",
  messagingSenderId: "22073478183",
  projectId: "protrading-ai-2026",
  authDomain: "protrading-ai-2026.firebaseapp.com",
  storageBucket: "protrading-ai-2026.firebasestorage.app"
});

const messaging = firebase.messaging();

// Background message handler
messaging.onBackgroundMessage(function(payload) {
  // Notification payloads are already displayed by Firebase.
  if (payload.notification) return;
  const notificationTitle = payload.data?.title;
  const body = payload.data?.body;
  if (typeof notificationTitle !== 'string' || !notificationTitle.trim() || notificationTitle.length > 200 ||
      typeof body !== 'string' || !body.trim() || body.length > 1000) return;
  const notificationOptions = {
    body,
    icon: "/favicon.png",
    data: payload.data,
    tag: payload.messageId
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
