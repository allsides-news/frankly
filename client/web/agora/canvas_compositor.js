/**
 * Canvas compositor for web screen sharing.
 *
 * Replaces the broken iris-web single-engine publishScreenCaptureVideo path.
 *
 * Architecture:
 *   1. getDisplayMedia()  → screenTrack
 *   2. getUserMedia()     → cameraPipTrack (optional PiP)
 *   3. <canvas> 1280×720  requestAnimationFrame loop:
 *        ctx.drawImage(screenVideo,  0,    0,    1280, 720)  // screen fills canvas
 *        ctx.drawImage(cameraVideo,  1080, 540,  200,  150)  // camera PiP, bottom-right
 *   4. canvas.captureStream(30) → mixedTrack
 *   5. RTCRtpSender.replaceTrack(mixedTrack) on the Agora peer connection video sender.
 *      The original sender track is saved and restored on stop.
 *
 * Dart calls window.startCanvasScreenShare(cameraDeviceId?) → Promise<bool>
 *                window.stopCanvasScreenShare()              → Promise<void>
 *                window.isCanvasScreenShareActive()          → bool
 *
 * When the user stops sharing via the browser's native UI (clicking the
 * "Stop sharing" button), stopCanvasScreenShare finishes cleanup then invokes
 * window._onCanvasScreenShareStopped — the Dart layer registers this before start.
 *
 * Peer-connection tracking: window._franklyPeerConnections (a Set) is
 * populated by an inline script in index.html that monkey-patches
 * RTCPeerConnection before iris-web-rtc.js runs.
 */
