import 'dart:async';
import 'dart:js_interop';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:beamer/beamer.dart';
import 'package:client/core/utils/navigation_utils.dart';
import 'package:client/core/utils/random_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/providers/meeting_guide_card_store.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_error.dart';
import 'package:client/features/events/features/live_meeting/features/video/utils/debug.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/data/providers/meeting_agenda_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/confirm_dialog.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:data_models/events/event.dart' hide Participant;
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:pedantic/pedantic.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:synchronized/synchronized.dart';
import 'package:client/core/utils/js_interop_bridge.dart';
import 'package:data_models/utils/utils.dart';
import 'package:universal_html/html.dart' as html;

import '../../../../../../../../core/routing/locations.dart';
import 'agora_room.dart';
import 'video_capture_confirm.dart';

class FakeParticipant extends AgoraParticipant {
  final int id;

  FakeParticipant({required this.id, required bool isLocal})
      : super(
          rtcEngine: null,
          agoraUid: id,
          userId: id.toString(),
          isLocal: isLocal,
        );

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  String get identity => userId;

  @override
  QualityType get networkQualityLevel => QualityType.qualityGood;

  @override
  String get userId => id.toString();

  String get state => 'connected';
}

class VideoParticipant implements MeetingProviderParticipant {
  final AgoraParticipant participant;
  final Event event;
  final String eventPath;

  VideoParticipant(this.participant, this.event, this.eventPath);

  @override
  bool get audioOn => participant.audioTrackEnabled;

  @override
  bool get local => participant.isLocal;

  @override
  String get sessionId => participant.userId;

  @override
  String get userId => participant.identity;

  @override
  Future<void> mute() {
    loggingService.log('muting: $userId');
    return firestoreLiveMeetingService.updateParticipantMuteOverride(
      event: event,
      participantId: userId,
      muteOverride: true,
    );
  }
}

class ConferenceRoom with ChangeNotifier {
  final LiveMeetingProvider liveMeetingProvider;
  final AgendaProvider agendaProvider;
  final CommunityProvider communityProvider;
  final MeetingGuideCardStore meetingGuideCardModel;
  final String token;
  final String roomName;
  final String? screenShareToken;

  ConferenceRoom({
    required this.liveMeetingProvider,
    required this.agendaProvider,
    required this.communityProvider,
    required this.meetingGuideCardModel,
    required this.token,
    required this.roomName,
    this.screenShareToken,
  }) {
    onException = _onExceptionStreamController.stream;
    Debug.enabled = true;
  }

  final StreamController<Exception> _onExceptionStreamController =
      StreamController<Exception>.broadcast();
  late Stream<Exception> onException;

  final Completer<AgoraRoom> _completer = Completer<AgoraRoom>();

  final List<StreamSubscription> _streamSubscriptions = [];

  final participantInitializationTimers = <String, Timer>{};

  final _audioTogglingLock = Lock();
  final _videoTogglingLock = Lock();

  List<AgoraParticipant> _orderedParticipants = [];

  StreamSubscription? _unraiseHandSubscription;

  /// List of users who have been muted by the host. All participants mute their audio streams until
  /// they unmute themselves.
  final _currentlyMutedUsers = <String>{};

  AgoraRoom? _room;
  bool hasStartedConnecting = false;
  String? _connectError;
  bool _isDisposed = false;

  int _numFakeParticipants = 0;

  int get numFakeParticipants => _numFakeParticipants;

  set numFakeParticipants(int value) {
    _numFakeParticipants = value;
    notifyListeners();
  }

  int get maxHighlightedParticipants {
    return liveMeetingProvider.showGuideCard &&
            !liveMeetingProvider.isMeetingCardMinimized
        ? 1
        : 2;
  }

  String? get connectError => _connectError;

  Future<AgoraRoom> get connectionFuture => _completer.future;
  bool flashEnabled = false;

  bool get audioEnabled => _room?.localParticipant?.audioTrackEnabled ?? false;

  bool get videoEnabled {
    return _room?.localParticipant?.videoTrackEnabled ?? false;
  }

  List<AgoraParticipant> get handRaisedParticipants => _orderedParticipants
      .where((p) => meetingGuideCardModel.getHandRaisedTime(p.identity) != null)
      .toList();

