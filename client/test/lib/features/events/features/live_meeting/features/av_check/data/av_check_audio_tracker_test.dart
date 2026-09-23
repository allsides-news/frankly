import 'package:client/features/events/features/live_meeting/features/av_check/data/av_check_audio_tracker.dart';
import 'package:client/features/events/features/live_meeting/features/av_check/data/av_check_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('avCheckAudioTrackerName', () {
    test('meters without a default mic id', () {
      expect(
        avCheckAudioTrackerName(defaultMic: null, audioTrackId: 'track-1'),
        'track-1',
      );
      expect(avCheckAudioTrackerName(), 'microphone');
    });

    test('prefers the default mic when it is known', () {
      expect(
        avCheckAudioTrackerName(defaultMic: 'mic-a', audioTrackId: 'track-1'),
        'mic-a',
      );
    });
  });

  group('shouldRetryAvCheckAudioTracker', () {
    test('retries after defaults when the first attach had no tracker', () {
      expect(
        shouldRetryAvCheckAudioTracker(
          trackerAttached: false,
          hasAudioTracks: true,
        ),
        isTrue,
      );
    });

    test('does not recreate a tracker that already attached', () {
      expect(
        shouldRetryAvCheckAudioTracker(
          trackerAttached: true,
          hasAudioTracks: true,
        ),
        isFalse,
      );
    });
  });

  group('avCheckHasLiveVideoTrack', () {
    test('disabled but live tracks can be turned back on', () {
      expect(avCheckHasLiveVideoTrack(['live']), isTrue);
      expect(avCheckHasLiveVideoTrack(['live', 'ended']), isTrue);
    });

    test('stopped tracks cannot be restored without getUserMedia', () {
      expect(avCheckHasLiveVideoTrack(['ended']), isFalse);
      expect(avCheckHasLiveVideoTrack(const []), isFalse);
    });
  });
}
