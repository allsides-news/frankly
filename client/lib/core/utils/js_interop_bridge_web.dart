import 'dart:js_interop';
import 'dart:js_interop_unsafe';

// Legacy `JsObject.callMethod` expects dart:js_util `allowInterop` wrappers — not
// dart:js_interop `.toJS` — or callbacks may not reach JS as real functions.
// ignore: deprecated_member_use
import 'dart:js_util' as js_util show allowInterop;

// ─── Canvas compositor JS bindings ──────────────────────────────────────────

@JS('startCanvasScreenShare')
external JSPromise _jsStartCanvasScreenShare(JSAny? cameraDeviceId);

@JS('stopCanvasScreenShare')
external JSPromise _jsStopCanvasScreenShare();

@JS('isCanvasCompositorSupported')
external JSBoolean _jsIsCanvasCompositorSupported();

@JS('isActualMobileDevice')
external JSBoolean _jsIsActualMobileDevice();

@JS('isCanvasScreenShareActive')
external JSBoolean _jsIsCanvasScreenShareActive();

@JS('getCanvasCompositorPixelSize')
external JSAny? _jsGetCanvasCompositorPixelSize();

/// Starts the canvas compositor screen share.
/// Returns:
///   true  — started successfully
///   null  — user dismissed/cancelled the screen picker (silent, no error)
///   false — actual failure (permission denied at OS level, API error, etc.)
Future<bool?> jsStartCanvasScreenShare(String? cameraDeviceId) async {
  final result = await _jsStartCanvasScreenShare(cameraDeviceId?.toJS).toDart;
  final val = result?.dartify();
  if (val == true) return true;
  if (val == null) return null; // user cancelled
  return false;
}

/// Stops the canvas compositor and restores the original video sender track.
Future<void> jsStopCanvasScreenShare() =>
    _jsStopCanvasScreenShare().toDart.then((_) {});

/// Returns true when running on an actual mobile phone (UA-based, not viewport).
/// Use this to block the screen-share start button on handsets while still
/// allowing it on narrow desktop windows.
bool jsIsActualMobileDevice() => _jsIsActualMobileDevice().toDart;

/// Returns true when all APIs required by the canvas compositor are available
/// in the current browser (getDisplayMedia + canvas.captureStream).
/// Use this to gate the "Share Screen" button rather than the raw
/// getDisplayMedia check, so Safari <16.4 and iOS never see the option.
bool jsIsCanvasCompositorSupported() => _jsIsCanvasCompositorSupported().toDart;

/// True when this client can start screen share (compositor APIs + not a phone).
bool jsCanInitiateScreenShare() =>
    jsIsCanvasCompositorSupported() && !jsIsActualMobileDevice();

/// Returns true if the canvas compositor is currently running.
bool jsIsCanvasScreenShareActive() => _jsIsCanvasScreenShareActive().toDart;

/// Canvas backing-store width/height in pixels while compositing, or null.
List<int>? jsGetCanvasCompositorPixelSize() {
  final raw = _jsGetCanvasCompositorPixelSize();
  if (raw == null) return null;
  final v = raw.dartify();
  if (v is! List || v.length < 2) return null;
  final w = v[0];
  final h = v[1];
  if (w is! num || h is! num) return null;
  final wi = w.round();
  final hi = h.round();
  if (wi <= 0 || hi <= 0) return null;
  return [wi, hi];
}

/// Registers a Dart callback that fires when the user stops sharing via the
/// browser's native "Stop sharing" button (i.e. the screenTrack 'ended' event).
void jsSetCanvasScreenShareStoppedCallback(void Function() callback) {
  globalContext['_onCanvasScreenShareStopped'] = jsInteropVoid(callback);
}

// ─── Agora client bridge (agora_client_bridge.js) ────────────────────────────
// Subscriber-side quality APIs that iris-web stubs out but the underlying
// Agora Web SDK client implements. Integer values match the native SDK enums
// (VideoStreamType / StreamFallbackOptions).

@JS('franklyAgoraClientBridgeAvailable')
external JSBoolean _jsFranklyAgoraClientBridgeAvailable();

@JS('franklySetRemoteVideoStreamType')
external JSPromise _jsFranklySetRemoteVideoStreamType(
  JSNumber uid,
  JSNumber streamType,
);