  /// True only when this client is actively publishing screen share (Agora/compositor).
  /// Do not use [screenSharerUserId] here — that reflects meeting-wide Firestore state
  /// and would block local mic/camera for non-sharers while someone else is sharing.
  bool get isLocalSharingScreenActive =>
      _room?.localParticipant?.isScreenSharing ?? false;

  String? get screenSharerUserId {
    // Prefer the participant flag (set by _updateScreenSharingParticipants).
    // Fall back to Firestore: remote viewers may see the compositor track on the
    // sharer's camera UID before isScreenSharing is synced on the participant.
    return participants.firstWhereOrNull((p) => p.isScreenSharing)?.identity ??
        agendaProvider.currentLiveMeeting?.screenSharingUserId ??
        liveMeetingProvider.liveMeeting?.screenSharingUserId;
  }

  AgoraParticipant? get screenSharer {
    final id = screenSharerUserId;
    if (id == null) return null;
    return participants.firstWhereOrNull((p) => p.identity == id);
  }

  String? get screenSharePath =>
      agendaProvider.currentLiveMeeting?.screenSharePath ??
      liveMeetingProvider.liveMeeting?.screenSharePath;

  AgoraRoom? get room => _room;

  String? get dominantSpeakerSid =>
      _debouncedDominantSpeakerStream?.value?.userId;
  BehaviorSubjectWrapper<AgoraParticipant?>? _debouncedDominantSpeakerStream;
  StreamSubscription<AgoraParticipant?>? _debouncedDominantSpeakerSubscription;

  /// Returns an ordered list of participants to be displayed on screen.
  ///
  /// In order to keep a consistent ordering the determined ordering is stored in
  /// [_orderedParticipants] and that is used to initialize the ordering. They are then sorted by
  /// hand raise status and the dominant speaker is placed in the front. The final ordering is then
  /// stored again in [_orderedParticipants].
  List<AgoraParticipant> get participants {
    final localParticipant = _room?.localParticipant;
    final participantsCopy = <AgoraParticipant>[
      if (localParticipant != null) localParticipant,
      ..._room?.remoteParticipants ?? [],
    ];

    final newOrderedList = <AgoraParticipant>[];

    // Add existing ordered participants in order.
    for (final participant in _orderedParticipants) {
      final existingIndex =
          participantsCopy.indexWhere((p) => p.userId == participant.userId);
      if (existingIndex >= 0) {
        newOrderedList.add(participant);
        participantsCopy.removeAt(existingIndex);
      }
    }

    // Insert all new ones in at the end
    newOrderedList.addAll(participantsCopy);
    _orderedParticipants = newOrderedList;

    final localHandRaisedParticipants = handRaisedParticipants.toList();
    localHandRaisedParticipants.sort((a, b) {
      final aHandRaisedTime =
          meetingGuideCardModel.getHandRaisedTime(a.identity);
      final bHandRaisedTime =
          meetingGuideCardModel.getHandRaisedTime(b.identity);

      if (aHandRaisedTime == bHandRaisedTime) return 0;
      if (aHandRaisedTime == null) return 1;
      if (bHandRaisedTime == null) return -1;

      return aHandRaisedTime.compareTo(bHandRaisedTime);
    });

    final handRaisedIds =
        localHandRaisedParticipants.map((p) => p.userId).toSet();
    _orderedParticipants.removeWhere((p) => handRaisedIds.contains(p.userId));
    _orderedParticipants.insertAll(0, localHandRaisedParticipants);

    final dominantSpeaker = _orderedParticipants
        .firstWhereOrNull((p) => p.userId == dominantSpeakerSid);
    final dominantSpeakerIndex = dominantSpeaker != null
        ? _orderedParticipants.indexOf(dominantSpeaker)
        : -1;
    final shouldMoveDominantSpeaker =
        liveMeetingProvider.liveMeetingViewType == LiveMeetingViewType.stage ||
            dominantSpeakerIndex > 8 ||
            handRaisedIds.isNotEmpty;
    if (dominantSpeaker != null && shouldMoveDominantSpeaker) {
      _orderedParticipants.remove(dominantSpeaker);
      _orderedParticipants.insert(0, dominantSpeaker);
    }

    final pinnedIds =
        agendaProvider.currentLiveMeeting?.pinnedUserIds.toSet() ?? {};
    final pinnedParticipants = _orderedParticipants
        .where((p) => pinnedIds.contains(p.identity))
        .toList();
    _orderedParticipants.removeWhere((p) => pinnedIds.contains(p.identity));
    _orderedParticipants.insertAll(0, pinnedParticipants);

    return [
      ..._orderedParticipants,
      for (int i = 0; i < _numFakeParticipants; i++)
        FakeParticipant(id: i, isLocal: false),
    ];
  }

