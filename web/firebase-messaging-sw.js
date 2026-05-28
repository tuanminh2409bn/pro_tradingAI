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
  console.log("[firebase-messaging-sw.js] Received background message: ", payload);

  const notificationTitle = payload.notification?.title || "ProTrading AI Signal";
  const notificationOptions = {
    body: payload.notification?.body || "New trade setup is ready!",
    icon: "/favicon.png",
    data: payload.data
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
