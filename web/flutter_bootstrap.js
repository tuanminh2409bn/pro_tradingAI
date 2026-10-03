{{flutter_js}}
{{flutter_build_config}}

const releaseVersion = {{flutter_service_worker_version}};
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += `?build=${releaseVersion}`;
}

(async () => {
  // Remove only the legacy Flutter cache worker; keep the FCM worker.
  const legacyUrl = new URL('flutter_service_worker.js', document.baseURI);
  const isLegacy = (worker) => worker &&
    new URL(worker.scriptURL).origin === legacyUrl.origin &&
    new URL(worker.scriptURL).pathname === legacyUrl.pathname;
  try {
    if ('serviceWorker' in navigator) {
      let removed = false;
      for (const registration of await navigator.serviceWorker.getRegistrations()) {
        if (isLegacy(registration.active || registration.waiting || registration.installing)) {
          removed = await registration.unregister() || removed;
        }
      }
      if (removed && isLegacy(navigator.serviceWorker.controller)) {
        window.location.reload();
        return;
      }
    }
  } catch (_) {
    console.warn('Could not remove the legacy Flutter cache.');
  }
  _flutter.loader.load();
})();
