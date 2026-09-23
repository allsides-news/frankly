/// Hark meters the stream; [defaultMic] is only a log label.
String avCheckAudioTrackerName({
  String? defaultMic,
  String? audioTrackId,
}) {
  if (defaultMic != null && defaultMic.isNotEmpty) return defaultMic;
  if (audioTrackId != null && audioTrackId.isNotEmpty) return audioTrackId;
  return 'microphone';
}

bool shouldRetryAvCheckAudioTracker({
  required bool trackerAttached,
  required bool hasAudioTracks,
}) =>
    !trackerAttached && hasAudioTracks;
