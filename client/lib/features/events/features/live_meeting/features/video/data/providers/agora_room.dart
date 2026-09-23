import 'dart:async';
import 'dart:ui';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/utils/utils.dart';
import 'package:rxdart/rxdart.dart';

import '../../../../../../../../core/data/services/logging_service.dart';
import '../../../../../../../../core/utils/error_utils.dart';
import '../../../../../../../../core/utils/js_interop_bridge.dart';
import '../../../../../../../../services.dart';
import '../../../../../event_page/data/providers/event_provider.dart';
import '../../../../data/providers/live_meeting_provider.dart';
import 'conference_room.dart';
import 'video_capture_confirm.dart';

const _kAgoraAppId = '76cd63ec061d4192ac03ff8cdde51395';

/// Thrown when the user dismisses the screen-picker dialog without selecting
/// a source.  The caller should treat this as a no-op, not an error.
class ScreenShareCancelledException implements Exception {
  const ScreenShareCancelledException();
}

enum AgoraRoomState {
  CONNECTING,
  CONNECTED,
  RECONNECTING,
  DISCONNECTED,
}

bool _isBenignIrisWebMuteWhileTrackDisabled(Object e) =>
    e.toString().contains('cannot set muted while the track is disabled');

String _gumLikeErrorFromLocalVideoReason(LocalVideoStreamReason reason) {
  switch (reason) {
    case LocalVideoStreamReason.localVideoStreamReasonDeviceNoPermission:
      return kGumNotAllowedError;
    case LocalVideoStreamReason.localVideoStreamReasonDeviceNotFound:
      return kGumNotFoundError;
    default:
      return kGumNotReadableError;
  }
}

/// Maps an Agora camera UID to our user id. `not-found` is a join/backfill
/// race or a UID with no publicUser — retry, then local Firestore, then null.
Future<String?> _userIdForAgoraUid(
  int agoraUid, {
  int maxAttempts = 3,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final user = await cloudFunctionsLiveMeetingService.getUserIdFromAgoraId(
        GetUserIdFromAgoraIdRequest(agoraId: agoraUid),
      );
      if (user.userId.isNotEmpty) return user.userId;
    } catch (e) {
      if (!isCloudFunctionsNotFoundError(e)) rethrow;
    }

    try {
      final local = await firestoreUserService.getPublicUserByAgoraId(
        agoraId: agoraUid,
      );
      if (local != null && local.id.isNotEmpty) return local.id;
    } catch (_) {}

    if (attempt < maxAttempts - 1) {
      await Future<void>.delayed(Duration(milliseconds: 300 * (1 << attempt)));
    }
  }
  return null;
}

/// Camera encoder settings for all participants. Non-screen tiles render at
/// most 854×480 (see participant_widget.dart), so 640×360@15fps is plenty and
/// caps uplink cost on slow connections. bitrate 0 = SDK standard for the
/// dims+fps; maintainFramerate keeps motion smooth as bandwidth drops, which
/// matters more than sharpness for talking heads.
const _kCameraEncoderConfig = VideoEncoderConfiguration(
  dimensions: VideoDimensions(width: 640, height: 360),
  frameRate: 15,
  bitrate: 0,
  degradationPreference: DegradationPreference.maintainFramerate,
);

/// Reduced camera encoding applied after the local uplink has been bad for a
/// sustained period (see [AgoraRoom._onLocalUplinkQualitySample]) — roughly
/// halves uplink cost while keeping motion watchable.
const _kDegradedCameraEncoderConfig = VideoEncoderConfiguration(
  dimensions: VideoDimensions(width: 424, height: 240),
  frameRate: 12,
  bitrate: 0,
  degradationPreference: DegradationPreference.maintainFramerate,
);

/// Current camera encoder target: [_kCameraEncoderConfig] normally,
/// [_kDegradedCameraEncoderConfig] while uplink-degraded. File-private
/// mutable for the same reason as [_webDualStreamActive]: AgoraParticipant
/// re-applies it whenever the camera track (re)starts, and only one
/// AgoraRoom is live at a time.
VideoEncoderConfiguration _cameraEncoderTarget = _kCameraEncoderConfig;

/// Worse (higher-severity) of two ranked qualities; unranked values
/// (unknown / unsupported / detecting) defer to the other side.
QualityType _worseQuality(QualityType a, QualityType b) {
  bool ranked(QualityType q) =>
      q.value() >= QualityType.qualityExcellent.value() &&
      q.value() <= QualityType.qualityDown.value();
  if (!ranked(a)) return b;
  if (!ranked(b)) return a;
  return a.value() >= b.value() ? a : b;
}

/// Low (simulcast) stream published alongside the camera stream when
/// dual-stream mode is on. Small grid/strip tiles subscribe to this instead of
/// the full stream, and the audio-only fallback steps through it on the way
/// down when a viewer's network degrades. Plain ints so the web bridge call
/// (jsEnableDualStream) shares the exact same parameters as the native
/// SimulcastStreamConfig below.
const _kLowStreamWidth = 320;
const _kLowStreamHeight = 180;
const _kLowStreamFps = 15;
const _kLowStreamKbps = 140;

const _kLowStreamConfig = SimulcastStreamConfig(
  dimensions:
      VideoDimensions(width: _kLowStreamWidth, height: _kLowStreamHeight),
  kBitrate: _kLowStreamKbps,
  framerate: _kLowStreamFps,
);

/// Tiles rendered at least this wide (logical px) subscribe to the
/// high-quality stream; smaller tiles use the low stream.
const kHighStreamMinTileWidth = 480.0;

/// True while dual-stream publishing is active on web (enabled post-join when
/// the JS client bridge is available — see
/// [AgoraRoom._applyWebSubscriberOptimizations]). File-private so
/// [AgoraParticipant] can pause dual-stream around canvas screen sharing:
/// the compositor replaces every video sender, and the low-stream sender must
/// not receive the full-res canvas track. Only one AgoraRoom is live at a
/// time (breakout swaps dispose the old room before the new one joins).
bool _webDualStreamActive = false;

/// In-flight post-join web dual-stream activation
/// ([AgoraRoom._applyWebSubscriberOptimizations]). File-private so
/// [AgoraParticipant._pauseWebDualStreamForShare] can await it: a share
/// started right after join (common in breakouts) otherwise races the
/// activation — the pause sees the flag still false and skips the disable,
/// then the delayed enableDualStream builds the low stream from whatever the
/// sender holds by then, i.e. the compositor's canvas track (QA measured a
/// 320×227 canvas-aspect low stream during a breakout share).
Future<void>? _webDualStreamSetup;

/// Cap longest canvas edge when mapping getDisplayMedia → encoder (retina / ultrawide).
const _kCanvasShareEncoderMaxLongEdge = 2560;

/// Matches [canvas.captureStream] in `canvas_compositor.js`.
const _kCanvasShareEncoderFrameRate = 30;

VideoDimensions _evenEncoderDimensions(int w, int h) {
  if (w <= 0 || h <= 0) {
    return const VideoDimensions(width: 1920, height: 1080);
  }
  var nw = w;
  var nh = h;
  final longest = nw > nh ? nw : nh;
  if (longest > _kCanvasShareEncoderMaxLongEdge) {
    final scale = _kCanvasShareEncoderMaxLongEdge / longest;
    nw = (nw * scale).floor();
    nh = (nh * scale).floor();
  }
  nw -= nw % 2;
  nh -= nh % 2;
  if (nw < 2) nw = 2;
  if (nh < 2) nh = 2;
  return VideoDimensions(width: nw, height: nh);
}

/// iris-web only. Swallow known errors only when muting: ignoring unmute failures
/// would leave publish on while the SDK stays muted (silent broken state).
Future<void> _muteLocalAudioStreamWeb(RtcEngine engine, bool mute) async {
  try {
    await engine.muteLocalAudioStream(mute);
  } catch (e) {
    if (mute && _isBenignIrisWebMuteWhileTrackDisabled(e)) {
      loggingService.log(
        'muteLocalAudioStream(true): ignored benign iris-web error: $e',
      );
      return;
    }
    rethrow;
  }
}

class AgoraRoom with ChangeNotifier {
  RtcEngine? _engine;

  /// Null until [connect] assigns it. UI must use this — a `late` getter
  /// becomes `Null check operator used on a null value` on dart2js when
  /// video tiles rebuild against a room that has not finished constructing
  /// (breakout / reconnect while a GlobalKey keeps the old subtree).
  RtcEngine? get engineIfReady => _engine;

  RtcEngine get engine {
    final e = _engine;
    if (e == null) {
      throw StateError('AgoraRoom.engine used before connect()');
    }
    return e;
  }

  late final RtcEngineEventHandler _rtcEngineEventHandler;

  final String channelName;
  final String token;
  // Token for the secondary Agora connection used for screen sharing.
  // Null on old server deployments — falls back to single-engine mode.
  final String? screenShareToken;
  final EventProvider eventProvider;
  final LiveMeetingProvider liveMeetingProvider;
  final ConferenceRoom conferenceRoom;

  AgoraRoom({
    required this.channelName,
    required this.token,
    this.screenShareToken,
    required this.eventProvider,
    required this.liveMeetingProvider,
    required this.conferenceRoom,
  });

  bool connectedWithAudioEnabled = false;
  bool connectedWithVideoEnabled = false;

  /// True after connect (or a later toggle) opened Agora's video module.
  /// Join calls enableVideo() even for listen-only, then enableLocalVideo
  /// (false) — this is not proof the camera was acquired.
  bool videoModuleInitialized = false;
  bool audioCaptureAvailable = false;

  /// True after capturing/encoding. Cleared on stop/fail so a later
  /// camera-on waits again instead of trusting a stale success.
  bool videoCaptureAvailable = false;

  /// True after at least one successful capture this session. Camera-off
  /// does not clear this: a second getUserMedia races the device iris-web
  /// still holds.
  bool videoCapturedThisSession = false;

  AgoraRoomState _state = AgoraRoomState.CONNECTING;
  AgoraRoomState get state => _state;

  AgoraParticipant? _localParticipant;
  AgoraParticipant? get localParticipant => _localParticipant;

  final _remoteParticipants = <AgoraParticipant>[];
  List<AgoraParticipant>? get remoteParticipants => _remoteParticipants;

  List<AudioVolumeInfo> _remoteSpeakers = [];
  AudioVolumeInfo? _localSpeaker;

  final Map<int, bool> _audioMutedState = {};
  final Map<int, bool> _videoMutedState = {};

  /// True while [uid]'s subscription has fallen back to audio-only on a weak
  /// network (onRemoteSubscribeFallbackToAudioOnly). Kept separate from
  /// [_videoMutedState] so a fallback recovery cannot unhide a
  /// publisher-muted video and vice versa.
  final Map<int, bool> _videoFallbackState = {};

  /// True while WE dropped [uid]'s video to audio-only because the bridge's
  /// starvation watch reported the subscription receiving nothing (web only —
  /// see [_onRemoteVideoStarved]). Separate from [_videoFallbackState]
  /// (server-driven) so a server 'recover' event cannot unhide a tile whose
  /// video subscription this client still holds muted.
  final Map<int, bool> _manualVideoFallback = {};

  // Screen UIDs that arrived via onUserJoined before their camera counterpart.
  // Keyed by screen UID, value is the derived camera UID.
  final Map<int, int> _pendingScreenUids = {};

