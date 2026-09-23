import 'dart:async';

/// Web camera-on waits for capturing unless this session already has it.
/// [waitForCapture] forces a wait even if a prior session left the flag set.
bool shouldConfirmLocalVideoCapture({
  required bool isWeb,
  required bool waitForCapture,
  required bool captureAlreadyAvailable,
}) {
  if (!isWeb) return waitForCapture;
  return waitForCapture || !captureAlreadyAvailable;
}

/// After join, a second getUserMedia races the device iris-web already holds
/// and can throw NotAllowedError even when permission was granted.
enum UserMediaProbeAction { skip, probe, denied }

/// Permissions API `state` as a comparable token. Dart/JS wrappers may not
/// be the bare string `'granted'`.
String? normalizePermissionState(Object? state) {
  if (state == null) return null;
  final text = state.toString().toLowerCase();
  if (text.contains('denied')) return 'denied';
  if (text.contains('granted')) return 'granted';
  if (text.contains('prompt')) return 'prompt';
  return null;
}

/// Skip the in-app getUserMedia probe after this session has captured, the
/// Permissions API says granted, or Agora's video module is already up
/// (`enableVideo()` at join). A second getUserMedia then races iris-web and
/// surfaces as "permission required" even when the camera works.
///
/// `denied` still short-circuits so a blocked camera never calls Agora.
UserMediaProbeAction userMediaProbeAction({
  required bool requestingVideo,
  required bool requestingAudio,
  required bool videoCapturedThisSession,
  required bool audioCaptureAvailable,
  bool agoraHoldsMedia = false,
  String? permissionState,
}) {
  final state = normalizePermissionState(permissionState);
  if (requestingVideo) {
    if (videoCapturedThisSession) return UserMediaProbeAction.skip;
    if (state == 'denied') return UserMediaProbeAction.denied;
    if (state == 'granted') return UserMediaProbeAction.skip;
    if (agoraHoldsMedia) return UserMediaProbeAction.skip;
    return UserMediaProbeAction.probe;
  }
  if (requestingAudio) {
    if (audioCaptureAvailable) return UserMediaProbeAction.skip;
    if (state == 'denied') return UserMediaProbeAction.denied;
    if (state == 'granted') return UserMediaProbeAction.skip;
    if (agoraHoldsMedia) return UserMediaProbeAction.skip;
    return UserMediaProbeAction.probe;
  }
  return UserMediaProbeAction.skip;
}

/// In-meeting device errors stay in the call. Refresh reloads the page.
bool audioVideoErrorShowsRefresh({
  required bool inMeeting,
  required bool isDeviceError,
}) =>
    !inMeeting || !isDeviceError;

/// "You can still join and listen" only makes sense on the pre-join wall,
/// where a continue CTA accompanies it. In-meeting a blocked device is a
/// permission problem, not a join decision (QA regression 2026-09).
bool audioVideoErrorUsesListenOnlyCopy({
  required bool inMeeting,
  required bool canJoinWithoutDevices,
}) =>
    !inMeeting && canJoinWithoutDevices;

/// [Future.timeout] does not cancel [original]. Reclaim a late success
/// (e.g. stop getUserMedia tracks granted after we already timed out).
void reclaimTimedOutFuture<T>(
  Future<T> original, {
  required void Function(T value) onLateSuccess,
}) {
  Future<void> reclaim() async {
    try {
      onLateSuccess(await original);
    } catch (_) {}
  }

  unawaited(reclaim());
}
