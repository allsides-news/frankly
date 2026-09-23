/// Live tracks can be muted and unmuted. Stopped tracks cannot be restarted
/// without a new getUserMedia.
bool avCheckHasLiveVideoTrack(Iterable<String?> readyStates) =>
    readyStates.any((state) => state == 'live');