  // Camera UIDs currently in the channel, including those not yet mapped to a
  // userId. The first lookup can lose a join/backfill race; keep retrying
  // instead of dropping the remote tile for the rest of the session.
  final Set<int> _presentCameraUids = {};
  final Set<int> _unresolvedJoinUids = {};
  Timer? _unresolvedJoinRetryTimer;
  int _unresolvedJoinRetryAttempt = 0;
  bool _unresolvedJoinRetryInFlight = false;

  /// A remote tile shows video only when the publisher hasn't muted AND no
  /// fallback (server- or client-driven) has dropped the subscription.
  void _syncRemoteVideoEnabled(int rUid) {
    _remoteParticipants
            .where((p) => p.agoraUid == rUid)
            .firstOrNull
            ?.videoTrackEnabled =
        !(_videoMutedState[rUid] ?? false) &&
            !(_videoFallbackState[rUid] ?? false) &&
            !(_manualVideoFallback[rUid] ?? false);
  }

  Duration _unresolvedJoinRetryDelay() {
    switch (_unresolvedJoinRetryAttempt) {
      case 0:
        return const Duration(seconds: 2);
      case 1:
        return const Duration(seconds: 4);
      case 2:
        return const Duration(seconds: 8);
      default:
        return const Duration(seconds: 15);
    }
  }

  void _trackUnresolvedJoin(int rUid) {
    if (_isDisposed || !_presentCameraUids.contains(rUid)) return;
    _unresolvedJoinUids.add(rUid);
    if (_unresolvedJoinRetryInFlight ||
        (_unresolvedJoinRetryTimer?.isActive ?? false)) {
      return;
    }
    _unresolvedJoinRetryAttempt = 0;
    _scheduleUnresolvedJoinRetry();
  }

  void _scheduleUnresolvedJoinRetry() {
    if (_isDisposed || _unresolvedJoinUids.isEmpty) return;
    _unresolvedJoinRetryTimer?.cancel();
    _unresolvedJoinRetryTimer = Timer(_unresolvedJoinRetryDelay(), () {
      unawaited(_retryUnresolvedJoins());
    });
  }

  Future<void> _retryUnresolvedJoins() async {
    if (_isDisposed) return;
    _unresolvedJoinRetryInFlight = true;
    try {
      final uids = List<int>.from(_unresolvedJoinUids);
      for (final uid in uids) {
        if (_isDisposed) return;
        if (!_presentCameraUids.contains(uid) ||
            _remoteParticipants.any((p) => p.agoraUid == uid)) {
          _unresolvedJoinUids.remove(uid);
          continue;
        }
        String? userId;
        try {
          userId = await _userIdForAgoraUid(uid, maxAttempts: 1);
        } catch (e, stackTrace) {
          loggingService.log(
            'AgoraRoom: unresolved join retry failed for $uid',
            logType: LogType.error,
            error: e,
            stackTrace: stackTrace,
          );
        }
        if (_isDisposed) return;
        if (userId != null && userId.isNotEmpty) {
          _unresolvedJoinUids.remove(uid);
          _addRemoteParticipant(uid, userId);
        }
      }
    } finally {
      _unresolvedJoinRetryInFlight = false;
      if (!_isDisposed && _unresolvedJoinUids.isNotEmpty) {
        _unresolvedJoinRetryAttempt++;
        _scheduleUnresolvedJoinRetry();
      } else {
        _unresolvedJoinRetryAttempt = 0;
      }
    }
  }

  void _addRemoteParticipant(int rUid, String userId) {
    if (_isDisposed || !_presentCameraUids.contains(rUid)) return;
    if (_remoteParticipants.any((p) => p.agoraUid == rUid)) return;
    final rtcEngine = engineIfReady;
    if (rtcEngine == null) return;

    final participant = AgoraParticipant(
      rtcEngine: rtcEngine,
      agoraUid: rUid,
      userId: userId,
      isLocal: false,
    )..audioTrackEnabled = !(_audioMutedState[rUid] ?? false);

    _remoteParticipants.add(participant);
    _syncRemoteVideoEnabled(rUid);

    final pendingScreenUid = _pendingScreenUids.entries
        .firstWhereOrNull((e) => e.value == rUid)
        ?.key;
    if (pendingScreenUid != null) {
      _pendingScreenUids.remove(pendingScreenUid);
      participant._applyScreenShare(uid: pendingScreenUid, sharing: true);
    }

    conferenceRoom.onParticipantConnected();
    notifyListeners();
  }

  void _clearUnresolvedJoins() {
    _unresolvedJoinRetryTimer?.cancel();
    _unresolvedJoinRetryTimer = null;
    _unresolvedJoinUids.clear();
    _presentCameraUids.clear();
    _unresolvedJoinRetryAttempt = 0;
  }

  /// Latest decoded frame size per Agora UID (see [onVideoSizeChanged]); drives screen-share tile aspect.
  final Map<int, Size> _videoFrameSizeByUid = {};

  bool _isDisposed = false;

  final _dominantSpeakerStream = BehaviorSubject<AgoraParticipant?>();
  BehaviorSubject<AgoraParticipant?> get dominantSpeakerStream =>
      _dominantSpeakerStream;

  /// Decoded video dimensions from [RtcEngineEventHandler.onVideoSizeChanged], if known.
  Size? videoFrameSize(int uid) {
    final s = _videoFrameSizeByUid[uid];
    if (s == null || s.width <= 0 || s.height <= 0) return null;
    return s;
  }

  /// Shared by main-engine [onVideoSizeChanged], dual-engine screen callbacks, and web seed.
  void applyReportedVideoFrameSize(
      int uid, int width, int height, int rotation) {
    if (_isDisposed) return;
    var w = width;
    var h = height;
    if (rotation == 90 || rotation == 270) {
      final t = w;
      w = h;
      h = t;
    }
    if (w <= 0 || h <= 0) return;
    _videoFrameSizeByUid[uid] = Size(w.toDouble(), h.toDouble());
    notifyListeners();
  }

  void clearVideoFrameSize(int uid) {
    if (_isDisposed) return;
    if (_videoFrameSizeByUid.remove(uid) != null) {
      notifyListeners();
    }
  }

  /// Seeds layout aspect before [onVideoSizeChanged] (web canvas compositor).
  void seedVideoFrameSize(int uid, int w, int h) {
    applyReportedVideoFrameSize(uid, w, h, 0);
  }

  void _updateDominantSpeaker({
    int? localUid,
    required List<AudioVolumeInfo> speakers,
  }) {
    // Agora may deliver local and remote speakers in a single batch (native
    // iOS/Android) or separate batches (web). Always update both caches from
    // each batch so stale high-volume remotes never block local from winning
    // the dominant-speaker election. The 1-second hold in ConferenceRoom's
    // debounced stream absorbs the brief window where a local-only batch on
    // separate-batch platforms temporarily shows empty remotes.
    final localSpeaker = speakers
        .where((s) => localUid != null && s.uid == localUid)
        .firstOrNull;
    final remoteSpeakers = speakers.where((s) => s.uid != localUid).toList();
    if (localSpeaker != null) {
      _localSpeaker = localSpeaker;
    }
    _remoteSpeakers = remoteSpeakers;

    final dominantRemoteSpeaker = _remoteSpeakers.isEmpty
        ? null
        : _remoteSpeakers.reduce((a, b) {
            final aVolume = a.volume ?? 0;
            final bVolume = b.volume ?? 0;
            return aVolume > bVolume ? a : b;
          });

    const volumeCutoff = 1700;

    if (dominantRemoteSpeaker != null &&
        (dominantRemoteSpeaker.volume ?? 0) > volumeCutoff) {
      final dominantParticipant = _remoteParticipants
          .whereNotNull()
          .where((s) => s.agoraUid == dominantRemoteSpeaker.uid)
          .firstOrNull;
      _dominantSpeakerStream.add(dominantParticipant);
    } else if ((_localSpeaker?.volume ?? 0) > volumeCutoff) {
      _dominantSpeakerStream.add(_localParticipant);
    } else {
      _dominantSpeakerStream.add(null);
    }
  }