  void initialize(BuildContext context) {
    liveMeetingProvider.conferenceRoom = this;

    liveMeetingProvider.eventProvider.addListener(_muteOthersOnOverride);
    agendaProvider.addListener(_updateScreenSharingParticipants);
  }

  void _muteOthersOnOverride() {
    final mutedUsers = liveMeetingProvider.eventProvider.eventParticipants
        .where((p) => p.muteOverride)
        .map((p) => p.id)
        .toSet();

    final newlyMutedUsers = mutedUsers.difference(_currentlyMutedUsers);
    final newlyUnmutedUsers = _currentlyMutedUsers.difference(mutedUsers);

    _currentlyMutedUsers.clear();
    _currentlyMutedUsers.addAll(mutedUsers);

    for (final participant
        in _room?.remoteParticipants ?? <AgoraParticipant>[]) {
      final userId = participant.identity;

      if (newlyMutedUsers.contains(userId) ||
          newlyUnmutedUsers.contains(userId)) {
        participant.toggleMuteOverride(
          isMuted: newlyMutedUsers.contains(userId),
        );
      }
    }
  }

  Future<void> connect() async {
    Debug.log('ConferenceRoom.connect()');
    try {
      hasStartedConnecting = true;
      _room = AgoraRoom(
        channelName: roomName,
        token: token,
        screenShareToken: screenShareToken,
        liveMeetingProvider: liveMeetingProvider,
        eventProvider: liveMeetingProvider.eventProvider,
        conferenceRoom: this,
      );
      await _room!.connect();
      _room!.addListener(notifyListeners);
    } catch (err, stacktrace) {
      loggingService.log('error');
      loggingService.log(stacktrace);
      loggingService.log(err.runtimeType);

      try {
        final raw = jsCallMethod(err as JSObject, 'toString', []);
        final dart = raw?.dartify();
        _connectError = dart is String ? dart : dart?.toString();
      } catch (_) {
        _connectError = 'Unknown connection error';
      }
      notifyListeners();

      Debug.log(err);

      // Only roll back if we were actually joining a breakout room.
      // getMeetingJoinInfo() sets _activeBreakoutRoomId = null, so for main-
      // room failures activeBreakoutRoomId is null and there is no optimistic
      // getBreakoutRoomFuture write to undo.
      if (liveMeetingProvider.activeBreakoutRoomId != null) {
        liveMeetingProvider.rollbackBreakoutRoomPresence();
      }
    }
  }

