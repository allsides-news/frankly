{{flutter_js}}
{{flutter_build_config}}

// Use absolute URLs to fix MIME type errors when using PathUrlStrategy on deep routes.
// Without this, flutter_service_worker.js and main.dart.js are requested relative to
// the current path (e.g. /space/.../discuss/xxx/), causing the server to return
// index.html (text/html) instead of the actual JS files.
// See: https://github.com/flutter/flutter/issues/116360
const serviceWorkerVersion = {{flutter_service_worker_version}};

let baseUri = document.baseURI;
if (!baseUri.endsWith("/")) {
  baseUri = baseUri + "/";
}

const kClearedFlutterSwFlag = "franklyClearedFlutterSW";

function loadFlutterApp() {
  // serviceWorkerSettings intentionally omitted: Flutter 3.41 deprecated and
  // nulled the service worker. Passing serviceWorkerSettings causes the loader
  // to await a 4-second SW registration timeout on every page load for no benefit.
  _flutter.loader.load({
    config: {
      entrypointBaseUrl: baseUri,
      // Same origin as <base href="/">. Without this, a deep PathUrlStrategy
      // route can request AssetManifest.bin.json relative to /space/.../ and
      // get index.html back.
      assetBase: baseUri,
    },
    onEntrypointLoaded: async function(engineInitializer) {
      const appRunner = await engineInitializer.initializeEngine();
      await appRunner.runApp();
      // Flutter has painted its first frame — fade out the HTML loading screen.
      const loadingScreen = document.getElementById('loading-screen');
      if (loadingScreen) {
        loadingScreen.classList.add('fade-out');
        setTimeout(function() { loadingScreen.remove(); }, 350);
      }
    },
  });
}

function hasClearedLegacyFlutterSw() {
  try {
    return sessionStorage.getItem(kClearedFlutterSwFlag) === "1";
  } catch (_) {
    return false;
  }
}

function markClearedLegacyFlutterSw() {
  try {
    sessionStorage.setItem(kClearedFlutterSwFlag, "1");
  } catch (_) {}
}

function isLegacyFlutterServiceWorker(registration) {
  const workers = [
    registration.installing,
    registration.waiting,
    registration.active,
  ];
  for (let i = 0; i < workers.length; i++) {
    const worker = workers[i];
    if (!worker) continue;
    try {
      const path = new URL(worker.scriptURL, window.location.href).pathname;
      if (path.endsWith("/flutter_service_worker.js")) {
        return true;
      }
    } catch (_) {
      if (String(worker.scriptURL).indexOf("flutter_service_worker.js") !== -1) {
        return true;
      }
    }
  }
  return false;
}

async function unregisterLegacyFlutterServiceWorkers() {
  if (!("serviceWorker" in navigator)) return false;
  const registrations = await navigator.serviceWorker.getRegistrations();
  const legacy = registrations.filter(isLegacyFlutterServiceWorker);
  if (legacy.length === 0) return false;
  await Promise.all(
    legacy.map(function (registration) {
      return registration.unregister();
    })
  );
  if (window.caches) {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter(function (key) {
          return key.toLowerCase().indexOf("flutter") !== -1;
        })
        .map(function (key) {
          return caches.delete(key);
        })
    );
  }
  return true;
}

if (hasClearedLegacyFlutterSw()) {
  loadFlutterApp();
} else {
  unregisterLegacyFlutterServiceWorkers()
    .catch(function () {
      return false;
    })
    .then(function (didUnregister) {
      if (didUnregister) {
        markClearedLegacyFlutterSw();
        window.location.reload();
        return;
      }
      loadFlutterApp();
    });
}