  Future<void> connect({
    bool enableAudio = false,
    bool enableVideo = false,
  }) async {
    _engine = createAgoraRtcEngine();

    await engine.initialize(
      RtcEngineContext(
        appId: _kAgoraAppId,
      ),
    );

    _localParticipant = AgoraParticipant(
      rtcEngine: engine,
      agoraUid: 0,
      isLocal: true,
      userId: userService.currentUserId!,
      token: token,
      owningRoom: this,
    )
      ..addListener(notifyListeners)
      ..audioTrackEnabled = false
      ..videoTrackEnabled = false;

    _rtcEngineEventHandler = RtcEngineEventHandler(
      onError: (ErrorCodeType err, String msg) {
        loggingService.log('[onError] err: $err, msg: $msg');
        if (err == ErrorCodeType.errJoinChannelRejected ||
            err == ErrorCodeType.errFailed) {
          conferenceRoom.setConnectError(
            'Could not join room. Please refresh and try again',
          );
          // Guard: only roll back if this AgoraRoom instance is for the
          // room that is currently active. onError is delivered
          // asynchronously by the SDK — a stale error for a previously
          // failed join can arrive after getBreakoutRoomFuture() has
          // already been called for a new room. Without the channelName
          // check, activeBreakoutRoomId would be non-null (new room) and
          // the guard would pass, incorrectly clearing the new room's
          // presence instead of the old failed room's presence.
          if (liveMeetingProvider.activeBreakoutRoomId == channelName) {
            liveMeetingProvider.rollbackBreakoutRoomPresence();
          }
        }
      },
      onJoinChannelSuccess: (RtcConnection connection, int elapsed) async {
        _state = AgoraRoomState.CONNECTED;

        // Web subscriber-side quality setup needs the live web client, which
        // only exists once the join is underway — so it runs post-join. The
        // future is kept so the screen-share pause can await it (see
        // _webDualStreamSetup).
        if (kIsWeb) {
          _webDualStreamSetup = _applyWebSubscriberOptimizations();
          unawaited(_webDualStreamSetup);
        }

        // A successful join confirms that the optimistic presence write is
        // correct. Clear any pending rollback flag that a stale
        // errJoinChannelRejected (from a prior failed attempt to this same
        // channel, arriving asynchronously after getBreakoutRoomFuture reset
        // the flag) may have re-set — otherwise the heartbeat would write null
        // every 5 s and make the user permanently invisible.
        if (liveMeetingProvider.activeBreakoutRoomId == channelName) {
          liveMeetingProvider.clearPresenceRollback();
        }

        unawaited(conferenceRoom.onConnected(this));
        conferenceRoom.onLocalParticipantChanges();

        notifyListeners();
        print(
          '[onJoinChannelSuccess] connection: ${connection.toJson()} elapsed: $elapsed',
        );

        await engine.enableAudioVolumeIndication(
          interval: 200,
          smooth: 3,
          reportVad: true,
        );

        print('Joined with audio: $enableAudio and video: $enableVideo');
        // Device errors are handled inside the toggles so a busy camera
        // cannot become an unhandled rejection on this SDK callback.
        if (enableVideo) {
          await conferenceRoom.toggleVideoEnabled(setEnabled: true);
        }
        if (enableAudio) {
          await conferenceRoom.toggleAudioEnabled(setEnabled: true);
        }
      },
      onUserJoined: (RtcConnection connection, int rUid, int elapsed) async {
        print(
          '[onUserJoined] connection: ${connection.toJson()} remoteUid: $rUid elapsed: $elapsed',
        );

        // Screen share UIDs have bit 30 set. They are virtual participants —
        // not added to the regular list, but linked to their camera participant.
        if (rUid >= (1 << 30)) {
          if (_isDisposed) return;
          final cameraUid = rUid ^ (1 << 30);
          final cameraParticipant = _remoteParticipants
              .firstWhereOrNull((p) => p.agoraUid == cameraUid);
          if (cameraParticipant != null) {
            cameraParticipant._applyScreenShare(uid: rUid, sharing: true);
            notifyListeners();
          } else {
            // Camera participant not yet in the list (e.g. reconnect race where
            // Agora delivers the screen UID first). Buffer it so we can apply it
            // once the camera UID's onUserJoined fires.
            _pendingScreenUids[rUid] = cameraUid;
          }
          return;
        }

        // Weak-network fallback is a per-remote-user call on web. Camera UIDs
        // only — reaching this line means the screen-UID branch above did not
        // return, so slow viewers can drop other cameras to low/audio-only
        // but never lose a shared screen.
        if (kIsWeb) {
          unawaited(_applyWebRemoteFallback(rUid));
        }

        _presentCameraUids.add(rUid);

        String? userId;
        try {
          userId = await _userIdForAgoraUid(rUid);
        } catch (e, stackTrace) {
          loggingService.log(
            'AgoraRoom.onUserJoined: lookup failed for $rUid',
            logType: LogType.error,
            error: e,
            stackTrace: stackTrace,
          );
        }

        if (_isDisposed) return;
        if (!_presentCameraUids.contains(rUid)) return;
        if (userId == null || userId.isEmpty) {
          loggingService.log(
            'AgoraRoom.onUserJoined: no publicUser for agora uid $rUid; retrying',
          );
          _trackUnresolvedJoin(rUid);
          return;
        }

        _addRemoteParticipant(rUid, userId);
      },
      onPermissionError: (PermissionType permissionType) {
        loggingService.log('[onPermissionError] $permissionType');
        if (permissionType == PermissionType.camera) {
          videoCaptureAvailable = false;
          videoCapturedThisSession = false;
          final waiting =
              _localParticipant?.isWaitingForLocalVideoStart ?? false;
          _localParticipant?.completeLocalVideoStart(
            error: Exception(kGumNotAllowedError),
          );
          if (!waiting) {
            unawaited(
              conferenceRoom.onLocalVideoCaptureFailed(kGumNotAllowedError),
            );
          }
        }
      },
      onLocalVideoStateChanged: (
        VideoSourceType source,
        LocalVideoStreamState state,
        LocalVideoStreamReason reason,
      ) {
        loggingService.log(
          '[onLocalVideoStateChanged] source: $source state: $state reason: $reason',
        );
        if (source != VideoSourceType.videoSourceCamera &&
            source != VideoSourceType.videoSourceCameraPrimary) {
          return;
        }
        if (state == LocalVideoStreamState.localVideoStreamStateCapturing ||
            state == LocalVideoStreamState.localVideoStreamStateEncoding) {
          videoCaptureAvailable = true;
          videoCapturedThisSession = true;
          _localParticipant?.completeLocalVideoStart();
        } else if (state ==
            LocalVideoStreamState.localVideoStreamStateStopped) {
          videoCaptureAvailable = false;
        } else if (state == LocalVideoStreamState.localVideoStreamStateFailed) {
          videoCaptureAvailable = false;
          final error = Exception(_gumLikeErrorFromLocalVideoReason(reason));
          final waiting =
              _localParticipant?.isWaitingForLocalVideoStart ?? false;
          _localParticipant?.completeLocalVideoStart(error: error);
          if (!waiting) {
            unawaited(
              conferenceRoom.onLocalVideoCaptureFailed(error.toString()),
            );
          }
        }
      },
      onUserOffline:
          (RtcConnection connection, int rUid, UserOfflineReasonType reason) {
        print(
          '[onUserOffline] connection: ${connection.toJson()}  rUid: $rUid reason: $reason',
        );
        if (rUid >= (1 << 30)) {
          // Screen share UID left — clear the link on its camera participant,
          // and remove any pending buffer entry in case it never matched.
          _pendingScreenUids.remove(rUid);
          _videoFrameSizeByUid.remove(rUid);
          _requestedStreamTypes.remove(rUid);
          _streamTypeWriteGen.remove(rUid);
          final participant = _remoteParticipants
              .firstWhereOrNull((p) => p.screenAgoraUid == rUid);
          if (participant != null) {
            participant._applyScreenShare(uid: null, sharing: false);
          }
          notifyListeners();
          return;
        }
        final wasPresent = _remoteParticipants.any((a) => a.agoraUid == rUid);
        _presentCameraUids.remove(rUid);
        _unresolvedJoinUids.remove(rUid);
        _remoteParticipants.removeWhere((a) => a.agoraUid == rUid);
        _videoMutedState.remove(rUid);
        _videoFallbackState.remove(rUid);
        _manualVideoFallback.remove(rUid);
        _manualFallbackProbing.remove(rUid);
        _audioMutedState.remove(rUid);
        _videoFrameSizeByUid.remove(rUid);
        _requestedStreamTypes.remove(rUid);
        _streamTypeWriteGen.remove(rUid);
        if (wasPresent) {
          conferenceRoom.onParticipantDisconnected();
        }
        notifyListeners();
      },
      onLeaveChannel: (RtcConnection connection, RtcStats stats) {
        print(
          '[onLeaveChannel] connection: ${connection.toJson()} stats: ${stats.toJson()}',
        );
        _remoteParticipants.clear();
        _pendingScreenUids.clear();
        _clearUnresolvedJoins();
        _videoFrameSizeByUid.clear();
        _requestedStreamTypes.clear();
        _streamTypeWriteGen.clear();
        _videoFallbackState.clear();
        _manualVideoFallback.clear();
        _manualFallbackProbing.clear();
        _state = AgoraRoomState.DISCONNECTED;
        notifyListeners();
      },
      onUserMuteVideo: (RtcConnection connection, int rUid, bool muted) {
        print(
          '[onUserMuteVideo] connection: ${connection.toJson()} muted: $muted',
        );

        _videoMutedState[rUid] = muted;
        _syncRemoteVideoEnabled(rUid);
        notifyListeners();
      },
      // Weak-network fallback (iris forwards the web SDK's 'stream-fallback'
      // event here): without this the tile keeps rendering the last decoded
      // frame — a frozen image instead of avatar-plus-audio.
      onRemoteSubscribeFallbackToAudioOnly: (int rUid, bool isFallback) {
        print(
          '[onRemoteSubscribeFallbackToAudioOnly] uid: $rUid '
          'isFallback: $isFallback',
        );
        _videoFallbackState[rUid] = isFallback;
        _syncRemoteVideoEnabled(rUid);
        notifyListeners();
      },
      onUserMuteAudio: (RtcConnection connection, int rUid, bool muted) {
        print(
          '[onUserMuteAudio] connection: ${connection.toJson()} muted: $muted',
        );
        _audioMutedState[rUid] = muted;
        _remoteParticipants
            .where((p) => p.agoraUid == rUid)
            .firstOrNull
            ?.audioTrackEnabled = !muted;

        notifyListeners();
      },
      onUserEnableVideo: (RtcConnection connection, int rUid, bool enabled) {
        print(
          '[onUserEnableVideo] connection: ${connection.toJson()} enabled: $enabled',
        );
      },
      onVideoSubscribeStateChanged: (
        String channelId,
        int uid,
        StreamSubscribeState oldState,
        StreamSubscribeState newState,
        int elapsedTime,
      ) {
        print(
          '[onVideoSubscribeStateChanged]  $channelId uid: $uid oldState: $oldState newState $newState',
        );
      },
      onRemoteAudioStateChanged: (
        RtcConnection connection,
        int remoteUid,
        RemoteAudioState state,
        RemoteAudioStateReason reason,
        int elapsed,
      ) {
        print(
          '[onRemoteAudioStateChanged] connection: ${connection.toJson()} remoteUid: $remoteUid state: $state reason: $reason elapsed: $elapsed',
        );

        notifyListeners();
      },
      onRemoteVideoStateChanged: (
        RtcConnection connection,
        int remoteUid,
        RemoteVideoState state,
        RemoteVideoStateReason reason,
        int elapsed,
      ) {
        print(
          '[onRemoteVideoStateChanged] connection: ${connection.toJson()} uid: $remoteUid state: $state',
        );

        notifyListeners();
      },
      onVideoSizeChanged: (
        RtcConnection connection,
        VideoSourceType _,
        int uid,
        int width,
        int height,
        int rotation,
      ) {
        applyReportedVideoFrameSize(uid, width, height, rotation);
      },
      onUserEnableLocalVideo:
          (RtcConnection connection, int uid, bool enabled) {
        print(
          '[onUserEnableLocalVideo] connection: ${connection.toJson()} uid: $uid enabled: $enabled',
        );
        notifyListeners();
      },
      onLocalAudioStateChanged: (
        RtcConnection connection,
        LocalAudioStreamState state,
        LocalAudioStreamReason reason,
      ) {
        print(
          '[onLocalAudioStateChanged] connection: ${connection.toJson()} state: $state reason: $reason',
        );
      },
      onNetworkQuality: (
        RtcConnection connection,
        int uid,
        QualityType txQuality,
        QualityType rxQuality,
      ) {
        if (uid == 0) {
          // iris-web forwards the web SDK's network-quality event as
          // (downlink, uplink) into the native (tx, rx) parameter slots —
          // inverted. Normalize so consumers reason in real uplink/downlink
          // terms on every platform.
          final uplink = kIsWeb ? rxQuality : txQuality;
          final downlink = kIsWeb ? txQuality : rxQuality;
          final local = _localParticipant;
          if (local != null) {
            local
              ..uplinkQuality = uplink
              ..downlinkQuality = downlink
              ..networkQualityLevel = _worseQuality(uplink, downlink);
          }
          _onLocalUplinkQualitySample(uplink);
          _onLocalDownlinkQualitySample(downlink);
        } else {
          // Per-remote quality only arrives on native; web always reports
          // uid 0.
          _remoteParticipants
              .where((p) => p.agoraUid == uid)
              .firstOrNull
              ?.networkQualityLevel = txQuality;
        }
        notifyListeners();
      },
      // Renew proactively so the SDK's automatic reconnect never re-joins
      // with an expired token (which strands the user until a refresh).
      onTokenPrivilegeWillExpire: (RtcConnection connection, String token) {
        loggingService.log('AgoraRoom: token expiring — renewing');
        unawaited(_renewToken());
      },
      // Device hot-swap (AirPods/headsets/USB cams): iris translates the web
      // SDK's onMicrophoneChanged/onCameraChanged into these events.
      onAudioDeviceStateChanged: (
        String deviceId,
        MediaDeviceType deviceType,
        MediaDeviceStateType deviceState,
      ) {
        loggingService.log(
          'AgoraRoom: audio device $deviceType $deviceState ($deviceId)',
        );
        if (deviceType == MediaDeviceType.audioRecordingDevice) {
          _onMediaDeviceChanged(isAudio: true);
        }
      },
      onVideoDeviceStateChanged: (
        String deviceId,
        MediaDeviceType deviceType,
        MediaDeviceStateType deviceState,
      ) {
        loggingService.log(
          'AgoraRoom: video device $deviceType $deviceState ($deviceId)',
        );
        if (deviceType == MediaDeviceType.videoCaptureDevice) {
          _onMediaDeviceChanged(isAudio: false);
        }
      },
      onAudioVolumeIndication: (
        RtcConnection connection,
        List<AudioVolumeInfo> speakers,
        int speakerNumber,
        int totalVolume,
      ) {
        for (final speaker in speakers) {
          if (speaker.uid == connection.localUid) {
            _localParticipant?.volume = speaker.volume;
          } else {
            final participant = _remoteParticipants
                .where((s) => s.agoraUid == speaker.uid)
                .firstOrNull;
            participant?.volume = speaker.volume;
          }
        }

        _updateDominantSpeaker(
          localUid: connection.localUid,
          speakers: speakers,
        );
      },
    );

    engine.registerEventHandler(_rtcEngineEventHandler);

    // Fresh room, fresh encoder baseline (file-private mutable).
    _cameraEncoderTarget = _kCameraEncoderConfig;

    if (kIsWeb) {
      // Reconnection banner: iris only surfaces terminal disconnects, so
      // RECONNECTING/CONNECTED transitions come from the client bridge.
      jsSetAgoraConnectionStateCallback(_onWebConnectionStateChanged);
      // Client-side audio-only stage: Agora's server-driven fallback never
      // fires for web subscribers, so the bridge watches for starved
      // subscriptions and this room drops/restores them itself.
      jsSetRemoteVideoStarvedCallback(_onRemoteVideoStarved);
      // Mobile browsers suspend capture when backgrounded/locked.
      jsSetPageVisibleCallback(_onPageVisible);
      // Keep the screen awake during the meeting (phones lock mid-meeting
      // for listen-only participants, killing their A/V).
      unawaited(jsSetWakeLock(true).catchError((_) => false));
    }

    // enableVideo() opens the capture module on web. A busy/missing camera
    // throws NotReadableError; aborting here locked the user out of the
    // meeting. Join listen-only and let a later camera toggle surface the
    // device error in the AV dialog.
    var videoModuleReady = false;
    try {
      await engine.enableVideo();
      videoModuleReady = true;
      videoModuleInitialized = true;
    } catch (e) {
      loggingService.log(
        'AgoraRoom.connect: enableVideo failed, joining without camera: $e',
      );
    }
    try {
      await engine.enableAudio();
    } catch (e) {
      loggingService.log(
        'AgoraRoom.connect: enableAudio failed, joining listen-only: $e',
      );
    }
    try {
      await engine.muteAllRemoteAudioStreams(false);
    } catch (e) {
      loggingService.log(
        'AgoraRoom.connect: muteAllRemoteAudioStreams failed: $e',
      );
    }

    await _applyBandwidthOptimizations();

    if (videoModuleReady) {
      await engine.enableLocalVideo(false);
    }
    // Keep local audio enabled but muted, so the mic capture pipeline stays
    // warm and unmuting is instant.
    //
    // Must not abort the join: on machines with no usable microphone (none
    // present, or blocked by Windows privacy settings) getUserMedia throws
    // NotFoundError here, and failing hard locked those users out of the
    // event entirely. Playback needs no capture device — join listen-only
    // and let a later unmute attempt surface the device error via the
    // normal toggle error dialog.
    try {
      await engine.enableLocalAudio(true);
      await engine.muteLocalAudioStream(true);
      audioCaptureAvailable = true;
    } catch (e) {
      loggingService.log(
        'AgoraRoom.connect: mic warm-up failed, joining listen-only: $e',
      );
    }

    await engine.joinChannel(
      channelId: channelName,
      token: token,
      uid: uidToInt(userService.currentUserId!),
      options: ChannelMediaOptions(
        clientRoleType: ClientRoleType.clientRoleBroadcaster,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        autoSubscribeAudio: true,
        autoSubscribeVideo: true,
        enableAudioRecordingOrPlayout: true,
        publishMicrophoneTrack: false,
      ),
    );
  }