  void setConnectError(String error) {
    _connectError = error;
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_isDisposed) super.notifyListeners();
  }

  @override
  void dispose() {
    loggingService.log('disposing');
    Debug.log('ConferenceRoom.dispose()');

    _isDisposed = true;
    liveMeetingProvider.conferenceRoom = null;

    if (isLocalSharingScreenActive) {
      unawaited(_writeScreenSharingState(null));
    }

    _room?.dispose();
    _updateLiveMeetingParticipants(participantsOverride: [], notify: false);
    _disposeStreamsAndSubscriptions();
    super.dispose();
  }

  void _disposeStreamsAndSubscriptions() {
    liveMeetingProvider.eventProvider.removeListener(_muteOthersOnOverride);
    agendaProvider.removeListener(_updateScreenSharingParticipants);

    _debouncedDominantSpeakerSubscription?.cancel();
    // Assigned in onConnected; dispose can run first (leave / remount / failed join).
    _unraiseHandSubscription?.cancel();
    _debouncedDominantSpeakerStream?.dispose();

    _onExceptionStreamController.close();
    for (final streamSubscription in _streamSubscriptions) {
      streamSubscription.cancel();
    }
  }

  Future<String?> _queryMediaPermission(String name) async {
    try {
      final status =
          await html.window.navigator.permissions?.query({'name': name});
      return normalizePermissionState(status?.state);
    } catch (_) {
      return null;
    }
  }

  /// null = allowed (or probe skipped). Otherwise a GUM-like error string.
  Future<String?> _requestUserMediaPermission({
    bool? audio,
    bool? video,
  }) async {
    final requestingVideo = video == true;
    final requestingAudio = audio == true;
    String? permissionState;
    if (kIsWeb) {
      if (requestingVideo) {
        permissionState = await _queryMediaPermission('camera');
      } else if (requestingAudio) {
        permissionState = await _queryMediaPermission('microphone');
      }
    }

    final action = userMediaProbeAction(
      requestingVideo: requestingVideo,
      requestingAudio: requestingAudio,
      videoCapturedThisSession: _room?.videoCapturedThisSession ?? false,
      audioCaptureAvailable: _room?.audioCaptureAvailable ?? false,
      agoraHoldsMedia: requestingVideo
          ? (_room?.videoModuleInitialized ?? false)
          : (_room?.audioCaptureAvailable ?? false),
      permissionState: permissionState,
    );
    if (action == UserMediaProbeAction.skip) return null;
    if (action == UserMediaProbeAction.denied) return kGumNotAllowedError;

    final mediaDevices = html.window.navigator.mediaDevices;
    if (mediaDevices == null) {
      return kGumNotFoundError;
    }
    late final Future<html.MediaStream> gumFuture;
    try {
      gumFuture = mediaDevices.getUserMedia({
        'audio': audio ?? false,
        'video': video ?? false,
      });
      final stream = await gumFuture.timeout(const Duration(seconds: 4));
      print('Microphone permission granted.');
      // Stop using the audio stream right away
      stream.getTracks().forEach((track) => track.stop());
      // Let the device drop before Agora re-acquires it.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return null;
    } on TimeoutException {
      // timeout() does not cancel getUserMedia. Stop a late grant so
      // those tracks cannot hold the device when Agora retries.
      reclaimTimedOutFuture<html.MediaStream>(
        gumFuture,
        onLateSuccess: (lateStream) {
          lateStream.getTracks().forEach((track) => track.stop());
        },
      );
      return kGumNotAllowedError;
    } catch (e) {
      print('Microphone permission denied.');
      print(e);
      return e.toString();
    }
  }

  Future<void> toggleVideoEnabled({
    bool? setEnabled,
    bool updateProvider = true,
  }) async {
    final updatedEnabledValue = setEnabled ?? !videoEnabled;

    if (updatedEnabledValue) {
      final probeError = await _requestUserMediaPermission(video: true);
      if (probeError != null) {
        await AudioVideoErrorDialog.show(
          navigatorState.context,
          probeError,
          inMeeting: true,
        );
        return;
      }
    }

    // Lock this code so that different sections toggling audio will not cause race conditions.
    bool executed = false;
    String? deviceError;
    try {
      await _videoTogglingLock.synchronized(
        () async {
          try {
            final participant = _room?.localParticipant;
            if (participant == null) {
              loggingService.log(
                'toggleVideoEnabled: skipped — _room or localParticipant is null',
              );
              return;
            }
            await participant.enableVideo(
              setEnabled: updatedEnabledValue,
              deviceId: sharedPreferencesService.getDefaultCameraId(),
              // Every camera-on: a stale videoCaptureAvailable skipped the wait.
              waitForCapture: kIsWeb && updatedEnabledValue,
            );
            if (updatedEnabledValue) {
              _room?.videoModuleInitialized = true;
            }
            if (updateProvider) {
              liveMeetingProvider.shouldStartLocalVideoOn = updatedEnabledValue;
            }
            executed = true;
          } catch (e) {
            loggingService.log('toggleVideoEnabled: exception: $e');
            if (isGetUserMediaError(e)) {
              // Show the dialog only after the lock is released below.
              // Awaiting it here held the lock until the user closed it, so
              // the next tap hit the 6s acquisition timeout and surfaced a
              // raw TimeoutException.
              deviceError = e.toString();
              return;
            }
            rethrow;
          }
        },
        timeout: Duration(seconds: 6),
      );
    } on TimeoutException {
      // Another toggle is still in flight (device capture can take seconds).
      // Drop this tap instead of surfacing the lock timeout to the user.
      loggingService.log('toggleVideoEnabled: toggle in progress, tap ignored');
      return;
    }
    if (deviceError != null) {
      await AudioVideoErrorDialog.show(
        navigatorState.context,
        deviceError!,
        inMeeting: true,
      );
      return;
    }
    if (executed) notifyListeners();
  }

  /// iris-web often fails camera publish without throwing. Revert the local
  /// tile so it is not a black rectangle, and show the existing AV dialog.
  Future<void> onLocalVideoCaptureFailed(String error) async {
    final participant = _room?.localParticipant;
    if (participant == null || !participant.videoTrackEnabled) return;
    if (participant.isWaitingForLocalVideoStart) return;
    try {
      await participant.enableVideo(setEnabled: false);
    } catch (_) {}
    liveMeetingProvider.shouldStartLocalVideoOn = false;
    notifyListeners();
    final context = navigatorState.context;
    if (context.mounted) {
      await AudioVideoErrorDialog.show(context, error, inMeeting: true);
    }
  }

  Future<void> toggleAudioEnabled({
    bool? setEnabled,
    bool updateProvider = true,
  }) async {
    final updatedEnabledValue = setEnabled ?? !audioEnabled;

    if (updatedEnabledValue) {
      final probeError = await _requestUserMediaPermission(audio: true);
      if (probeError != null) {
        await showAlert(
          navigatorState.context,
          'Error enabling microphone. Please ensure you have granted permission.',
        );
        return;
      }
    }

    // Lock this code so that different sections toggling audio will not cause race conditions.
    bool executed = false;
    String? deviceError;
    try {
      await _audioTogglingLock.synchronized(
        () async {
          if (updatedEnabledValue &&
              liveMeetingProvider.audioTemporarilyDisabled) {
            executed =
                true; // notify listeners so UI can reconcile toggle state
            return;
          }

          final participant = _room?.localParticipant;
          if (participant == null) {
            loggingService.log(
              'toggleAudioEnabled: skipped — _room or localParticipant is null',
            );
            return;
          }

          // Optimistic update: reflect the new state immediately so the mute
          // button responds on click instead of after the SDK round-trip
          // completes. Reverted below if the toggle fails.
          final previousEnabled = participant.audioTrackEnabled;
          participant.audioTrackEnabled = updatedEnabledValue;
          notifyListeners();

          // Tracks whether the Agora toggle itself succeeded, so the rollback
          // below never misreports live mic state: if Agora unmuted but the
          // parallel Firestore write failed, the mic IS hot and the UI must
          // keep showing unmuted.
          bool agoraToggleCompleted = false;
          try {
            final audioEnableFutures = [
              participant
                  .enableAudio(
                setEnabled: updatedEnabledValue,
                deviceId: sharedPreferencesService.getDefaultMicrophoneId(),
              )
                  .then((_) {
                agoraToggleCompleted = true;
              }),
              if ((liveMeetingProvider
                          .eventProvider.selfParticipant?.muteOverride ??
                      false) &&
                  updatedEnabledValue)
                firestoreLiveMeetingService.updateParticipantMuteOverride(
                  event: liveMeetingProvider.eventProvider.event,
                  participantId: userService.currentUserId!,
                  muteOverride: false,
                ),
            ];

            // Default (non-eager) Future.wait: all futures settle before it
            // completes, so agoraToggleCompleted is final in the catch block.
            await Future.wait(audioEnableFutures);

            if (updateProvider) {
              liveMeetingProvider.shouldStartLocalAudioOn = updatedEnabledValue;
            }
            executed = true;
          } catch (e) {
            // Covers AgoraRtcException from enableAudio and FirebaseException
            // (or any other error) from updateParticipantMuteOverride.
            if (!agoraToggleCompleted) {
              participant.audioTrackEnabled = previousEnabled;
              notifyListeners();
            } else if (updatedEnabledValue) {
              // Agora unmuted, so the failure came from the muteOverride clear
              // (the only other future). A hot mic with the override still
              // persisted would make the next self-participant snapshot treat
              // the stale override as a fresh host-mute (re-mute + "muted by
              // the host" toast). Mute again so live state matches the
              // persisted override; retrying unmute re-attempts the clear.
              try {
                await participant.enableAudio(setEnabled: false);
                notifyListeners();
              } catch (rollbackError) {
                // Mic stays hot — keep showing unmuted (truthful) and let the
                // snapshot listener reconcile.
                loggingService.log(
                  'toggleAudioEnabled: override rollback failed: $rollbackError',
                );
              }
            }
            loggingService.log('toggleAudioEnabled: exception: $e');
            if (isGetUserMediaError(e)) {
              // Shown after the lock is released below; see toggleVideoEnabled.
              deviceError = e.toString();
              return;
            }
            rethrow;
          }
        },
        timeout: Duration(seconds: 4),
      );
    } on TimeoutException {
      loggingService.log('toggleAudioEnabled: toggle in progress, tap ignored');
      return;
    }
    if (deviceError != null) {
      await AudioVideoErrorDialog.show(
        navigatorState.context,
        deviceError!,
        inMeeting: true,
      );
      return;
    }

    if (executed) notifyListeners();
  }

  bool _canInitiateScreenShare() {
    final userId = userService.currentUserId;
    if (userId == null) return false;
    if (liveMeetingProvider.eventProvider.event.creatorId == userId) {
      return true;
    }
    return userDataService.getMembership(communityProvider.communityId).isMod;
  }

  Future<void> toggleScreenShare({bool? setEnabled}) async {
    final updatedEnabledValue = setEnabled ?? !isLocalSharingScreenActive;
    if (updatedEnabledValue) {
      if (!_canInitiateScreenShare()) return;
      if (screenSharer != null && !isLocalSharingScreenActive) return;
      bool started = false;
      bool cancelled = false;
      try {
        await _room!.localParticipant!.startScreenShare(
          channelName: roomName,
          screenShareToken: screenShareToken,
          onNativeStop: () => unawaited(_writeScreenSharingState(null)),
          onScreenEngineVideoSizeChanged: (uid, w, h, rot) {
            _room!.applyReportedVideoFrameSize(uid, w, h, rot);
            // Screen engine reports uid=0 for local capture; layout keys by screenUid.
            if (uid == 0) {
              final screenUid = _room!.localParticipant?.screenAgoraUid;
              if (screenUid != null) {
                _room!.applyReportedVideoFrameSize(screenUid, w, h, rot);
              }
            }
          },
        );
        started = true;
        if (kIsWeb) {
          final px = jsGetCanvasCompositorPixelSize();
          if (px != null && px.length >= 2 && px[0] > 0 && px[1] > 0) {
            final uid = uidToInt(userService.currentUserId!);
            _room!.seedVideoFrameSize(uid, px[0], px[1]);
            _room!.seedVideoFrameSize(0, px[0], px[1]);
          }
        }
      } on ScreenShareCancelledException {
        // User dismissed the browser screen picker — silently treat as no-op.
        cancelled = true;
        return;
      } finally {
        // Skip the Firestore write on cancellation — nothing changed in Agora
        // or Firestore, and writing null could clear an in-progress share.
        if (!cancelled) {
          await _writeScreenSharingState(
            started && !_isDisposed ? userService.currentUserId : null,
          );
        }
      }
    } else {
      try {
        final screenUid = _room?.localParticipant?.screenAgoraUid;
        await _room!.localParticipant!.stopScreenShare();
        if (screenUid != null) {
          _room!.clearVideoFrameSize(screenUid);
        }
      } finally {
        await _writeScreenSharingState(null);
      }
    }
    notifyListeners();
  }

  Future<void> _writeScreenSharingState(String? userId) async {
    if (_isDisposed) return;
    final liveMeetingPath = agendaProvider.liveMeetingPath;
    if (liveMeetingPath.isEmpty) return;

    // screenShareAgoraUid is the Agora integer UID of the secondary screen-share
    // engine (uidToInt(userId)|(1<<30)). on_live_meeting.dart reads this field to
    // use the screen UID (not the camera UID) as maxResolutionUid in the recording
    // layout. Null when single-engine fallback is active or on stop.
    final screenAgoraUid =
        userId != null ? _room?.localParticipant?.screenAgoraUid : null;
    final String? screenSharePath;
    if (userId == null) {
      screenSharePath = null;
    } else if (screenAgoraUid != null) {
      screenSharePath = LiveMeeting.screenSharePathDual;
    } else if (kIsWeb) {
      screenSharePath = LiveMeeting.screenSharePathCanvas;
    } else {
      screenSharePath = LiveMeeting.screenSharePathSingle;
    }

    // Write directly (not via currentMeeting.copyWith) so this never silently
    // no-ops when agendaProvider.currentLiveMeeting is null during transitions.
    try {
      await firestoreDatabase.firestore.doc(liveMeetingPath).set(
        {
          LiveMeeting.kFieldScreenSharingUserId: userId ?? FieldValue.delete(),
          LiveMeeting.kFieldScreenShareAgoraUid:
              screenAgoraUid ?? FieldValue.delete(),
          LiveMeeting.kFieldScreenSharePath:
              screenSharePath ?? FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      loggingService.log(
          '_writeScreenSharingState: error writing to $liveMeetingPath: $e');
    }
  }

  void _updateScreenSharingParticipants() {
    final liveMeeting = agendaProvider.currentLiveMeeting;
    final screenSharingUserId = liveMeeting?.screenSharingUserId;
    final screenShareAgoraUid = liveMeeting?.screenShareAgoraUid;

    // Only sync remote participants from Firestore. The local participant's
    // isScreenSharing flag is authoritative — it is set directly by
    // startScreenShare/stopScreenShare. Syncing it here would cause a race
    // where an in-flight Firestore event (with screenSharingUserId still null)
    // clears the local flag before the write we just made has been confirmed.
    for (final participant
        in _room?.remoteParticipants ?? <AgoraParticipant>[]) {
      final shouldShare = screenSharingUserId != null &&
          participant.userId == screenSharingUserId;
      if (shouldShare && screenShareAgoraUid != null) {
        participant.syncRemoteScreenShare(
          screenUid: screenShareAgoraUid,
          sharing: true,
        );
      } else if (shouldShare) {
        participant.setScreenSharing(true);
      } else {
        participant.syncRemoteScreenShare(sharing: false, screenUid: null);
      }
    }
    // Defer past the current build frame — this method is called as an
    // AgendaProvider listener, which can fire mid-build, causing
    // "setState during build" if we notify synchronously.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) notifyListeners();
    });
  }

  Future<void> onConnected(AgoraRoom room) async {
    Debug.log('ConferenceRoom._onConnected => state: ${room.state}');

    _debouncedDominantSpeakerStream = BehaviorSubjectWrapper(
      room.dominantSpeakerStream
          .distinct()
          .debounceTime(Duration(milliseconds: 150))
          .switchMap((id) {
        if (id == null) {
          // Wait before clearing speaker indicator to avoid flickering
          return Rx.timer(null, Duration(milliseconds: 1000));
        }
        return Stream.value(id); // Immediately emit new speaker ID
      }).debounceTime(Duration(milliseconds: 150)),
    );
    _debouncedDominantSpeakerSubscription =
        _debouncedDominantSpeakerStream!.listen((_) => notifyListeners());

    _unraiseHandSubscription = _debouncedDominantSpeakerStream!
        .distinct()
        .debounceTime(Duration(seconds: 4))
        .distinct()
        .listen((dominantSpeaker) {
      final dismissRaisedHand =
          room.localParticipant?.agoraUid == dominantSpeaker?.agoraUid;
      final isHandRaised =
          meetingGuideCardModel.getHandIsRaised(userService.currentUserId!);
      if (dismissRaisedHand && isHandRaised) {
        firestoreMeetingGuideService.toggleHandRaise(
          agendaItemId: meetingGuideCardModel.handRaiseScopeId,
          userId: userService.currentUserId!,
          liveMeetingPath: agendaProvider.liveMeetingPath,
          isHandRaised: false,
        );
      }
    });

    _updateLiveMeetingParticipants();
    print('updated live meeting participants');
    notifyListeners();
    _completer.complete(room);

    final isTest = (routerDelegate.currentBeamLocation.state as BeamState)
            .queryParameters['test'] !=
        null;
    if (isTest) {
      if (!(_room?.localParticipant?.audioTrackEnabled ?? false)) {
        await AudioVideoErrorDialog.showOnError(
          navigatorState.context,
          () => toggleAudioEnabled(setEnabled: true),
        );
      }
      if (!(_room?.localParticipant?.videoTrackEnabled ?? false)) {
        await AudioVideoErrorDialog.showOnError(
          navigatorState.context,
          () => toggleVideoEnabled(setEnabled: true),
        );
      }
    } else if (liveMeetingProvider.shouldStartLocalAudioOn ||
        liveMeetingProvider.shouldStartLocalVideoOn) {
      unawaited(_promptToTurnOnVideo());
    }
  }

  Future<void> _promptToTurnOnVideo() async {
    final enableAudioVideo = await ConfirmDialog(
      title: appLocalizationService.getLocalization().turnOnAudioVideo,
      mainText: 'Would you like to turn on audio and video?',
      cancelText: appLocalizationService.getLocalization().cancel,
    ).show();
    if (enableAudioVideo) {
      if (!(_room?.localParticipant?.audioTrackEnabled ?? false)) {
        await AudioVideoErrorDialog.showOnError(
          navigatorState.context,
          () => toggleAudioEnabled(setEnabled: true),
        );
      }
      if (!(_room?.localParticipant?.videoTrackEnabled ?? false)) {
        await AudioVideoErrorDialog.showOnError(
          navigatorState.context,
          () => toggleVideoEnabled(setEnabled: true),
        );
      }
    }
  }

  void _updateLiveMeetingParticipants({
    List<AgoraParticipant>? participantsOverride,
    bool notify = true,
  }) {
    final participants = participantsOverride ?? this.participants;
    final participantIds = participants.map((p) => p.userId).toSet();

    // Remove initialization timers for participants that have left
    participantInitializationTimers
        .removeWhere((id, _) => !participantIds.contains(id));
    // Add timers for newly connected users
    for (final participant in participants) {
      participantInitializationTimers[participant.userId] ??=
          Timer(Duration(seconds: 4), () => notifyListeners());
    }

    liveMeetingProvider.setMeetingProviderParticipants(
      participants
          .map(
            (p) => VideoParticipant(
              p,
              liveMeetingProvider.eventProvider.event,
              liveMeetingProvider.eventPath,
            ),
          )
          .toList(),
      notify: notify,
    );
  }

  void onLocalParticipantChanges() {
    Debug.log('ConferenceRoom.onLocalParticipant');
    _updateLiveMeetingParticipants();
    notifyListeners();
  }

  void onParticipantConnected() {
    Debug.log('ConferenceRoom._onParticipantConnected');

    _updateLiveMeetingParticipants();
    _updateScreenSharingParticipants();

    // When a participant rejoins (e.g. after a WiFi drop without using the
    // "Leave Meeting" CTA), their existing Firestore vote may already satisfy
    // the consensus threshold with the updated denominator. Re-checking here
    // mirrors the same logic in onParticipantDisconnected and prevents the
    // agenda from getting stuck when all visible voters show "Ready" but no
    // one can click Next to trigger the cloud function again.
    Future.delayed(
        Duration(
            milliseconds: (500 + 5.0 * random.nextDouble() * 1000).round()),
        () {
      if (!_isDisposed && liveMeetingProvider.isInBreakout) {
        agendaProvider.checkReadyToAdvance();
      }
    });

    notifyListeners();
  }

  void onParticipantDisconnected() {
    Debug.log('ConferenceRoom._onParticipantDisconnected');
    _updateLiveMeetingParticipants();

    Future.delayed(
        Duration(milliseconds: (5.0 * random.nextDouble() * 1000).round()), () {
      if (!_isDisposed && liveMeetingProvider.isInBreakout) {
        agendaProvider.checkReadyToAdvance();
      }
    });

    notifyListeners();
  }

  static ConferenceRoom? read(BuildContext context) {
    try {
      return Provider.of<ConferenceRoom>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// If this method is called from a place in the tree that is not a descendant of ConferenceRoom
  /// it will throw.
  static ConferenceRoom watch(BuildContext context) =>
      Provider.of<ConferenceRoom>(context);

  static ConferenceRoom? watchOrNull(BuildContext context) {
    try {
      return Provider.of<ConferenceRoom>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }
}
