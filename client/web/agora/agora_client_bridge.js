/**
 * Agora client bridge — dual-stream / subscriber-side quality APIs.
 *
 * iris-web-rtc stubs out enableDualStreamMode, setRemoteVideoStreamType,
 * setStreamFallbackOption and setRemoteDefaultVideoStreamType ("not
 * supported in this platform!"), even though the Agora Web SDK embedded in
 * the same bundle implements all of them on the AgoraRTCClient object. This
 * script captures the client instances iris creates and exposes those calls
 * to Dart.
 *
 * How the capture works: iris resolves its SDK namespace from the module it
 * bundles, which it also exports as window.__ARTC__ (verified: the Flutter
 * plugin never passes an agoraRTC override to IrisWebRtc.initIrisRtc, so
 * globalState.AgoraRTC is always this default). Wrapping
 * __ARTC__.createClient therefore sees every client iris creates. Same
 * technique as the RTCPeerConnection proxy in index.html.
 *
 * Everything fails soft: if __ARTC__ is missing (a different iris build) the
 * bridge reports unavailable, Dart skips dual-stream mode, and the app
 * behaves exactly as without this file.
 *
 * Load order: after iris-web-rtc.js (its module eval assigns __ARTC__),
 * before flutter_bootstrap.js — enforced by <script defer> order.
 *
 * Enum values (Agora Web SDK, match the native SDK integer values):
 *   RemoteStreamType:          0 = high, 1 = low
 *   RemoteStreamFallbackType:  0 = disabled, 1 = low stream, 2 = audio only
 */