  /// Bandwidth/quality settings for slow connections. Must run before
  /// joinChannel (the fallback option and default stream type only apply
  /// pre-join). Each call is best-effort: platform support differs between
  /// native and iris-web, and a failure of any single optimization must not
  /// abort the join.
  Future<void> _applyBandwidthOptimizations() async {
    Future<void> attempt(String name, Future<void> Function() fn) async {
      try {
        await fn();
      } catch (e) {
        loggingService.log('AgoraRoom: $name failed: $e');
      }
    }

    // Audio profile: musicStandard = 48 kHz mono, up to 64 Kbps — cheap next
    // to video and keeps enough fidelity for speech-to-text. Do NOT drop to
    // speechStandard (32 kHz / 18 Kbps on web): it audibly degraded live
    // transcription in QA (choppy, missing words). Under packet loss the
    // encode rate rising to ~63 Kbps is expected (Opus in-band FEC), not a
    // config bug.
    await attempt(
      'setAudioProfile',
      () => engine.setAudioProfile(
        profile: AudioProfileType.audioProfileMusicStandard,
        scenario: AudioScenarioType.audioScenarioMeeting,
      ),
    );

    await attempt(
      'setVideoEncoderConfiguration',
      () => engine.setVideoEncoderConfiguration(_kCameraEncoderConfig),
    );

    // iris-web stubs out the entire dual-stream tier below
    // (enableDualStreamMode / setRemoteDefaultVideoStreamType /
    // setRemoteSubscribeFallbackOption all throw ERR_NOT_SUPPORTED), so on
    // web it goes through the JS client bridge instead, post-join — see
    // _applyWebSubscriberOptimizations.
    if (kIsWeb) return;

    // Publish a low-res stream alongside the camera stream so subscribers can
    // pick per tile (see ParticipantWidget) and the fallback below has a
    // middle step before dropping video entirely.
    await attempt(
      'enableDualStreamMode',
      () => engine.enableDualStreamMode(
        enabled: true,
        streamConfig: _kLowStreamConfig,
      ),
    );

    // Default new subscriptions to the low stream; tiles rendered large
    // upgrade themselves to high via setPreferredRemoteVideoStreamType.
    await attempt(
      'setRemoteDefaultVideoStreamType',
      () => engine.setRemoteDefaultVideoStreamType(
        VideoStreamType.videoStreamLow,
      ),
    );

    // When a viewer's downlink degrades, automatically step down to the low
    // stream and then to audio-only, restoring video when the network
    // recovers. Keeps audio alive — the most important thing on a bad
    // connection.
    await attempt(
      'setRemoteSubscribeFallbackOption',
      () => engine.setRemoteSubscribeFallbackOption(
        StreamFallbackOptions.streamFallbackOptionAudioOnly,
      ),
    );
  }

  /// Web counterpart of the dual-stream tier in _applyBandwidthOptimizations.
  /// iris-web stubs the subscriber-side engine APIs, but the JS client bridge
  /// (agora_client_bridge.js) exposes them on the underlying web client.
  /// Runs post-join because the web client is only created during joinChannel.
  Future<void> _applyWebSubscriberOptimizations() async {
    if (!kIsWeb || _isDisposed) return;
    _webDualStreamActive = false;
    if (!jsAgoraClientBridgeAvailable()) {
      loggingService.log(
        'AgoraRoom: JS client bridge unavailable — dual-stream disabled on web',
      );
      return;
    }

    // Publish the low simulcast stream. iris-web stubs enableDualStreamMode
    // (every variant throws ERR_NOT_SUPPORTED), so this must go through the
    // bridge to the underlying web client.
    try {
      final enabled = await jsEnableDualStream(
        width: _kLowStreamWidth,
        height: _kLowStreamHeight,
        framerate: _kLowStreamFps,
        bitrateKbps: _kLowStreamKbps,
      );
      if (!enabled) {
        loggingService.log(
          'AgoraRoom: enableDualStream(web) not applied — '
          'dual-stream disabled',
        );
        return;
      }
      _webDualStreamActive = true;
      // Success breadcrumb: QA verifies each end's activation from console
      // captures (chrome://inspect on phones); only failures were logged
      // before, so an unactivated end was indistinguishable from a lost log.
      loggingService.log('AgoraRoom: web dual-stream active');
      // Belt-and-braces for the share race (see _webDualStreamSetup): if the
      // compositor grabbed the senders while the enable above was in flight,
      // the low stream was just built from the canvas track — undo now. The
      // flag stays true so the post-share resume re-enables it.
      if (jsIsCanvasScreenShareActive()) {
        loggingService.log(
          'AgoraRoom: share active during dual-stream activation — '
          'disabling low stream until share ends',
        );
        try {
          await jsDisableDualStream();
        } catch (e) {
          loggingService.log('AgoraRoom: post-activation disable failed: $e');
        }
      }
    } catch (e) {
      loggingService.log('AgoraRoom: enableDualStream(web) failed: $e');
      return;
    }

    // Default future subscriptions to the low stream; tiles rendered large
    // upgrade themselves via setPreferredRemoteVideoStreamType. Participants
    // already subscribed keep high until their tile's next layout pass.
    try {
      await jsSetRemoteDefaultVideoStreamType(
        VideoStreamType.videoStreamLow.value(),
      );
    } catch (e) {
      loggingService.log(
        'AgoraRoom: setRemoteDefaultVideoStreamType(web) failed: $e',
      );
    }

    // Rebuild tiles now that dual-stream is active: per-tile preferences
    // requested before activation were intentionally dropped in
    // setPreferredRemoteVideoStreamType, and this notification guarantees the
    // layout pass that re-issues them (rather than waiting for an unrelated
    // rebuild).
    if (!_isDisposed) notifyListeners();
  }

