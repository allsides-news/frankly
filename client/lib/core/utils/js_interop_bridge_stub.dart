/// Non-web analysis / VM: web-only widgets should not hit these paths at runtime.
import 'dart:js_interop';

JSAny? jsInteropVoid(void Function() f) => null;

// Canvas compositor stubs (non-web).
bool jsIsActualMobileDevice() => false;
bool jsIsCanvasCompositorSupported() => false;
bool jsCanInitiateScreenShare() => false;
Future<bool?> jsStartCanvasScreenShare(String? cameraDeviceId) async => false;
Future<void> jsStopCanvasScreenShare() async {}
bool jsIsCanvasScreenShareActive() => false;
void jsSetCanvasScreenShareStoppedCallback(void Function() callback) {}
String? jsGetCanvasShareLabel() => null;

List<int>? jsGetCanvasCompositorPixelSize() => null;

// Agora client bridge stubs (non-web).
bool jsAgoraClientBridgeAvailable() => false;
Future<bool> jsSetRemoteVideoStreamType(int uid, int streamType) async =>
    false;
Future<bool> jsSetStreamFallbackOption(int uid, int option) async => false;
Future<bool> jsSetRemoteDefaultVideoStreamType(int streamType) async => false;
Future<bool> jsEnableDualStream({
  required int width,
  required int height,
  required int framerate,
  required int bitrateKbps,
}) async =>
    false;
Future<bool> jsDisableDualStream() async => false;
Future<bool> jsSetLocalVideoOptimizationMode(String mode) async => false;
Future<bool> jsRenewToken(String token) async => false;
Future<bool> jsSetWakeLock(bool enable) async => false;
void jsSetAgoraConnectionStateCallback(
  void Function(String state, String reason) callback,
) {}
void jsSetPageVisibleCallback(void Function() callback) {}
void jsSetRemoteVideoStarvedCallback(
  void Function(int uid, bool starved) callback,
) {}

dynamic legacyJsAllowInteropVoid(void Function() f) => f;

dynamic jsInteropDynamicPair(void Function(dynamic a, dynamic b) f) => f;

bool jsHasProperty(Object o, Object name) => false;

JSAny? jsCallMethod(JSAny? receiver, Object method, List<JSAny?> args) {
  throw UnsupportedError('JS interop');
}

JSAny? jsJsify(Object? object) {
  throw UnsupportedError('JS interop');
}