(function () {
  'use strict';

  /** @type {Set<Object>} live AgoraRTCClient instances created by iris */
  var _clients = new Set();
  var _hooked = false;

  function ensureHook() {
    if (_hooked) return true;
    var ns = window.__ARTC__;
    if (!ns || typeof ns.createClient !== 'function') return false;
    var origCreateClient = ns.createClient;
    ns.createClient = function () {
      var client = origCreateClient.apply(this, arguments);
      try {
        _clients.add(client);
        startStarvationWatch();
        // Each AgoraRoom creates a fresh engine (and therefore a fresh
        // client), so a client that reaches DISCONNECTED after leaving is
        // done for good — drop it to keep the set from growing across
        // breakout-room switches.
        client.on('connection-state-change', function (cur, prev, reason) {
          if (cur === 'DISCONNECTED') _clients.delete(client);
          // Forward to Dart (drives the "Reconnecting…" banner): iris only
          // surfaces terminal disconnects, never RECONNECTING.
          try {
            var cb = window._franklyOnConnectionStateChange;
            if (typeof cb === 'function') cb(cur, reason || '');
          } catch (e) {}
          console.info(
            '[AgoraClientBridge] connection-state ' + prev + ' → ' + cur +
              (reason ? ' (' + reason + ')' : ''));
        });
        // Diagnostics: iris's stream-type-changed handler is an empty stub
        // and stream-fallback only reaches Dart release logs, so these are
        // the one console-visible record of the SDK actually switching
        // streams — the signal QA needs when low selection or weak-network
        // fallback appears inert.
        client.on('stream-type-changed', function (uid, streamType) {
          console.info(
            '[AgoraClientBridge] stream-type-changed uid=' + uid +
              ' type=' + streamType);
          // Log the actually delivered resolution once the switch settles.
          // Event-driven proof that the reported type matches what arrives —
          // webrtc-internals sampling can miss short type windows entirely.
          setTimeout(function () {
            try {
              var users = client.remoteUsers || [];
              for (var i = 0; i < users.length; i++) {
                if (sameUid(users[i].uid, uid) && users[i].videoTrack) {
                  var s =
                    users[i].videoTrack.getMediaStreamTrack().getSettings();
                  // getSettings().frameRate can be Infinity in some browsers
                  // (QA saw "@Infinity"); 0 = unknown.
                  var fps = typeof s.frameRate === 'number' &&
                      isFinite(s.frameRate)
                    ? Math.round(s.frameRate)
                    : 0;
                  console.info(
                    '[AgoraClientBridge] uid=' + uid + ' delivering ' +
                      s.width + 'x' + s.height + '@' + fps + ' (type=' +
                      streamType + ')');
                }
              }
            } catch (e) {
              /* diagnostic only */
            }
          }, 3000);
        });
        client.on('stream-fallback', function (uid, isFallbackOrRecover) {
          console.info(
            '[AgoraClientBridge] stream-fallback uid=' + uid + ' ' +
              isFallbackOrRecover);
        });
      } catch (e) {
        console.warn('[AgoraClientBridge] client capture failed:', e);
      }
      return client;
    };
    _hooked = true;
    console.log('[AgoraClientBridge] createClient hook installed');
    return true;
  }
  ensureHook();

  /**
   * uid comparison tolerant of number/string representation differences
   * between the Dart-passed uid and the SDK's remoteUsers entries.
   */
  function sameUid(a, b) {
    return String(a) === String(b);
  }

  /** Clients that currently see the given remote uid. */
  function clientsWithRemoteUser(uid) {
    var out = [];
    _clients.forEach(function (client) {
      try {
        var users = client.remoteUsers || [];
        for (var i = 0; i < users.length; i++) {
          if (sameUid(users[i].uid, uid)) {
            out.push(client);
            return;
          }
        }
      } catch (e) {
        /* ignore — client may be mid-teardown */
      }
    });
    if (out.length === 0) {
      // Loud on purpose: per-uid calls fail closed (return false) on a miss,
      // which is otherwise invisible in the console.
      var seen = [];
      _clients.forEach(function (client) {
        try {
          (client.remoteUsers || []).forEach(function (u) {
            seen.push(u.uid);
          });
        } catch (e) {}
      });
      console.warn(
        '[AgoraClientBridge] uid ' + uid + ' not visible; remoteUsers: [' +
          seen.join(', ') + ']');
    }
    return out;
  }

  // ─── Remote-video starvation watch ───────────────────────────────────────
  //
  // The SDK's weak-network fallback (setStreamFallbackOption) is entirely
  // server-driven: the client only registers a preference over signaling and
  // waits for on_stream_fallback_update, which QA showed Agora's edge never
  // sends for web subscribers even at 100 Kbps down — the subscription just
  // starves (stats report 0 bitrate, tile freezes). This watch is the
  // client-side replacement for the missing audio-only stage: it detects a
  // subscribed-but-starved remote video and reports it to Dart, which drops
  // that uid's video subscription (avatar + audio) and probes for recovery.
  //
  // Protocol with Dart (window._franklyOnRemoteVideoStarved(uid, starved)):
  //   • starved=true  — uid subscribed and 0 receive bitrate for
  //     STARVE_TRIP_SAMPLES consecutive samples.
  //   • starved=false — uid receiving again after a starved=true.
  //   While Dart holds the subscription muted, the uid has no videoTrack and
  //   its state here is frozen — the reported flag intentionally survives so
  //   the first flowing sample after Dart's probe re-subscribe emits
  //   starved=false. State is dropped only when the uid leaves the channel.

  var STARVE_SAMPLE_MS = 2000;
  var STARVE_TRIP_SAMPLES = 4; // 8s of zero receive while subscribed

  /** @type {Object<string, number>} uid → consecutive starved samples */
  var _starveCounters = {};
  /** @type {Object<string, boolean>} uid → starved state last told to Dart */
  var _starveReported = {};
  var _starveTimer = null;

  function startStarvationWatch() {
    if (_starveTimer) return;
    _starveTimer = setInterval(sampleRemoteVideoStarvation, STARVE_SAMPLE_MS);
  }

  function sampleRemoteVideoStarvation() {
    var cb = window._franklyOnRemoteVideoStarved;
    if (typeof cb !== 'function' || _clients.size === 0) return;
    var present = {};
    _clients.forEach(function (client) {
      var users, stats;
      try {
        users = client.remoteUsers || [];
        stats = client.getRemoteVideoStats() || {};
      } catch (e) {
        return; // client mid-teardown
      }
      for (var i = 0; i < users.length; i++) {
        var u = users[i];
        var key = String(u.uid);
        present[key] = true;
        // hasVideo false = publisher muted; videoTrack null = we are not
        // subscribed (e.g. Dart muted it) — neither is starvation, freeze.
        if (!u.hasVideo || !u.videoTrack) continue;
        var s = stats[u.uid] || stats[key];
        if (!s) continue;
        if ((s.receiveBitrate || 0) === 0) {
          _starveCounters[key] = (_starveCounters[key] || 0) + 1;
          if (_starveCounters[key] >= STARVE_TRIP_SAMPLES &&
              !_starveReported[key]) {
            _starveReported[key] = true;
            console.info(
              '[AgoraClientBridge] uid ' + key + ' video starved (' +
                _starveCounters[key] + ' samples @0 bitrate)');
            try { cb(u.uid, true); } catch (e) {}
          }
        } else {
          _starveCounters[key] = 0;
          if (_starveReported[key]) {
            _starveReported[key] = false;
            console.info(
              '[AgoraClientBridge] uid ' + key + ' video receiving again');
            try { cb(u.uid, false); } catch (e) {}
          }
        }
      }
    });
    // Drop state for uids that left the channel (NOT merely unsubscribed).
    Object.keys(_starveCounters).forEach(function (k) {
      if (!present[k]) delete _starveCounters[k];
    });
    Object.keys(_starveReported).forEach(function (k) {
      if (!present[k]) delete _starveReported[k];
    });
  }

  window.franklyAgoraClientBridgeAvailable = function () {
    return ensureHook();
  };

  /**
   * Subscribes to the high (0) or low (1) quality stream of a remote user.
   * Resolves true when applied on at least one client; false when the uid is
   * not (yet) visible — the caller may retry later.
   */
  window.franklySetRemoteVideoStreamType = async function (uid, streamType) {
    if (!ensureHook()) return false;
    var clients = clientsWithRemoteUser(uid);
    if (clients.length === 0) return false;
    var ok = false;
    for (var client of clients) {
      try {
        await client.setRemoteVideoStreamType(uid, streamType);
        console.info(
          '[AgoraClientBridge] setRemoteVideoStreamType(' + uid + ', ' +
            streamType + ') ok');
        ok = true;
      } catch (e) {
        console.warn(
          '[AgoraClientBridge] setRemoteVideoStreamType(' + uid + ', ' +
            streamType + ') failed:', e);
      }
    }
    return ok;
  };

  /**
   * Sets the weak-network fallback for one remote user:
   * 0 = disabled, 1 = drop to low stream, 2 = low stream then audio-only.
   */
  window.franklySetStreamFallbackOption = async function (uid, option) {
    if (!ensureHook()) return false;
    var clients = clientsWithRemoteUser(uid);
    if (clients.length === 0) return false;
    var ok = false;
    for (var client of clients) {
      try {
        await client.setStreamFallbackOption(uid, option);
        console.info(
          '[AgoraClientBridge] setStreamFallbackOption(' + uid + ', ' +
            option + ') ok');
        ok = true;
      } catch (e) {
        console.warn(
          '[AgoraClientBridge] setStreamFallbackOption(' + uid + ', ' +
            option + ') failed:', e);
      }
    }
    return ok;
  };

  /** Default stream type (0 high / 1 low) for future subscriptions. */
  window.franklySetRemoteDefaultVideoStreamType = async function (streamType) {
    if (!ensureHook()) return false;
    var ok = false;
    for (var client of _clients) {
      try {
        await client.setRemoteDefaultVideoStreamType(streamType);
        ok = true;
      } catch (e) {
        console.warn(
          '[AgoraClientBridge] setRemoteDefaultVideoStreamType(' + streamType +
            ') failed:', e);
      }
    }
    return ok;
  };

  /**
   * Publishes the low (simulcast) stream alongside the camera stream, with
   * the given parameters (bitrate in Kbps). iris-web stubs every
   * enableDualStreamMode variant, and its internal client.enableDualStream
   * path is unreachable dead code (nothing populates enabledDualStreamModes)
   * with a broken config translation (bitrate := framerate) — so Dart
   * activates dual-stream here instead.
   */
  window.franklyEnableDualStream = async function (
    width, height, framerate, bitrate) {
    if (!ensureHook()) return false;
    var ok = false;
    for (var client of _clients) {
      try {
        client.setLowStreamParameter({
          width: width,
          height: height,
          framerate: framerate,
          bitrate: bitrate,
        });
        await client.enableDualStream();
        console.info('[AgoraClientBridge] enableDualStream ok (' + width +
          'x' + height + '@' + framerate + ', ' + bitrate + ' Kbps low)');
        ok = true;
      } catch (e) {
        // Double enable surfaces as INVALID_OPERATION — dual stream is on.
        if (e && e.code === 'INVALID_OPERATION') {
          ok = true;
        } else {
          console.warn('[AgoraClientBridge] enableDualStream failed:', e);
        }
      }
    }
    return ok;
  };

  /** Stops publishing the low stream (canvas compositor owns the senders). */
  window.franklyDisableDualStream = async function () {
    if (!ensureHook()) return false;
    var ok = false;
    for (var client of _clients) {
      try {
        await client.disableDualStream();
        ok = true;
      } catch (e) {
        if (e && e.code === 'INVALID_OPERATION') {
          ok = true; // already disabled
        } else {
          console.warn('[AgoraClientBridge] disableDualStream failed:', e);
        }
      }
    }
    return ok;
  };

  /**
   * Renews the channel token on every live client. iris-web stubs the
   * engine-level renewToken, but the web client implements it — without
   * renewal, the SDK's automatic reconnect re-joins with the original
   * (possibly expired) token and gets rejected.
   */
  window.franklyRenewToken = async function (token) {
    if (!ensureHook()) return false;
    var ok = false;
    for (var client of _clients) {
      try {
        await client.renewToken(token);
        console.info('[AgoraClientBridge] renewToken ok');
        ok = true;
      } catch (e) {
        console.warn('[AgoraClientBridge] renewToken failed:', e);
      }
    }
    return ok;
  };

  // ─── Wake lock + page visibility (meeting-scoped, no SDK hook needed) ───

  /** @type {WakeLockSentinel|null} */
  var _wakeLock = null;
  var _wantWakeLock = false;

  async function acquireWakeLock() {
    if (!navigator.wakeLock || typeof navigator.wakeLock.request !== 'function') {
      return false;
    }
    try {
      _wakeLock = await navigator.wakeLock.request('screen');
      _wakeLock.addEventListener('release', function () {
        _wakeLock = null;
      });
      console.info('[AgoraClientBridge] wake lock acquired');
      return true;
    } catch (e) {
      // NotAllowedError when backgrounded / low battery — benign.
      _wakeLock = null;
      return false;
    }
  }

  /**
   * Keeps the screen awake while in a meeting (phones lock mid-meeting for
   * listen-only participants, killing their A/V). Auto re-acquires on return
   * to foreground; unsupported browsers report false and nothing breaks.
   */
  window.franklySetWakeLock = async function (enable) {
    _wantWakeLock = !!enable;
    if (!_wantWakeLock) {
      if (_wakeLock) {
        try { await _wakeLock.release(); } catch (e) {}
        _wakeLock = null;
      }
      return true;
    }
    return acquireWakeLock();
  };

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState !== 'visible') return;
    // Wake locks auto-release when the page is hidden; re-acquire.
    if (_wantWakeLock && !_wakeLock) acquireWakeLock();
    try {
      var cb = window._franklyOnPageVisible;
      if (typeof cb === 'function') cb();
    } catch (e) {}
  });

  /**
   * Encoder degradation preference for currently published local video
   * tracks: 'motion' | 'detail' | 'balanced'. iris-web drops
   * degradationPreference when translating VideoEncoderConfiguration;
   * 'motion' is the web equivalent of maintainFramerate. Call after the
   * camera is publishing — it does not persist to future tracks.
   */
  window.franklySetLocalVideoOptimizationMode = async function (mode) {
    if (!ensureHook()) return false;
    var ok = false;
    for (var client of _clients) {
      var tracks;
      try {
        tracks = client.localTracks || [];
      } catch (e) {
        continue; // client mid-teardown
      }
      for (var track of tracks) {
        try {
          if (track.trackMediaType === 'video' &&
              typeof track.setOptimizationMode === 'function') {
            await track.setOptimizationMode(mode);
            ok = true;
          }
        } catch (e) {
          console.warn('[AgoraClientBridge] setOptimizationMode failed:', e);
        }
      }
    }
    return ok;
  };
})();