(function () {
  'use strict';

  /** @type {{ screenTrack: MediaStreamTrack, cameraPipTrack: MediaStreamTrack|null,
   *           rafId: number, screenVideo: HTMLVideoElement,
   *           cameraVideo: HTMLVideoElement|null, mixedTrack: MediaStreamTrack,
   *           savedSenders: Array<{sender: RTCRtpSender, track: MediaStreamTrack|null}> }|null} */
  var _state = null;

  // Canvas defaults (overridden per-session once we know the captured resolution).
  var W = 1280, H = 720;
  // PiP is 20% of canvas width with 4:3 aspect ratio so it scales naturally
  // at any captured resolution.  Position is recalculated in startCanvasScreenShare
  // after canvas dimensions are known.
  var PIP_W = 200, PIP_H = 150, PIP_X = W - PIP_W - 16, PIP_Y = H - PIP_H - 16;

  function _recalcPip() {
    var marginX = Math.max(12, Math.round(W * 0.012));
    var marginY = Math.max(12, Math.round(H * 0.015));
    var targetW = Math.round(W * 0.20);
    var maxPipW = 288;
    var minPipW = 96;
    PIP_W = Math.min(maxPipW, Math.max(minPipW, targetW));
    if (PIP_W > W - marginX - 8) {
      PIP_W = Math.max(64, W - marginX - 8);
    }
    PIP_H = Math.round(PIP_W * 0.75);
    if (PIP_H > H - marginY - 8) {
      PIP_H = Math.max(48, H - marginY - 8);
      PIP_W = Math.round(PIP_H / 0.75);
    }
    PIP_X = Math.max(0, W - PIP_W - marginX);
    PIP_Y = Math.max(0, H - PIP_H - marginY);
  }

  /** Center-crop camera into dst (like object-fit:cover) — avoids squash/stretch. */
  function drawCameraPip(ctx, video, dx, dy, dw, dh) {
    var vw = video.videoWidth;
    var vh = video.videoHeight;
    if (!vw || !vh) return;
    var dstAspect = dw / dh;
    var srcAspect = vw / vh;
    var sx, sy, sw, sh;
    if (srcAspect > dstAspect) {
      sh = vh;
      sw = Math.round(vh * dstAspect);
      sx = Math.round((vw - sw) / 2);
      sy = 0;
    } else {
      sw = vw;
      sh = Math.round(vw / dstAspect);
      sx = 0;
      sy = Math.round((vh - sh) / 2);
    }
    ctx.drawImage(video, sx, sy, sw, sh, dx, dy, dw, dh);
  }

  /** Creates an offscreen <video> element and starts playing a MediaStream. */
  function makeVideoEl(stream) {
    var v = document.createElement('video');
    v.srcObject = stream;
    v.muted = true;
    v.autoplay = true;
    v.playsInline = true;
    v.play().catch(function () {});
    return v;
  }

  /**
   * Returns true when all APIs required by the canvas compositor are present:
   *   • navigator.mediaDevices.getDisplayMedia  (all modern browsers)
   *   • HTMLCanvasElement.captureStream          (Chrome 51+, Firefox 43+,
   *                                              Safari 16.4+, Edge 79+)
   *
   * Notably absent in Safari < 16.4 and all iOS browsers (Apple's WebKit
   * restriction).  Use this to hide the screen-share option rather than
   * letting the compositor fail at runtime.
   */
  window.isCanvasCompositorSupported = function () {
    try {
      var testCanvas = document.createElement('canvas');
      return !!(
        navigator.mediaDevices &&
        typeof navigator.mediaDevices.getDisplayMedia === 'function' &&
        typeof testCanvas.captureStream === 'function'
      );
    } catch (_) {
      return false;
    }
  };

  /**
   * Returns true when running on an actual mobile phone (Android or iOS),
   * regardless of viewport width.  Used to block the screen-share start button
   * on handsets while still allowing it on narrow desktop browser windows.
   * iOS is also gated by isCanvasCompositorSupported() returning false (no
   * getDisplayMedia), but this provides an explicit belt-and-suspenders check.
   */
  window.isActualMobileDevice = function () {
    // Android phones: getDisplayMedia throws NotAllowedError at call time.
    // Tablets omit "Mobile" in the UA and can share on Android 13+ / Chrome 113+.
    return /Android.*Mobile|iPhone|iPod|IEMobile|Opera Mini/i.test(
      navigator.userAgent,
    );
  };

  window.startCanvasScreenShare = async function (cameraDeviceId) {
    if (_state) {
      console.warn('[CanvasCompositor] already active, ignoring start');
      return false;
    }
    // Fresh defaults so a prior session's resolution never feeds the first
    // _recalcPip() before this session's capture dimensions are known.
    W = 1280;
    H = 720;
    _recalcPip();
    // Hard guard: fail fast on browsers that lack captureStream.
    if (!window.isCanvasCompositorSupported()) {
      console.warn('[CanvasCompositor] not supported in this browser');
      return false;
    }

    // ── 1. Capture screen ────────────────────────────────────────────────────
    var screenStream;
    try {
      // No width/height constraint: capture at native screen resolution so
      // the canvas matches the actual content (avoids the "half screen" crop
      // seen when sharing a non-16:9 or high-DPI surface).
      screenStream = await navigator.mediaDevices.getDisplayMedia({
        video: { frameRate: 30, cursor: 'always' },
        audio: false,
      });
    } catch (e) {
      // NotAllowedError / AbortError = user pressed Cancel — return null so
      // Dart can distinguish "silent cancel" from a real failure.
      if (e && (e.name === 'NotAllowedError' || e.name === 'AbortError' ||
                e.name === 'InvalidStateError')) {
        console.log('[CanvasCompositor] user cancelled screen picker');
        return null;
      }
      console.error('[CanvasCompositor] getDisplayMedia failed:', e);
      return false;
    }
    var screenTrack = screenStream.getVideoTracks()[0];

    // ── 2. Camera track for PiP ───────────────────────────────────────────────
    // Prefer the track already held by the Agora video sender to avoid opening
    // a second capture session on the same device (doubles OS camera indicator,
    // may degrade frame rate).  Fall back to getUserMedia if none is found.
    var cameraPipTrack = null;
    var cameraVideo = null;
    var ownsCameraPipTrack = false; // true only when we opened it via getUserMedia
    (function () {
      var pcs = window._franklyPeerConnections || new Set();
      for (var pc of pcs) {
        for (var sender of pc.getSenders()) {
          if (sender.track && sender.track.kind === 'video' &&
              sender.track.readyState === 'live') {
            cameraPipTrack = sender.track;
            break;
          }
        }
        if (cameraPipTrack) break;
      }
    })();
    if (cameraPipTrack) {
      cameraVideo = makeVideoEl(new MediaStream([cameraPipTrack]));
    } else {
      try {
        var camConstraints = cameraDeviceId
          ? { video: { deviceId: { ideal: cameraDeviceId }, width: 320, height: 240 } }
          : { video: { width: 320, height: 240 } };
        var camStream = await navigator.mediaDevices.getUserMedia(camConstraints);
        cameraPipTrack = camStream.getVideoTracks()[0];
        cameraVideo = makeVideoEl(camStream);
        ownsCameraPipTrack = true;
      } catch (e) {
        console.log('[CanvasCompositor] Camera PiP unavailable:', e);
      }
    }

    // ── 3. Canvas + preview video element ─────────────────────────────────────
    // Size the canvas to the actual captured resolution so content is never
    // cropped or letterboxed.  Fall back to 1280×720 if getSettings() is
    // unavailable (older Safari).
    var captureSettings = {};
    try { captureSettings = screenTrack.getSettings(); } catch (_) {}
    W = captureSettings.width  || W;
    H = captureSettings.height || H;
    _recalcPip();

    var canvas = document.createElement('canvas');
    canvas.id = 'canvas-compositor-preview'; // Flutter HtmlElementView finds it by this ID
    canvas.width = W;
    canvas.height = H;
    canvas.style.cssText =
      'position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;visibility:hidden;';
    document.body.appendChild(canvas); // must be in DOM for getElementById

    var ctx = canvas.getContext('2d');

    var screenVideo = makeVideoEl(screenStream);

    function applyVideoDimsToCanvas() {
      var vw = screenVideo.videoWidth;
      var vh = screenVideo.videoHeight;
      if (!vw || !vh) return false;
      canvas.width = vw;
      canvas.height = vh;
      W = vw;
      H = vh;
      _recalcPip();
      return true;
    }

    // Wait for decoded dimensions before captureStream so the track matches the
    // real capture aspect (getSettings() alone can be wrong vs videoWidth/Height).
    await new Promise(function (resolve) {
      var done = false;
      function finish() {
        if (done) return;
        done = true;
        resolve();
      }
      var deadlineMs = 900;
      var deadline = Date.now() + deadlineMs;
      function attempt() {
        if (applyVideoDimsToCanvas()) {
          finish();
          return;
        }
        if (Date.now() >= deadline) {
          finish();
          return;
        }
        requestAnimationFrame(attempt);
      }
      screenVideo.addEventListener('loadedmetadata', attempt);
      attempt();
    });

    // ── 4. Canvas stream ──────────────────────────────────────────────────────
    var mixedStream = canvas.captureStream(30);
    var mixedTrack = mixedStream.getVideoTracks()[0];

    // ── 5. Runtime state + RAF ─────────────────────────────────────────────────
    // Commit _state before the RAF loop so draw() can bail when stop clears it.
    // assign _state.rafId each frame so cancelAnimationFrame in stop is not stale.
    _state = {
      screenTrack: screenTrack,
      cameraPipTrack: cameraPipTrack,
      ownsCameraPipTrack: ownsCameraPipTrack,
      rafId: null,
      screenVideo: screenVideo,
      cameraVideo: cameraVideo,
      canvas: canvas,
      mixedTrack: mixedTrack,
      savedSenders: [],
    };

    // Browser-native "Stop sharing": register before collectAndReplace so 'ended'
    // during the retry window is never missed.
    screenTrack.addEventListener('ended', async function () {
      await window.stopCanvasScreenShare();
    });

    screenVideo.addEventListener('resize', function () {
      if (!_state) return;
      applyVideoDimsToCanvas();
    });

    function draw() {
      if (!_state) return;
      if (screenVideo.readyState >= 2) {
        ctx.drawImage(screenVideo, 0, 0, W, H);
      } else {
        ctx.fillStyle = '#111';
        ctx.fillRect(0, 0, W, H);
      }
      if (cameraVideo && cameraVideo.readyState >= 2) {
        drawCameraPip(ctx, cameraVideo, PIP_X, PIP_Y, PIP_W, PIP_H);
      }
      _state.rafId = requestAnimationFrame(draw);
    }
    draw();

    // ── 6. Replace video sender tracks ────────────────────────────────────────
    // collectAndReplace may await (retry window); 'ended' may stop mid-await.
    // Agora's web SDK may report updateChannelMediaOptions complete before
    // addTrack/renegotiation has created the RTCRtpSender. Retry over ~3s to
    // cover that window: it is widest when the camera was off at start AND
    // renegotiation is slow — the main room (many transceivers) plus the
    // just-issued disableDualStream renegotiation. QA hit start failures in
    // the main room with the previous single 300 ms retry.
    async function collectAndReplace(retries) {
      if (!_state) return 0;
      var count = 0;
      var pcs = window._franklyPeerConnections || new Set();
      for (var pc of pcs) {
        if (!_state) return count;
        try {
          for (var sender of pc.getSenders()) {
            if (!_state) return count;
            if (sender.track && sender.track.kind === 'video') {
              if (sender.track === mixedTrack) {
                count++;
                continue;
              }
              var alreadySaved = _state.savedSenders.some(function (e) {
                return e.sender === sender;
              });
              if (!alreadySaved) {
                _state.savedSenders.push({ sender: sender, track: sender.track });
              }
              await sender.replaceTrack(mixedTrack);
              if (!_state) return count;
              console.log('[CanvasCompositor] replaced video sender track');
              count++;
            }
          }
        } catch (e) {
          console.warn('[CanvasCompositor] replaceTrack error:', e);
        }
      }
      if (count === 0 && retries > 0 && _state) {
        await new Promise(function (r) { setTimeout(r, 300); });
        if (!_state) return 0;
        return collectAndReplace(retries - 1);
      }
      return count;
    }
    var replacedCount = await collectAndReplace(10);

    // Native stop ran during startup — stopCanvasScreenShare cleared _state.
    if (!_state) {
      return null;
    }

    // Guard: if no sender was found even after the retries, fail visibly —
    // with a sender inventory so the next QA round can pin down WHY (closed
    // pc? sender without track? track ended?).
    if (replacedCount === 0) {
      var inventory = [];
      (window._franklyPeerConnections || new Set()).forEach(function (pc) {
        try {
          var senders = pc.getSenders().map(function (sn) {
            return sn.track
              ? sn.track.kind + ':' + sn.track.readyState
              : 'no-track';
          });
          inventory.push(
            pc.connectionState + '[' + senders.join(',') + ']');
        } catch (e) {
          inventory.push('unreadable(' + e + ')');
        }
      });
      await window.stopCanvasScreenShare({ suppressDartCallback: true });
      console.error(
        '[CanvasCompositor] no video sender found — is Agora connected? ' +
          'pcs: ' + (inventory.join(' ') || 'none'));
      return false;
    }

    console.log('[CanvasCompositor] started; senders replaced:', replacedCount);
    return true;
  };

  /**
   * @param {{ suppressDartCallback?: boolean }} [opts]
   *   suppressDartCallback — when true, do not invoke _onCanvasScreenShareStopped
   *   (used when startup fails before sharing was actually active).
   */
  window.stopCanvasScreenShare = async function (opts) {
    opts = opts || {};
    var suppressDartCallback = opts.suppressDartCallback === true;
    if (!_state) return;
    var s = _state;
    _state = null;
    var cb = suppressDartCallback ? null : window._onCanvasScreenShareStopped;
    window._onCanvasScreenShareStopped = null;

    if (s.rafId != null) cancelAnimationFrame(s.rafId);

    try {
      if (s.screenVideo) s.screenVideo.srcObject = null;
      if (s.cameraVideo) s.cameraVideo.srcObject = null;
    } catch (e) {}

    // Restore original sender tracks.
    // KNOWN ISSUE (pre-existing, also on prod): after stop — especially via
    // the browser's native "Stop sharing" — webrtc-internals can show the
    // share's outbound-rtp still active. Sharing does end for everyone
    // (Firestore state + this restore), so the impact is wasted uplink only;
    // deliberately not chased as part of the slow-network work.
    for (var entry of s.savedSenders) {
      try {
        await entry.sender.replaceTrack(entry.track);
      } catch (e) {
        console.warn('[CanvasCompositor] restore replaceTrack error:', e);
      }
    }

    // Stop all captured tracks — but only stop the camera track if we opened it
    // via getUserMedia; Agora-owned tracks must not be stopped here.
    s.screenTrack.stop();
    if (s.cameraPipTrack && s.ownsCameraPipTrack) s.cameraPipTrack.stop();
    s.mixedTrack.stop();

    // Remove preview canvas from DOM
    var previewEl = document.getElementById('canvas-compositor-preview');
    if (previewEl) previewEl.remove();

    console.log('[CanvasCompositor] stopped');
    if (typeof cb === 'function') {
      try {
        cb();
      } catch (e) {
        console.warn('[CanvasCompositor] _onCanvasScreenShareStopped error:', e);
      }
    }
  };

  window.isCanvasScreenShareActive = function () {
    return !!_state;
  };

  /** @returns {number[]|null} [width,height] bitmap pixels, or null if inactive */
  window.getCanvasCompositorPixelSize = function () {
    if (!_state || !_state.canvas) return null;
    var w = _state.canvas.width;
    var h = _state.canvas.height;
    if (!w || !h) return null;
    return [w, h];
  };

  /**
   * Returns a human-readable label describing what is being shared.
   * Uses MediaStreamTrack.getSettings().displaySurface when available,
   * falling back to the track label string.
   *
   * Possible return values (examples):
   *   "Full Screen"         – entire monitor
   *   "Browser Tab"         – a browser tab (no title available in most browsers)
   *   "Chrome Tab · Gmail"  – if the label contains a meaningful title
   *   "Window · Figma"      – application window
   *   "Screen"              – unknown / unsupported browser
   */
  window.getCanvasShareLabel = function () {
    if (!_state) return null;
    return _describeTrack(_state.screenTrack);
  };

  /**
   * Extracts a human-readable name from a getDisplayMedia video track.
   *
   * Returns a two-part object: { type, detail } where:
   *   type   — "Full Screen" | "Browser Tab" | "Window" | "Screen"
   *   detail — app/tab name when the browser exposes it, otherwise ''
   *
   * displaySurface is the reliable API (Chrome 107+, Firefox, Edge).
   * The track label is browser/OS-specific:
   *   Chrome macOS  — usually empty (privacy)
   *   Firefox       — often contains window title
   *   Edge          — similar to Chrome
   */
  function _getTrackInfo(track) {
    var settings = {};
    try { settings = track.getSettings(); } catch (_) {}

    var surface = settings.displaySurface || '';   // 'monitor'|'browser'|'window'|''
    var rawLabel = (track.label || '').trim();

    // Internal Chrome/Edge URI patterns — never user-facing.
    // Firefox and Windows Chrome often return real human-readable names.
    var internalPattern = /^(web-contents-media-stream:\/\/|screen:\d|window:\d+|0:\d)/;
    var isInternal = internalPattern.test(rawLabel);
    var detail = isInternal ? '' : rawLabel;

    // Infer surface from label when displaySurface is not available.
    if (!surface) {
      if (/^screen:\d/.test(rawLabel) || /screen\s*\d/i.test(rawLabel) ||
          rawLabel.toLowerCase() === 'entire screen') {
        surface = 'monitor';
      } else if (rawLabel.startsWith('web-contents-media-stream://') ||
                 rawLabel.toLowerCase().includes(' tab')) {
        surface = 'browser';
      } else if (/^window:\d/.test(rawLabel)) {
        surface = 'window';
      }
    }

    // Browser-specific notes:
    //   Chrome macOS  – label is empty (privacy); displaySurface is set
    //   Chrome Windows – label has window title for 'window' surface
    //   Firefox (all)  – label has window/tab title; displaySurface is set
    //   Safari 16.4+   – displaySurface is set; label varies by OS
    //   Edge           – behaves like Chrome Windows

    var type;
    switch (surface) {
      case 'monitor': type = 'Full Screen';  break;
      case 'browser': type = 'Browser Tab'; break;
      case 'window':  type = 'Window';      break;
      default:        type = detail ? 'Window' : 'Screen'; break;
    }

    return { type: type, detail: detail };
  }

  function _describeTrack(track) {
    var info = _getTrackInfo(track);
    return info.detail ? info.type + ' · ' + info.detail : info.type;
  }
})();