@JS('franklySetStreamFallbackOption')
external JSPromise _jsFranklySetStreamFallbackOption(
  JSNumber uid,
  JSNumber option,
);

@JS('franklySetRemoteDefaultVideoStreamType')
external JSPromise _jsFranklySetRemoteDefaultVideoStreamType(
  JSNumber streamType,
);

@JS('franklyEnableDualStream')
external JSPromise _jsFranklyEnableDualStream(
  JSNumber width,
  JSNumber height,
  JSNumber framerate,
  JSNumber bitrateKbps,
);

@JS('franklyDisableDualStream')
external JSPromise _jsFranklyDisableDualStream();

@JS('franklySetLocalVideoOptimizationMode')
external JSPromise _jsFranklySetLocalVideoOptimizationMode(JSString mode);

@JS('franklyRenewToken')
external JSPromise _jsFranklyRenewToken(JSString token);

@JS('franklySetWakeLock')
external JSPromise _jsFranklySetWakeLock(JSBoolean enable);

/// True when agora_client_bridge.js is loaded and has hooked the Agora Web
/// SDK namespace. When false, dual-stream subscriber features are
/// unavailable on web and callers should skip them.
bool jsAgoraClientBridgeAvailable() {
  if (!globalContext
      .hasProperty('franklyAgoraClientBridgeAvailable'.toJS)
      .toDart) {
    return false;
  }
  try {
    return _jsFranklyAgoraClientBridgeAvailable().toDart;
  } catch (_) {
    return false;
  }
}

/// Subscribes to the high (0) / low (1) stream of [uid]. Returns false when
/// the uid is not yet visible to the client (caller may retry).
Future<bool> jsSetRemoteVideoStreamType(int uid, int streamType) async {
  final result =
      await _jsFranklySetRemoteVideoStreamType(uid.toJS, streamType.toJS)
          .toDart;
  return result.dartify() == true;
}

/// Weak-network fallback for [uid]: 0 disabled, 1 low stream, 2 audio-only.
Future<bool> jsSetStreamFallbackOption(int uid, int option) async {
  final result =
      await _jsFranklySetStreamFallbackOption(uid.toJS, option.toJS).toDart;
  return result.dartify() == true;
}

/// Default stream type (0 high / 1 low) for future remote subscriptions.
Future<bool> jsSetRemoteDefaultVideoStreamType(int streamType) async {
  final result =
      await _jsFranklySetRemoteDefaultVideoStreamType(streamType.toJS).toDart;
  return result.dartify() == true;
}

/// Publishes the low (simulcast) stream with the given parameters.
/// Returns false when the bridge is unavailable or the browser does not
/// support dual-stream.
Future<bool> jsEnableDualStream({
  required int width,
  required int height,
  required int framerate,
  required int bitrateKbps,
}) async {
  final result = await _jsFranklyEnableDualStream(
    width.toJS,
    height.toJS,
    framerate.toJS,
    bitrateKbps.toJS,
  ).toDart;
  return result.dartify() == true;
}

/// Stops publishing the low (simulcast) stream.
Future<bool> jsDisableDualStream() async {
  final result = await _jsFranklyDisableDualStream().toDart;
  return result.dartify() == true;
}

/// Degradation preference for currently published local video tracks:
/// 'motion' (maintain framerate) | 'detail' | 'balanced'. Only affects
/// tracks that are publishing when called.
Future<bool> jsSetLocalVideoOptimizationMode(String mode) async {
  final result =
      await _jsFranklySetLocalVideoOptimizationMode(mode.toJS).toDart;
  return result.dartify() == true;
}

/// Renews the Agora channel token on the live web client(s). The engine
/// API is stubbed by iris-web; this is the only renewal path on web.
Future<bool> jsRenewToken(String token) async {
  final result = await _jsFranklyRenewToken(token.toJS).toDart;
  return result.dartify() == true;
}

/// Keeps the screen awake while enabled (auto re-acquires on foreground).
/// Returns false when Wake Lock is unsupported or denied — safe to ignore.
Future<bool> jsSetWakeLock(bool enable) async {
  if (!globalContext.hasProperty('franklySetWakeLock'.toJS).toDart) {
    return false;
  }
  final result = await _jsFranklySetWakeLock(enable.toJS).toDart;
  return result.dartify() == true;
}

