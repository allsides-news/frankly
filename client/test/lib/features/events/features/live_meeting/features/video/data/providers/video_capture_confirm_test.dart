import 'dart:async';

import 'package:client/features/events/features/live_meeting/features/video/data/providers/video_capture_confirm.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldConfirmLocalVideoCapture', () {
    test('web camera-on waits after a prior capture was cleared', () {
      expect(
        shouldConfirmLocalVideoCapture(
          isWeb: true,
          waitForCapture: false,
          captureAlreadyAvailable: false,
        ),
        isTrue,
      );
    });

    test('web camera-on still waits when the caller forces confirmation', () {
      expect(
        shouldConfirmLocalVideoCapture(
          isWeb: true,
          waitForCapture: true,
          captureAlreadyAvailable: true,
        ),
        isTrue,
      );
    });

    test('web restore skips wait only while capture is still live', () {
      expect(
        shouldConfirmLocalVideoCapture(
          isWeb: true,
          waitForCapture: false,
          captureAlreadyAvailable: true,
        ),
        isFalse,
      );
    });

    test('non-web follows waitForCapture only', () {
      expect(
        shouldConfirmLocalVideoCapture(
          isWeb: false,
          waitForCapture: false,
          captureAlreadyAvailable: false,
        ),
        isFalse,
      );
    });
  });

  group('userMediaProbeAction', () {
    test('listen-only blocked camera is denied without a second getUserMedia',
        () {
      expect(
        userMediaProbeAction(
          requestingVideo: true,
          requestingAudio: false,
          videoCapturedThisSession: false,
          audioCaptureAvailable: true,
          permissionState: 'denied',
        ),
        UserMediaProbeAction.denied,
      );
    });

    test('skips probe after this session already captured', () {
      expect(
        userMediaProbeAction(
          requestingVideo: true,
          requestingAudio: false,
          videoCapturedThisSession: true,
          audioCaptureAvailable: false,
          permissionState: 'denied',
        ),
        UserMediaProbeAction.skip,
      );
    });

    test('granted camera skips probe so Agora can re-acquire', () {
      expect(
        userMediaProbeAction(
          requestingVideo: true,
          requestingAudio: false,
          videoCapturedThisSession: false,
          audioCaptureAvailable: false,
          permissionState: 'granted',
        ),
        UserMediaProbeAction.skip,
      );
    });

    test('prompt or unknown camera still probes', () {
      expect(
        userMediaProbeAction(
          requestingVideo: true,
          requestingAudio: false,
          videoCapturedThisSession: false,
          audioCaptureAvailable: false,
          permissionState: 'prompt',
        ),
        UserMediaProbeAction.probe,
      );
      expect(
        userMediaProbeAction(
          requestingVideo: true,
          requestingAudio: false,
          videoCapturedThisSession: false,
          audioCaptureAvailable: false,
        ),
        UserMediaProbeAction.probe,
      );
    });

    test('does not probe after Agora already opened the video module', () {
      expect(
        userMediaProbeAction(
          requestingVideo: true,
          requestingAudio: false,
          videoCapturedThisSession: false,
          audioCaptureAvailable: true,
          agoraHoldsMedia: true,
          permissionState: 'prompt',
        ),
        UserMediaProbeAction.skip,
      );
    });

    test('blocked camera is still denied even when Agora holds media', () {
      expect(
        userMediaProbeAction(
          requestingVideo: true,
          requestingAudio: false,
          videoCapturedThisSession: false,
          audioCaptureAvailable: true,
          agoraHoldsMedia: true,
          permissionState: 'denied',
        ),
        UserMediaProbeAction.denied,
      );
    });

    test('normalizes PermissionState-style strings', () {
      expect(normalizePermissionState('PermissionState.granted'), 'granted');
      expect(normalizePermissionState('DENIED'), 'denied');
    });

    test('mic follows capture-available and permission the same way', () {
      expect(
        userMediaProbeAction(
          requestingVideo: false,
          requestingAudio: true,
          videoCapturedThisSession: false,
          audioCaptureAvailable: true,
          permissionState: 'denied',
        ),
        UserMediaProbeAction.skip,
      );
      expect(
        userMediaProbeAction(
          requestingVideo: false,
          requestingAudio: true,
          videoCapturedThisSession: false,
          audioCaptureAvailable: false,
          permissionState: 'denied',
        ),
        UserMediaProbeAction.denied,
      );
    });
  });

  group('in-meeting AV error CTAs', () {
    test('blocked camera in a meeting is a permission error without Refresh',
        () {
      // Regression: in-meeting used to show the pre-join "you can still join
      // and listen" copy, which makes no sense once already in the room.
      expect(
        audioVideoErrorUsesListenOnlyCopy(
          inMeeting: true,
          canJoinWithoutDevices: false,
        ),
        isFalse,
      );
      expect(
        audioVideoErrorShowsRefresh(
          inMeeting: true,
          isDeviceError: true,
        ),
        isFalse,
      );
    });

    test('join wall with a continue CTA uses the listen-only copy', () {
      expect(
        audioVideoErrorUsesListenOnlyCopy(
          inMeeting: false,
          canJoinWithoutDevices: true,
        ),
        isTrue,
      );
    });

    test('join wall without continue still uses Refresh', () {
      expect(
        audioVideoErrorUsesListenOnlyCopy(
          inMeeting: false,
          canJoinWithoutDevices: false,
        ),
        isFalse,
      );
      expect(
        audioVideoErrorShowsRefresh(
          inMeeting: false,
          isDeviceError: true,
        ),
        isTrue,
      );
    });
  });

  group('reclaimTimedOutFuture', () {
    test('reclaims a late success after timeout would have fired', () async {
      final completer = Completer<String>();
      String? reclaimed;
      reclaimTimedOutFuture<String>(
        completer.future,
        onLateSuccess: (value) => reclaimed = value,
      );
      completer.complete('stream');
      await Future<void>.delayed(Duration.zero);
      expect(reclaimed, 'stream');
    });

    test('swallows a late error so it is not unhandled', () async {
      final completer = Completer<String>();
      reclaimTimedOutFuture<String>(
        completer.future,
        onLateSuccess: (_) => fail('late error should not look like success'),
      );
      completer.completeError('NotAllowedError');
      await Future<void>.delayed(Duration.zero);
    });
  });
}