  /// Web: registers the server-side weak-network fallback preference for
  /// [uid] (drop to low stream, then audio-only, recover with the network).
  ///
  /// Per the Agora web SDK docs (IAgoraRTCClient), this is NOT mutually
  /// exclusive with the per-tile setRemoteVideoStreamType calls: the manual
  /// type is the baseline and fallback dynamically overrides it under
  /// congestion, restoring it on recovery. Both only take effect when the
  /// PUBLISHER of [uid] has dual-stream active.
  ///
  /// KNOWN LIMITATION, measured in QA: the low-stream stage works, but
  /// Agora's edge never pushes the audio-only stage
  /// (on_stream_fallback_update / 'stream-fallback') to web subscribers —
  /// verified at 100 Kbps down, far under the 140 Kbps low stream, where the
  /// subscription simply starved at 0 fps. This registration is kept as the
  /// documented API (and it may drive the low stage server-side), but the
  /// audio-only stage is implemented client-side: the bridge's starvation
  /// watch + [_onRemoteVideoStarved].
  Future<void> _applyWebRemoteFallback(int uid) async {
    if (!kIsWeb || _isDisposed || !jsAgoraClientBridgeAvailable()) return;
    // onUserJoined (the only call site) can fire before the web client lists
    // the uid in remoteUsers; retry briefly rather than one-shotting, since
    // a miss here would leave the fallback unset for the whole session.
    const attempts = 5;
    for (var i = 0; i < attempts; i++) {
      if (_isDisposed) return;
      try {
        final applied = await jsSetStreamFallbackOption(
          uid,
          StreamFallbackOptions.streamFallbackOptionAudioOnly.value(),
        );
        if (applied) return;
      } catch (e) {
        loggingService.log(
          'AgoraRoom: setStreamFallbackOption($uid) failed: $e',
        );
        return;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    loggingService.log(
      'AgoraRoom: stream fallback never applied for $uid (uid not visible '
      'after $attempts attempts)',
    );
  }

  /// Fetches a fresh token for THIS room and renews the live session. On
  /// web the engine-level renewToken is stubbed by iris-web; the client
  /// bridge is the only renewal path.
  Future<void> _renewToken() async {
    try {
      final joinInfo =
          await liveMeetingProvider.fetchFreshJoinInfoForCurrentRoom();
      if (_isDisposed) return;
      if (joinInfo.meetingId != channelName) {
        // Raced a breakout transition — this room is on its way out.
        loggingService.log(
          'AgoraRoom: fresh token is for ${joinInfo.meetingId}, '
          'not $channelName — skipping renew',
        );
        return;
      }
      if (kIsWeb) {
        if (jsAgoraClientBridgeAvailable()) {
          final ok = await jsRenewToken(joinInfo.meetingToken);
          loggingService.log(
            'AgoraRoom: token renew ${ok ? 'ok' : 'not applied'}',
          );
        }
        return;
      }
      await engine.renewToken(joinInfo.meetingToken);
      loggingService.log('AgoraRoom: token renew ok');
    } catch (e) {
      loggingService.log('AgoraRoom: token renew failed: $e');
    }
  }

  /// Bumped after each web reconnect; remote tiles key their AgoraVideoView
  /// on it. iris-web can fail to re-attach a remote track to the old
  /// platform view after a reconnect ("AgoraSurfaceView_* not found" — view
  /// ids change), leaving a black tile while frames still arrive (verified
  /// in QA via getStats). A changed key disposes the old view and creates a
  /// fresh one, re-running setupRemoteVideo against the live track.
  int _remoteVideoViewGeneration = 0;
  int get remoteVideoViewGeneration => _remoteVideoViewGeneration;

  void _onWebConnectionStateChanged(String state, String reason) {
    if (_isDisposed) return;
    if (state == 'RECONNECTING' && _state == AgoraRoomState.CONNECTED) {
      loggingService.log('AgoraRoom: reconnecting ($reason)');
      _state = AgoraRoomState.RECONNECTING;
      notifyListeners();
    } else if (state == 'CONNECTED' && _state == AgoraRoomState.RECONNECTING) {
      loggingService.log('AgoraRoom: reconnected');
      _remoteVideoViewGeneration++;
      _state = AgoraRoomState.CONNECTED;
      notifyListeners();
    }
  }

  /// Mobile browsers suspend the camera when the page is backgrounded or the
  /// screen locks; nudge it back on return. Desktop tab switches don't
  /// suspend capture, so this is mobile-only.
  void _onPageVisible() {
    if (_isDisposed || !jsIsActualMobileDevice()) return;
    final local = _localParticipant;
    if (local == null || !local.videoTrackEnabled || local._isScreenSharing) {
      return;
    }
    loggingService.log('AgoraRoom: page visible — restoring camera');
    unawaited(
      local
          .enableVideo(
        setEnabled: true,
        deviceId: sharedPreferencesService.getDefaultCameraId(),
        waitForCapture: kIsWeb,
      )
          .catchError((e) {
        loggingService.log('AgoraRoom: camera restore failed: $e');
      }),
    );
  }

  // ─── Sustained-bad-uplink encoder step-down ───

  static const _kUplinkDegradeAfter = Duration(seconds: 20);
  static const _kUplinkRestoreAfter = Duration(seconds: 60);
  DateTime? _uplinkBadSince;
  DateTime? _uplinkGoodSince;
  bool _cameraEncoderDegraded = false;

  /// Steps the camera encoder down after sustained bad uplink and back up
  /// after sustained recovery. Hysteresis (20s down / 60s up) prevents
  /// flapping on marginal connections. The receiver side already exists
  /// (dual-stream low + fallback); this reduces what WE send.
  ///
  /// 'poor' is deliberately on the RESTORE side, not the degrade side: the
  /// web SDK derives tx quality from RTT/loss feedback and lingers at poor
  /// long after congestion clears (QA measured rtt 2672ms during downlink
  /// starvation). With poor treated as bad, every poor sample reset the 60s
  /// restore streak and the encoder stayed at 424×240 for the rest of the
  /// session. A link merely at poor sustains 640×360@15 fine; only
  /// bad/vbad/down warrant stepping down.
  void _onLocalUplinkQualitySample(QualityType uplink) {
    const bad = [
      QualityType.qualityBad,
      QualityType.qualityVbad,
      QualityType.qualityDown,
    ];
    const restorable = [
      QualityType.qualityExcellent,
      QualityType.qualityGood,
      QualityType.qualityPoor,
    ];
    final now = DateTime.now();
    if (bad.contains(uplink)) {
      _uplinkGoodSince = null;
      _uplinkBadSince ??= now;
      if (!_cameraEncoderDegraded &&
          now.difference(_uplinkBadSince!) >= _kUplinkDegradeAfter) {
        _cameraEncoderDegraded = true;
        _setCameraEncoderTarget(
          _kDegradedCameraEncoderConfig,
          reason: 'sustained bad uplink',
        );
      }
    } else if (restorable.contains(uplink)) {
      _uplinkBadSince = null;
      _uplinkGoodSince ??= now;
      if (_cameraEncoderDegraded &&
          now.difference(_uplinkGoodSince!) >= _kUplinkRestoreAfter) {
        _cameraEncoderDegraded = false;
        _setCameraEncoderTarget(
          _kCameraEncoderConfig,
          reason: 'uplink recovered',
        );
      }
    }
    // Unknown/detecting samples are neutral: they extend neither streak.
  }

  void _setCameraEncoderTarget(
    VideoEncoderConfiguration config, {
    required String reason,
  }) {
    _cameraEncoderTarget = config;
    loggingService.log(
      'AgoraRoom: camera encoder → ${config.dimensions?.width}x'
      '${config.dimensions?.height}@${config.frameRate} ($reason)',
    );
    final local = _localParticipant;
    // While the compositor owns the senders its raised share encoder must
    // not be overwritten; a camera that is off picks the target up on its
    // next start via _applyCameraTrackSettingsWeb.
    if (local == null || local._isScreenSharing || !local.videoTrackEnabled) {
      return;
    }
    unawaited(
      engine.setVideoEncoderConfiguration(config).catchError((e) {
        loggingService.log('AgoraRoom: encoder retarget failed: $e');
      }),
    );
  }

  // ─── Client-side audio-only fallback (web) ───
  //
  // QA disproved the server-driven fallback at 100 Kbps down (well under the
  // 140 Kbps low stream): setStreamFallbackOption registers fine but Agora's
  // edge never sends on_stream_fallback_update to web subscribers — the
  // subscription just starves (0 bitrate, frozen frame, no avatar). The
  // bridge's starvation watch + this section implement the audio-only stage
  // ourselves: drop the starved uid's video subscription (avatar + audio
  // stays), then probe for recovery.

  /// Sustained good downlink before probing whether starved videos recover.
  static const _kManualFallbackProbeAfterGood = Duration(seconds: 15);

  /// Probe cadence when downlink quality never reports good (e.g. a link
  /// that is merely adequate for the low stream) — without this a fallback
  /// engaged during a transient dip would never restore.
  static const _kManualFallbackProbeInterval = Duration(seconds: 60);

  /// A probe (re-subscribe) that hasn't seen frames within this window is
  /// considered failed and the subscription is muted again.
  static const _kManualFallbackProbeTimeout = Duration(seconds: 15);

  /// UIDs re-subscribed by a probe, awaiting the bridge's verdict. The tile
  /// keeps showing the avatar until frames actually flow (starved=false), so
  /// a failed probe never flashes a black tile.
  final Set<int> _manualFallbackProbing = {};
  Timer? _manualFallbackProbeTimer;
  DateTime? _downlinkGoodSince;
  DateTime? _lastManualFallbackProbe;

  /// Bridge starvation-watch callback: [starved]=true when [uid]'s
  /// subscribed video received nothing for a sustained period, false when it
  /// is receiving again (only ever fires while the subscription is live, so
  /// false doubles as a successful-probe signal).
  void _onRemoteVideoStarved(int uid, bool starved) {
    if (_isDisposed || uid == 0) return;
    // Never audio-only a shared screen: dual-engine screens have bit 30 set;
    // web canvas shares ride the sharer's camera uid, flagged on the
    // participant. Content beats motion — a frozen slide is still readable.
    if (uid >= (1 << 30)) return;
    final participant =
        _remoteParticipants.firstWhereOrNull((p) => p.agoraUid == uid);
    if (starved) {
      if (participant?.isScreenSharing ?? false) return;
      // Publisher-muted video legitimately receives nothing; the bridge
      // already skips hasVideo=false but guard against ordering races.
      if (_videoMutedState[uid] ?? false) return;
      if ((_manualVideoFallback[uid] ?? false) &&
          !_manualFallbackProbing.contains(uid)) {
        return;
      }
      _manualFallbackProbing.remove(uid);
      _manualVideoFallback[uid] = true;
      _lastManualFallbackProbe ??= DateTime.now();
      loggingService.log(
        'AgoraRoom: $uid video starved — dropping to audio-only',
      );
      unawaited(
        engine.muteRemoteVideoStream(uid: uid, mute: true).catchError((e) {
          loggingService.log('AgoraRoom: mute starved video($uid): $e');
        }),
      );
      _syncRemoteVideoEnabled(uid);
      notifyListeners();
    } else {
      _manualFallbackProbing.remove(uid);
      if (_manualVideoFallback.remove(uid) != null) {
        loggingService.log('AgoraRoom: $uid video recovered from audio-only');
        // The unsubscribe/resubscribe cycle may have reset the server-side
        // high/low selection while _requestedStreamTypes still records it as
        // applied (same rejoin-ABA shape as _streamTypeWriteGen). Drop the
        // entry so the next layout pass re-issues the tile's preference.
        _requestedStreamTypes.remove(uid);
        _streamTypeWriteGen.remove(uid);
        _syncRemoteVideoEnabled(uid);
        notifyListeners();
      }
      if (_manualVideoFallback.isEmpty) _lastManualFallbackProbe = null;
    }
  }

  /// Mirror of [_onLocalUplinkQualitySample] for the receive side: decides
  /// when to probe manually-dropped videos for recovery.
  void _onLocalDownlinkQualitySample(QualityType downlink) {
    const good = [QualityType.qualityExcellent, QualityType.qualityGood];
    const bad = [
      QualityType.qualityPoor,
      QualityType.qualityBad,
      QualityType.qualityVbad,
      QualityType.qualityDown,
    ];
    final now = DateTime.now();
    if (good.contains(downlink)) {
      _downlinkGoodSince ??= now;
    } else if (bad.contains(downlink)) {
      _downlinkGoodSince = null;
    }
    // Unknown/detecting samples extend neither streak.

    if (_manualVideoFallback.isEmpty || _manualFallbackProbing.isNotEmpty) {
      return;
    }
    final goodSince = _downlinkGoodSince;
    final lastProbe = _lastManualFallbackProbe;
    final goodLongEnough = goodSince != null &&
        now.difference(goodSince) >= _kManualFallbackProbeAfterGood;
    final probeOverdue = lastProbe != null &&
        now.difference(lastProbe) >= _kManualFallbackProbeInterval;
    if (goodLongEnough || probeOverdue) {
      _probeManualFallbacks();
    }
  }

  /// Re-subscribes every manually-dropped video; the bridge then reports
  /// starved=false (frames flowing → tile restored) or stays silent, in
  /// which case the timeout mutes the subscription again. The avatar stays
  /// up for the whole probe either way.
  void _probeManualFallbacks() {
    _lastManualFallbackProbe = DateTime.now();
    for (final uid in _manualVideoFallback.keys) {
      _manualFallbackProbing.add(uid);
      loggingService.log('AgoraRoom: probing audio-only fallback for $uid');
      unawaited(
        engine.muteRemoteVideoStream(uid: uid, mute: false).catchError((e) {
          loggingService.log('AgoraRoom: fallback probe unmute($uid): $e');
        }),
      );
    }
    _manualFallbackProbeTimer?.cancel();
    _manualFallbackProbeTimer = Timer(_kManualFallbackProbeTimeout, () {
      if (_isDisposed) return;
      for (final uid in _manualFallbackProbing.toList()) {
        _manualFallbackProbing.remove(uid);
        if (_manualVideoFallback[uid] ?? false) {
          loggingService.log(
            'AgoraRoom: probe failed for $uid — staying audio-only',
          );
          unawaited(
            engine.muteRemoteVideoStream(uid: uid, mute: true).catchError((e) {
              loggingService.log('AgoraRoom: fallback probe re-mute($uid): $e');
            }),
          );
        }
      }
    });
  }

  // ─── Device hot-swap recovery ───

  Timer? _deviceReacquireTimer;
  bool _pendingMicReacquire = false;
  bool _pendingCameraReacquire = false;

  /// Debounced re-acquire after device hot-swap (AirPods, headsets, USB
  /// cams) so capture follows the current default device instead of dying
  /// silently with the removed one. Debounced because one physical event
  /// fires several state changes. A muted mic is skipped — the next unmute
  /// re-acquires anyway.
  void _onMediaDeviceChanged({required bool isAudio}) {
    if (isAudio) {
      _pendingMicReacquire = true;
    } else {
      _pendingCameraReacquire = true;
    }
    _deviceReacquireTimer?.cancel();
    _deviceReacquireTimer = Timer(const Duration(seconds: 1), () {
      final mic = _pendingMicReacquire;
      final camera = _pendingCameraReacquire;
      _pendingMicReacquire = false;
      _pendingCameraReacquire = false;
      final local = _localParticipant;
      if (_isDisposed || local == null) return;
      if (mic && local.audioTrackEnabled) {
        unawaited(
          local
              .enableAudio(
            setEnabled: true,
            deviceId: sharedPreferencesService.getDefaultMicrophoneId(),
          )
              .catchError((e) {
            loggingService.log('AgoraRoom: mic re-acquire failed: $e');
          }),
        );
      }
      if (camera && local.videoTrackEnabled && !local._isScreenSharing) {
        unawaited(
          local
              .enableVideo(
            setEnabled: true,
            deviceId: sharedPreferencesService.getDefaultCameraId(),
            waitForCapture: kIsWeb,
          )
              .catchError((e) {
            loggingService.log('AgoraRoom: camera re-acquire failed: $e');
          }),
        );
      }
    });
  }

  /// Latest requested high/low stream per remote UID; deduplicates the
  /// per-tile requests coming from ParticipantWidget on every layout pass.
  final Map<int, VideoStreamType> _requestedStreamTypes = {};

  /// Globally unique generation per write to [_requestedStreamTypes]. The
  /// apply loop compares generations, not values: after a disconnect+rejoin
  /// with the same UID the rejoined tile re-requests the SAME stream type,
  /// which value equality cannot distinguish from "unchanged since read" —
  /// the loop would either discard the fresh request on failure or skip the
  /// (server-side reset) re-subscribe on success. The counter never resets,
  /// so a rewrite is detectable even across removals.
  final Map<int, int> _streamTypeWriteGen = {};
  int _streamTypeWriteCounter = 0;

  /// UIDs with an apply loop currently running. Callers are unawaited layout
  /// passes, so without serialization two in-flight requests for one UID can
  /// reach the SDK out of order while the map already records the newest
  /// preference — leaving a stale subscription that dedupe then never
  /// corrects. One loop per UID applies requests strictly in order and picks
  /// up preferences that change mid-flight.
  final Set<int> _streamTypeApplyInFlight = {};

  /// Subscribes to the high- or low-quality stream of [uid]. Called by
  /// ParticipantWidget based on rendered tile size. No-op when the requested
  /// type is already active.
  Future<void> setPreferredRemoteVideoStreamType(
    int uid,
    VideoStreamType streamType,
  ) async {
    if (_isDisposed) return;
    if (_requestedStreamTypes[uid] == streamType) return;
    _requestedStreamTypes[uid] = streamType;
    _streamTypeWriteGen[uid] = ++_streamTypeWriteCounter;
    if (_streamTypeApplyInFlight.contains(uid)) return;

    _streamTypeApplyInFlight.add(uid);
    try {
      int? appliedGen;
      while (!_isDisposed) {
        // Re-read after every await: the desired type may have changed while
        // the previous apply was in flight (or been removed on user offline).
        final desired = _requestedStreamTypes[uid];
        final generation = _streamTypeWriteGen[uid];
        if (desired == null || generation == appliedGen) break;
        if (!await _applyRemoteVideoStreamType(uid, desired)) {
          if (_streamTypeWriteGen[uid] == generation) {
            // Entry unchanged since we read it — drop it so the next layout
            // pass retries.
            _requestedStreamTypes.remove(uid);
            _streamTypeWriteGen.remove(uid);
            break;
          }
          // Rewritten while this (failed) apply was in flight — possibly with
          // an equal value (rejoin) — never discard it; loop to apply it.
          // Bounded: each pass through here requires a fresh mid-await write.
          continue;
        }
        appliedGen = generation;
        // Low-frequency (tile threshold crossings only); kept as a release
        // breadcrumb because QA diagnoses stream selection from logs.
        loggingService.log('AgoraRoom: remote $uid stream type → $desired');
      }
    } finally {
      _streamTypeApplyInFlight.remove(uid);
    }
  }

  /// Platform call behind [setPreferredRemoteVideoStreamType]; returns true
  /// when the type was applied.
  Future<bool> _applyRemoteVideoStreamType(
    int uid,
    VideoStreamType streamType,
  ) async {
    // iris-web stubs the engine API; go through the JS client bridge instead.
    if (kIsWeb) {
      if (!_webDualStreamActive) {
        // Not active (yet): either the bridge is unavailable, or the
        // post-join activation hasn't completed. Fail so the next layout
        // pass issues the real call — _applyWebSubscriberOptimizations
        // notifies listeners after activation to trigger that pass.
        return false;
      }
      try {
        // false = uid not visible to the web client yet.
        return await jsSetRemoteVideoStreamType(uid, streamType.value());
      } catch (e) {
        loggingService.log(
          'AgoraRoom: bridge setRemoteVideoStreamType($uid, $streamType) '
          'failed: $e',
        );
        return false;
      }
    }

    try {
      await engine.setRemoteVideoStreamType(uid: uid, streamType: streamType);
      return true;
    } catch (e) {
      loggingService.log(
        'AgoraRoom: setRemoteVideoStreamType($uid, $streamType) failed: $e',
      );
      return false;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pendingScreenUids.clear();
    _clearUnresolvedJoins();
    _deviceReacquireTimer?.cancel();
    _manualFallbackProbeTimer?.cancel();
    if (kIsWeb) {
      _webDualStreamActive = false;
      _webDualStreamSetup = null;
      unawaited(jsSetWakeLock(false).catchError((_) => false));
    }

    final eng = _engine;
    if (eng == null) {
      super.dispose();
      return;
    }

    try {
      eng.unregisterEventHandler(_rtcEngineEventHandler);
    } catch (e) {
      loggingService.log('Error unregistering event handler: $e');
    }

    // Stop screen share engine if active OR if joinChannel is still in-flight.
    // _isScreenSharing is only set true after joinChannel completes, so also
    // check screenEngine != null to catch the window where startScreenShare is
    // awaiting joinChannel — otherwise the engine stays connected ~90s.
    final participant = _localParticipant;
    if (participant != null &&
        (participant.isScreenSharing || participant.screenEngine != null)) {
      unawaited(participant.stopScreenShare());
    }

    // super.dispose() is called synchronously below; the async block holds
    // its own reference to `eng` and completes independently.
    unawaited(() async {
      try {
        await eng.stopPreview();
      } catch (e) {
        loggingService.log('Error stopping preview: $e');
      }

      try {
        if (kIsWeb) {
          await eng.muteLocalVideoStream(false);
        }
        await eng.enableLocalVideo(false);
      } catch (e) {
        loggingService.log('Error disabling video: $e');
      }

      try {
        // Web: best-effort unmute before disableLocalAudio; if it throws (muted +
        // unpublished disables the track), still run enableLocalAudio(false).
        if (kIsWeb) {
          try {
            await eng.muteLocalAudioStream(false);
          } catch (e) {
            loggingService.log('dispose: web muteLocalAudioStream(false): $e');
          }
        }
        await eng.enableLocalAudio(false);
      } catch (e) {
        loggingService.log('Error disabling audio: $e');
      }

      try {
        await eng.leaveChannel();
      } catch (e) {
        loggingService.log('Error leaving channel: $e');
      }

      try {
        await eng.release();
      } catch (e) {
        loggingService.log('Error releasing engine: $e');
      }
    }());

    super.dispose();
  }
}

class VideoTrack {
  final bool isStarted;
  final bool isEnabled;
  final Size dimensions;

  VideoTrack({
    required this.isStarted,
    required this.isEnabled,
    required this.dimensions,
  });
}

class AgoraParticipant with ChangeNotifier {
  AgoraParticipant({
    RtcEngine? rtcEngine,
    // Agora user Id
    required this.agoraUid,
    required this.isLocal,
    // User ID in the app
    required this.userId,
    this.token,
    AgoraRoom? owningRoom,
  })  : _rtcEngineObj = rtcEngine,
        _owningRoom = owningRoom;

  RtcEngine? get _rtcEngineOrNull => _rtcEngineObj;
  RtcEngine get _rtcEngine {
    final engine = _rtcEngineObj;
    if (engine == null) {
      throw StateError('AgoraParticipant used before its RtcEngine was ready');
    }
    return engine;
  }

  final RtcEngine? _rtcEngineObj;
  final AgoraRoom? _owningRoom;
  final int agoraUid;
  final String userId;
  final bool isLocal;
  final String? token;

  String get identity => userId;

  QualityType networkQualityLevel = QualityType.qualityUnknown;

  /// Normalized link qualities from onNetworkQuality — local participant
  /// only (web reports only uid 0, so these stay unknown on remotes).
  /// Uplink = what others receive from us; downlink = what we receive.
  QualityType uplinkQuality = QualityType.qualityUnknown;
  QualityType downlinkQuality = QualityType.qualityUnknown;

  int? volume = 0;

  bool audioTrackEnabled = true;

  bool videoLocalPreviewStarted = false;
  bool videoTrackEnabled = true;
  // Camera state at the moment web canvas sharing began; used to restore on stop.
  bool _preSharingCameraState = false;

  Completer<void>? _localVideoStart;

  bool get isWaitingForLocalVideoStart {
    final c = _localVideoStart;
    return c != null && !c.isCompleted;
  }

  void beginLocalVideoStartWait() {
    _localVideoStart = Completer<void>();
  }

  void completeLocalVideoStart({Object? error}) {
    final c = _localVideoStart;
    if (c == null || c.isCompleted) return;
    if (error == null) {
      c.complete();
    } else {
      c.completeError(error);
    }
  }

  Future<void> waitForLocalVideoStart({
    required Duration timeout,
    required bool required,
  }) async {
    final c = _localVideoStart;
    if (c == null) return;
    try {
      await c.future.timeout(timeout);
    } on TimeoutException {
      if (required) {
        throw Exception(kGumNotReadableError);
      }
    } finally {
      _localVideoStart = null;
    }
  }

  bool _isScreenSharing = false;
  bool get isScreenSharing => _isScreenSharing;

  // Secondary Agora engine used for the screen share connection (separate UID).
  RtcEngine? _screenEngine;
  RtcEngine? get screenEngine => _screenEngine;

  int? _screenAgoraUid;
  int? get screenAgoraUid => _screenAgoraUid;

  /// Web canvas compositor: unique [HtmlElementView] factory id per share session
  /// so Flutter allocates a fresh platform-view slot after stop removes the DOM node.
  int _webCanvasCompositorSession = 0;
  String? _webCanvasCompositorPreviewViewType;
  String? get webCanvasCompositorPreviewViewType =>
      _webCanvasCompositorPreviewViewType;

  void setScreenSharing(bool value) {
    if (_isScreenSharing == value) return;
    _isScreenSharing = value;
    notifyListeners();
  }

  /// Firestore sync for remote participants (screen UID from dual-engine path).
  void syncRemoteScreenShare({required bool sharing, int? screenUid}) {
    _applyScreenShare(uid: sharing ? screenUid : null, sharing: sharing);
  }

  /// Sets both fields atomically and notifies once.  Used by AgoraRoom event
  /// handlers that would otherwise produce three consecutive notifications.
  void _applyScreenShare({required int? uid, required bool sharing}) {
    if (_screenAgoraUid == uid && _isScreenSharing == sharing) return;
    _screenAgoraUid = uid;
    _isScreenSharing = sharing;
    notifyListeners();
  }

  /// True once publishMicrophoneTrack has been turned on for this session.
  /// The mic track is published on the first unmute and stays published for
  /// the rest of the meeting; mute/unmute after that is a pure
  /// muteLocalAudioStream toggle. Unpublishing on every mute forced a WebRTC
  /// renegotiation round-trip per toggle — the source of multi-second
  /// mute/unmute delays on congested connections. A muted published track
  /// sends effectively nothing.
  bool _micTrackPublished = false;

  Future<void> enableAudio({required bool setEnabled, String? deviceId}) async {
    if (_rtcEngineOrNull == null) {
      loggingService.log('enableAudio: skipped, engine not ready');
      return;
    }
    if (setEnabled) {
      if (deviceId != null) {
        try {
          await _rtcEngine.getAudioDeviceManager().setRecordingDevice(deviceId);
        } catch (e) {
          print('Error setting device ID $deviceId');
        }
      }

      // Use muteLocalAudioStream instead of enableLocalAudio to avoid
      // re-acquiring the microphone from the OS, which causes delay.
      if (!_micTrackPublished) {
        // One-time publish (renegotiation). Must happen before unmuting:
        // iris-web disables the track while unpublished, and
        // muteLocalAudioStream(false) on a disabled track throws.
        await _rtcEngine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishMicrophoneTrack: true,
          ),
        );
        _micTrackPublished = true;
      }

      if (kIsWeb) {
        await _muteLocalAudioStreamWeb(_rtcEngine, false);
      } else {
        await _rtcEngine.muteLocalAudioStream(false);
      }
    } else {
      // Mute only — keep the track published so the next unmute is instant.
      // On web the benign-error wrapper covers the never-published case,
      // where the track is still disabled.
      if (kIsWeb) {
        await _muteLocalAudioStreamWeb(_rtcEngine, true);
      } else {
        await _rtcEngine.muteLocalAudioStream(true);
      }
    }
    audioTrackEnabled = setEnabled;
  }

  /// Re-applies camera quality settings after the camera track (re)starts.
  ///
  /// iris-web applies setVideoEncoderConfiguration only to tracks that exist
  /// at call time and never re-reads the stored config at track creation, so
  /// the pre-join call in _applyBandwidthOptimizations cannot reach a camera
  /// turned on later (measured: such tracks published at the 640x480 SDK
  /// default). It also drops degradationPreference in translation, so the
  /// web equivalent (optimizationMode 'motion' = maintainFramerate) is set
  /// through the bridge on the live track.
  Future<void> _applyCameraTrackSettingsWeb() async {
    if (!kIsWeb) return;
    try {
      // Target, not the fixed config: respects the uplink-degraded tier.
      await _rtcEngine.setVideoEncoderConfiguration(_cameraEncoderTarget);
    } catch (e) {
      loggingService.log('enableVideo: setVideoEncoderConfiguration: $e');
    }
    if (jsAgoraClientBridgeAvailable()) {
      try {
        await jsSetLocalVideoOptimizationMode('motion');
      } catch (e) {
        loggingService.log('enableVideo: setLocalVideoOptimizationMode: $e');
      }
    }
  }

  Future<void> enableVideo({
    required bool setEnabled,
    String? deviceId,
    bool waitForCapture = false,
  }) async {
    // While the canvas compositor is running on web, the peer connection's
    // video sender is holding the canvas track.  Any Agora API call that
    // publishes or unpublishes the camera track would call
    // sender.replaceTrack(cameraTrack / null), destroying the compositor.
    // Instead, just track the logical state and let stopScreenShare restore
    // the correct physical state when sharing ends.
    if (kIsWeb && _isScreenSharing) {
      videoTrackEnabled = setEnabled;
      return;
    }

    if (_rtcEngineOrNull == null) {
      loggingService.log('enableVideo: skipped, engine not ready');
      return;
    }

    if (setEnabled) {
      final hadPreviewBefore = videoLocalPreviewStarted;
      final confirmCapture = shouldConfirmLocalVideoCapture(
        isWeb: kIsWeb,
        waitForCapture: waitForCapture,
        captureAlreadyAvailable: _owningRoom?.videoCaptureAvailable ?? false,
      );
      if (confirmCapture) {
        beginLocalVideoStartWait();
      }
      try {
        if (!videoLocalPreviewStarted) {
          await _rtcEngine.startPreview();
        }

        if (deviceId != null) {
          try {
            await _rtcEngine.getVideoDeviceManager().setDevice(deviceId);
          } catch (e) {
            print('Error setting device ID $deviceId');
          }
        }

        // Web SDK (iris-web): cannot call track setEnabled while the track is
        // still muted — publishing-off / mute keeps muted until cleared.
        if (kIsWeb) {
          await _rtcEngine.muteLocalVideoStream(false);
        }
        await _rtcEngine.enableLocalVideo(true);
        await _rtcEngine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishCameraTrack: true,
          ),
        );
        if (confirmCapture) {
          await waitForLocalVideoStart(
            timeout: const Duration(seconds: 2),
            required: true,
          );
          // Capturing can fire and then immediately fail; don't publish
          // a black tile if capture is already gone.
          if (_owningRoom?.videoCaptureAvailable != true) {
            throw Exception(kGumNotReadableError);
          }
        }
        videoLocalPreviewStarted = true;
        // Track exists now — apply encoder settings that the pre-join config
        // can't reach on web. Fire-and-forget: must not delay camera-on.
        unawaited(_applyCameraTrackSettingsWeb());
      } catch (e) {
        _localVideoStart = null;
        _owningRoom?.videoCaptureAvailable = false;
        if (!hadPreviewBefore) {
          videoLocalPreviewStarted = false;
          try {
            await _rtcEngine.stopPreview();
          } catch (_) {}
        }
        rethrow;
      }
    } else {
      try {
        await _rtcEngine.updateChannelMediaOptions(
          ChannelMediaOptions(
            publishCameraTrack: false,
          ),
        );
        if (kIsWeb) {
          videoLocalPreviewStarted = false;
          try {
            await _rtcEngine.stopPreview();
          } catch (e) {
            loggingService.log('enableVideo(off): stopPreview: $e');
          }
        } else {
          await _rtcEngine.enableLocalVideo(false);
          videoLocalPreviewStarted = false;
        }
      } finally {
        _owningRoom?.videoCaptureAvailable = false;
      }
    }