/// Registers a callback for Agora client connection-state transitions
/// (state, reason) — e.g. ('RECONNECTING', ''), ('CONNECTED', '').
void jsSetAgoraConnectionStateCallback(
  void Function(String state, String reason) callback,
) {
  globalContext['_franklyOnConnectionStateChange'] = jsInteropDynamicPair(
    (a, b) => callback(a?.toString() ?? '', b?.toString() ?? ''),
  ) as JSAny?;
}

/// Registers a callback fired when the page returns to the foreground.
void jsSetPageVisibleCallback(void Function() callback) {
  globalContext['_franklyOnPageVisible'] = jsInteropVoid(callback);
}

/// Registers a callback for the bridge's remote-video starvation watch:
/// starved=true when [uid]'s subscribed video has received nothing for a
/// sustained period, starved=false when it is receiving again. Drives the
/// client-side audio-only fallback (Agora's server-driven fallback never
/// fires for web subscribers).
void jsSetRemoteVideoStarvedCallback(
  void Function(int uid, bool starved) callback,
) {
  globalContext['_franklyOnRemoteVideoStarved'] = jsInteropDynamicPair(
    (a, b) {
      final uid =
          a is num ? a.toInt() : int.tryParse(a?.toString() ?? '') ?? -1;
      if (uid < 0) return;
      callback(uid, b == true);
    },
  ) as JSAny?;
}

@JS('getCanvasShareLabel')
external JSString? _jsGetCanvasShareLabel();

/// Returns a human-readable label for what is currently being shared, e.g.
/// "Full Screen", "Browser Tab · Gmail", "Window · Figma".
/// Returns null when the canvas compositor is not active.
String? jsGetCanvasShareLabel() => _jsGetCanvasShareLabel()?.toDart;

// Thin bridge uses dart:js_interop (not dart:js_util). Generic JS callbacks use jsInteropVoid /
// jsInteropDynamicPair — Function.toJS requires a statically known signature.

// VM/mobile analysis parses web-only SDK URIs without a browser compile target.
// ignore_for_file: uri_does_not_exist, avoid_web_libraries_in_flutter

/// Same sentinel as Flutter [kIsWasm] (`dart.tool.dart2wasm`); avoids a
/// Flutter dependency in this barrel.
const bool _kDart2wasm = bool.fromEnvironment('dart.tool.dart2wasm');

JSAny? jsInteropVoid(void Function() f) => f.toJS;

/// Wrap [f] for legacy `JsObject.callMethod` / universal_html `context.callMethod`.
dynamic legacyJsAllowInteropVoid(void Function() f) => js_util.allowInterop(f);

dynamic jsInteropDynamicPair(void Function(dynamic a, dynamic b) f) {
  void bridge(JSAny? a, JSAny? b) {
    f(a.dartify(), b.dartify());
  }

  return bridge.toJS;
}

bool jsHasProperty(Object o, Object name) {
  // Cast is OK on dart2js: dart:html / universal_html wrappers share the JS
  // representation with dart:js_interop JSObject views. Wasm compiles do not;
  // fail fast until call sites use package:web (or equivalent) handles.
  if (_kDart2wasm) {
    throw UnsupportedError(
      'jsHasProperty: dart:html Object → JSObject is not supported on dart2wasm; '
      'refactor to package:web interop or a wasm-specific bridge.',
    );
  }
  final obj = o as JSObject;
  return obj.hasProperty((name as String).toJS).toDart;
}

/// Returns the raw [JSAny?] from the method call so JS-object results can be
/// passed back as method receivers. Call [dartify] when you need a Dart value.
///
/// Arguments must already be JS values: string/number `.toJS`, plain maps via
/// [jsJsify], and DOM/native handles via an explicit interop cast (do not pass
/// arbitrary Dart objects through generic jsify helpers).
JSAny? jsCallMethod(JSAny? receiver, Object method, List<JSAny?> args) {
  final obj = receiver as JSObject;
  final jsMethod = (method as String).toJS;
  return obj.callMethodVarArgs(jsMethod, args);
}

JSAny? jsJsify(Object? object) => object.jsify();