    videoTrackEnabled = setEnabled;
  }

  /// The canvas compositor replaces every live video sender on the peer
  /// connection. With dual-stream on, that includes the low (simulcast)
  /// sender, which would then carry the full-res canvas track through a
  /// 320×180 encoder. Pause dual-stream for the duration of the share.
  Future<void> _pauseWebDualStreamForShare() async {
    if (!kIsWeb) return;
    // The post-join activation may still be in flight (a share started right
    // after a breakout join races it); settle it first so the flag below is
    // truthful and the low sender exists to be disabled.
    final setup = _webDualStreamSetup;
    if (setup != null) {
      try {
        await setup;
      } catch (_) {
        // Activation failures are logged where they occur.
      }
    }
    if (!_webDualStreamActive) return;
    try {
      await jsDisableDualStream();
    } catch (e) {
      loggingService.log('[screenShare] disable dual stream failed: $e');
    }
  }

  Future<void> _resumeWebDualStreamAfterShare() async {
    if (!kIsWeb || !_webDualStreamActive) return;
    try {
      await jsEnableDualStream(
        width: _kLowStreamWidth,
        height: _kLowStreamHeight,
        framerate: _kLowStreamFps,
        bitrateKbps: _kLowStreamKbps,
      );
    } catch (e) {
      loggingService.log('[screenShare] re-enable dual stream failed: $e');
    }
  }

  /// Starts screen sharing.
  ///
  /// **Web (canvas compositor path):**
  /// Composites the screen and a camera PiP onto a 1280×720 `<canvas>` using a
  /// `requestAnimationFrame` loop, captures the canvas as a `MediaStreamTrack`,
  /// and injects it into the Agora peer connection via `RTCRtpSender.replaceTrack`.
  /// This bypasses iris-web's broken `publishScreenCaptureVideo` path (which
  /// captures locally but never publishes to remote participants) and requires no
  /// second engine, no Mux, and no extra Agora UID.
  ///
  /// **Native (dual-engine path):**
  /// The screen UID is `uidToInt(userId) | (1 << 30)`. Falls back to
  /// single-engine mode when [screenShareToken] is null.
  Future<void> startScreenShare({
    required String channelName,
    required String? screenShareToken,

    /// Called when the browser-native "Stop sharing" button fires (web) or when
    /// the screen engine stops due to token expiry / connection failure (native).
    /// The caller (ConferenceRoom) uses this to write screenSharingUserId=null
    /// to Firestore, which the participant layer cannot do directly.
    void Function()? onNativeStop,

    /// Native dual-engine only: screen engine [RtcEngineEventHandler.onVideoSizeChanged].
    /// Forward to [AgoraRoom.applyReportedVideoFrameSize] so local screen tiles match aspect.
    void Function(int uid, int width, int height, int rotation)?
        onScreenEngineVideoSizeChanged,
  }) async {
    if (kIsWeb) {
      // Snapshot camera state before we mutate it; both stopScreenShare and the
      // browser-native-stop callback restore from _preSharingCameraState.
      _preSharingCameraState = videoTrackEnabled;
      if (!_preSharingCameraState) {
        final hadPreviewBefore = videoLocalPreviewStarted;
        try {
          if (!videoLocalPreviewStarted) {
            await _rtcEngine.startPreview();
          }
          await _rtcEngine.muteLocalVideoStream(false);
          await _rtcEngine.enableLocalVideo(true);
          // Do NOT set videoTrackEnabled=true here. It reflects user intent only.
          // _preSharingCameraState records the physical enable; stopScreenShare
          // uses videoTrackEnabled to decide what to restore.
          await _rtcEngine.updateChannelMediaOptions(
            const ChannelMediaOptions(publishCameraTrack: true),
          );
          videoLocalPreviewStarted = true;
        } catch (e) {
          if (!hadPreviewBefore) {
            videoLocalPreviewStarted = false;
            try {
              await _rtcEngine.stopPreview();
            } catch (_) {}
          }
          _preSharingCameraState = false; // camera was off, stays off
          rethrow;
        }
      }

      // Register a callback for the browser-native "Stop sharing" button.
      // JS already restored the sender track; restore Agora camera state and
      // notify the caller (ConferenceRoom) so it can clear Firestore state.
      jsSetCanvasScreenShareStoppedCallback(() {
        if (!_isScreenSharing) return;
        _isScreenSharing = false;
        _webCanvasCompositorPreviewViewType = null;
        // Use videoTrackEnabled (not _preSharingCameraState) — same reasoning
        // as stopScreenShare: it reflects all mid-share toggles.
        if (!videoTrackEnabled) {
          unawaited(
            _rtcEngine
                .updateChannelMediaOptions(
                  const ChannelMediaOptions(publishCameraTrack: false),
                )
                .catchError((_) {}),
          );
          videoLocalPreviewStarted = false;
          unawaited(_rtcEngine.stopPreview().catchError((_) {}));
        }
        unawaited(_resumeWebDualStreamAfterShare());
        onNativeStop?.call();
        notifyListeners();
      });

      // Must complete before the compositor collects senders below, so the
      // low-stream sender is gone before tracks are replaced.
      await _pauseWebDualStreamForShare();

      // null = user cancelled picker, true = success, false = API failure.
      bool? startResult;
      Object? startError;
      try {
        startResult = await jsStartCanvasScreenShare(null);
      } catch (e) {
        loggingService.log('[startScreenShare] canvas compositor error: $e');
        startError = e; // preserve for rethrow — don't swallow real exceptions
      }

      if (startResult != true) {
        // Share never started — restore dual-stream publishing.
        await _resumeWebDualStreamAfterShare();
        // Roll back any camera we enabled just for the compositor.
        if (!_preSharingCameraState) {
          await _rtcEngine
              .updateChannelMediaOptions(
                const ChannelMediaOptions(publishCameraTrack: false),
              )
              .catchError((_) {});
          videoLocalPreviewStarted = false;
          try {
            await _rtcEngine.stopPreview();
          } catch (_) {}
          // videoTrackEnabled was never set true (we stopped updating it in
          // the enable block), so no change needed here.
        } else if (videoTrackEnabled) {
          // Camera was on before the attempt. The compositor may have
          // replaced some senders before failing (its cleanup restores the
          // saved tracks best-effort), so re-assert the published, unmuted
          // state rather than assuming it survived — QA observed a failed
          // main-room start leaving zero outbound video.
          try {
            await _rtcEngine.muteLocalVideoStream(false);
            await _rtcEngine.updateChannelMediaOptions(
              const ChannelMediaOptions(publishCameraTrack: true),
            );
          } catch (e) {
            loggingService.log(
              '[startScreenShare] camera re-assert after failed start: $e',
            );
          }
          unawaited(_applyCameraTrackSettingsWeb());
        }
        if (startError != null) {
          // Unexpected Dart exception → surface it (shows error dialog).
          Error.throwWithStackTrace(startError, StackTrace.current);
        }
        if (startResult == null) {
          // User pressed Cancel in the browser picker — silent, no error dialog.
          throw const ScreenShareCancelledException();
        }
        throw Exception('Canvas screen share failed to start');
      }

      // Encoder targets the published camera sender; canvas uses replaceTrack().
      // iris-web applies this after swap (best-effort). bitrate 0 = standard auto Kbps
      // for dimensions+fps; maintainResolution avoids aspect-skewing resize under stress.
      final px = jsGetCanvasCompositorPixelSize();
      final cw = (px != null && px.length >= 2) ? px[0] : 1920;
      final ch = (px != null && px.length >= 2) ? px[1] : 1080;
      final encDims = _evenEncoderDimensions(cw, ch);
      try {
        await _rtcEngine.setVideoEncoderConfiguration(
          VideoEncoderConfiguration(
            dimensions: encDims,
            frameRate: _kCanvasShareEncoderFrameRate,
            bitrate: 0,
            degradationPreference: DegradationPreference.maintainResolution,
          ),
        );
        loggingService.log(
          '[startScreenShare] encoder ${encDims.width}x${encDims.height} '
          '@${_kCanvasShareEncoderFrameRate}fps bitrate=standard iris-web',
        );
      } catch (e) {
        loggingService
            .log('[startScreenShare] setVideoEncoderConfiguration: $e');
      }

      _webCanvasCompositorSession++;
      _webCanvasCompositorPreviewViewType =
          'canvas-compositor-preview-$_webCanvasCompositorSession';
      _isScreenSharing = true;
      notifyListeners();
      return;
    }

    if (screenShareToken == null) {
      // Single-engine path: screen capture published on the main connection.
      // NOTE: publishScreenCaptureVideo on the main connection does NOT publish
      // to remote participants in iris-web — kept only as a non-web fallback.
      await _rtcEngine.startScreenCapture(
        const ScreenCaptureParameters2(captureVideo: true, captureAudio: false),
      );
      try {
        await _rtcEngine.updateChannelMediaOptions(
          const ChannelMediaOptions(publishScreenCaptureVideo: true),
        );
        await _rtcEngine.startPreview(
          sourceType: VideoSourceType.videoSourceScreen,
        );
      } catch (e) {
        await _rtcEngine.stopScreenCapture().catchError((_) {});
        await _rtcEngine
            .updateChannelMediaOptions(
              const ChannelMediaOptions(publishScreenCaptureVideo: false),
            )
            .catchError((_) {});
        rethrow;
      }
      _isScreenSharing = true;
      notifyListeners();
      return;
    }

    final screenUid = uidToInt(userId) | (1 << 30);
    _screenAgoraUid = screenUid;

    final eng = createAgoraRtcEngine();
    _screenEngine = eng;
    try {
      await eng.initialize(
        RtcEngineContext(appId: _kAgoraAppId),
      );
      eng.registerEventHandler(
        RtcEngineEventHandler(
          onTokenPrivilegeWillExpire: (connection, token) {
            print('[screenEngine] token will expire, stopping screen share');
            final wasSharing = _isScreenSharing;
            unawaited(() async {
              await stopScreenShare();
              if (wasSharing) onNativeStop?.call();
            }());
          },
          onConnectionStateChanged: (connection, state, reason) {
            // Only stop on permanent failure — disconnected is transient.
            if (state == ConnectionStateType.connectionStateFailed) {
              print(
                  '[screenEngine] connection failed ($reason), stopping screen share');
              final wasSharing = _isScreenSharing;
              unawaited(() async {
                await stopScreenShare();
                if (wasSharing) onNativeStop?.call();
              }());
            }
          },
          onVideoSizeChanged: (
            RtcConnection connection,
            VideoSourceType _,
            int uid,
            int width,
            int height,
            int rotation,
          ) {
            onScreenEngineVideoSizeChanged?.call(
              uid,
              width,
              height,
              rotation,
            );
          },
        ),
      );
      await eng.startScreenCapture(
        const ScreenCaptureParameters2(captureVideo: true, captureAudio: false),
      );
      await eng.joinChannel(
        token: screenShareToken,
        channelId: channelName,
        uid: screenUid,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
          publishScreenCaptureVideo: true,
          publishCameraTrack: false,
          publishMicrophoneTrack: false,
          autoSubscribeAudio: false,
          autoSubscribeVideo: false,
        ),
      );
    } catch (e) {
      // Clear refs first so dispose() never retries a broken engine.
      _screenEngine = null;
      _screenAgoraUid = null;
      // Best-effort cleanup — mirror stopScreenShare ordering.
      try {
        await eng.stopScreenCapture();
      } catch (_) {}
      try {
        await eng.leaveChannel();
      } catch (_) {}
      try {
        await eng.release();
      } catch (_) {}
      rethrow;
    }
    _isScreenSharing = true;
    notifyListeners();
  }

  Future<void> stopScreenShare() async {
    // Also check _screenEngine: dispose() calls this during the joinChannel
    // window where _isScreenSharing is still false but the engine is live.
    if (!_isScreenSharing && _screenEngine == null) return;
    // Notify before async cleanup so the camera tile is rendered while
    // cleanup runs asynchronously.
    _isScreenSharing = false;
    if (kIsWeb) {
      _webCanvasCompositorPreviewViewType = null;
    }
    notifyListeners();

    if (kIsWeb) {
      // Reset pre-sharing state so stale values never bleed into the next share.
      _preSharingCameraState = false;
      // Canvas compositor path: stop the compositor and restore the sender.
      await jsStopCanvasScreenShare().catchError((e) {
        loggingService
            .log('[stopScreenShare] canvas compositor stop error: $e');
      });

      // Resume dual-stream publishing (paused while the compositor owned the
      // video senders).
      unawaited(_resumeWebDualStreamAfterShare());

      // videoTrackEnabled is the sole source of truth for camera intent.
      // The enableVideo guard deferred all Agora API calls during sharing, so
      // this flag already reflects every mid-share camera toggle correctly —
      // regardless of what _preSharingCameraState was.
      if (videoTrackEnabled) {
        final hadPreviewBefore = videoLocalPreviewStarted;
        try {
          if (!videoLocalPreviewStarted) {
            await _rtcEngine.startPreview();
          }
          await _rtcEngine.muteLocalVideoStream(false);
          videoLocalPreviewStarted = true;
        } catch (e) {
          if (!hadPreviewBefore) {
            videoLocalPreviewStarted = false;
            try {
              await _rtcEngine.stopPreview();
            } catch (_) {}
          }
          loggingService.log('[stopScreenShare] re-enable camera error: $e');
        }
      } else {
        await _rtcEngine
            .updateChannelMediaOptions(
              const ChannelMediaOptions(publishCameraTrack: false),
            )
            .catchError((_) {});
        videoLocalPreviewStarted = false;
        try {
          await _rtcEngine.stopPreview();
        } catch (e) {
          loggingService.log('[stopScreenShare] camera-off stopPreview: $e');
        }
      }

      // Restore camera encoder settings (raised for screen share). Must run
      // after the camera-restore above: a camera turned on mid-share only
      // gets its track created by that startPreview, and iris applies config
      // to existing tracks only.
      unawaited(_applyCameraTrackSettingsWeb());
      return;
    }

    if (_screenEngine != null) {
      final eng = _screenEngine!;
      _screenEngine = null;
      _screenAgoraUid = null;
      try {
        await eng.stopScreenCapture();
      } catch (e) {
        print('[stopScreenShare] stopScreenCapture error: $e');
      }
      try {
        await eng.leaveChannel();
      } catch (e) {
        print('[stopScreenShare] leaveChannel error: $e');
      }
      try {
        await eng.release();
      } catch (e) {
        print('[stopScreenShare] release error: $e');
      }
    } else {
      // Legacy single-engine (non-web fallback): tear down screen capture only.
      // No publishCameraTrack restore — same as web/dual-engine, camera publish
      // state is whatever videoTrackEnabled already reflects (stays off if it
      // was off before share).
      try {
        await _rtcEngine.stopPreview(
          sourceType: VideoSourceType.videoSourceScreen,
        );
      } catch (e) {
        print('[stopScreenShare] legacy stopPreview error: $e');
      }
      try {
        await _rtcEngine.stopScreenCapture();
      } catch (e) {
        print('[stopScreenShare] legacy stopScreenCapture error: $e');
      }
      try {
        await _rtcEngine.updateChannelMediaOptions(
          const ChannelMediaOptions(publishScreenCaptureVideo: false),
        );
      } catch (e) {
        print('[stopScreenShare] legacy updateChannelMediaOptions error: $e');
      }
    }
  }

  Future<void> toggleMuteOverride({required bool isMuted}) async {
    await _rtcEngine.muteRemoteAudioStream(uid: agoraUid, mute: isMuted);
  }
}
