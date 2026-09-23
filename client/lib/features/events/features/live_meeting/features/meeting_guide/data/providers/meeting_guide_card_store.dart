import 'dart:async';

import 'package:client/core/utils/provider_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/data/providers/meeting_agenda_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/utils/visible_exception.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/meeting_guide.dart';
import 'package:provider/provider.dart';

class MeetingGuideCardStore with ChangeNotifier {
  static const String startAgendaItemId = 'start';

  final CommunityProvider communityProvider;
  final LiveMeetingProvider liveMeetingProvider;
  final AgendaProvider agendaProvider;
  final Function(String) showToast;

  MeetingGuideCardStore({
    required this.communityProvider,
    required this.liveMeetingProvider,
    required this.agendaProvider,
    required this.showToast,
  });

  /// A timer that is used to assign the current agenda item for the meeting guide card after a
  /// delay.
  ///
  /// While this timer is active, the meeting guide card shows a countdown.
  Timer? _pendingMeetingGuideAgendaItemTimer;
  final pendingMeetingGuideAgendaItemElapsed = Stopwatch()..start();

  /// The ID of the agenda item that is currently being show in the meeting guide card.
  ///
  /// This should not be set directly but should be set using [_setCurrentMeetingGuideAgendaItemId].
  String? _currentMeetingGuideAgendaItemId;

  /// The current agenda item that we have loaded participant item details for.
  String? _participantAgendaItemDetailsId;

  /// A stream of each participant's agenda item details.
  ///
  /// This includes information such as I'm Ready, their poll responses, or other per-participant
  /// data. As users fill in their object, every participant is notified via this stream.
  BehaviorSubjectWrapper<List<ParticipantAgendaItemDetails>>?
      _participantAgendaItemDetailsStream;
  StreamSubscription? _participantAgendaItemDetailsSubscription;

  Stream<List<ParticipantAgendaItemDetails>>?
      get participantAgendaItemDetailsStream =>
          _participantAgendaItemDetailsStream;
  List<ParticipantAgendaItemDetails>? get participantAgendaItemDetails =>
      _participantAgendaItemDetailsStream?.stream.valueOrNull;

  /// This is the current agenda item. The meetingGuideCardAgendaItem may lag behind this during the
  /// countdown.
  String? get currentAgendaModelItemId {
    if (!agendaProvider.isMeetingStarted) {
      return startAgendaItemId;
    } else if (agendaProvider.isMeetingFinished) {
      return null;
    }

    return meetingGuideCardAgendaItem?.id ??
        agendaProvider.agendaItems.firstOrNull?.id;
  }

  String? get _agendaProviderCurrentItemId {
    if (!agendaProvider.isMeetingStarted) {
      return startAgendaItemId;
    } else if (agendaProvider.isMeetingFinished) {
      return null;
    }

    return agendaProvider.currentAgendaItem?.id ??
        agendaProvider.agendaItems.firstOrNull?.id;
  }

  AgendaItem? get meetingGuideCardAgendaItem => agendaProvider.agendaItems
      .where((i) => i.id == _currentMeetingGuideAgendaItemId)
      .firstOrNull;

  bool get meetingGuideCardIsPending =>
      _pendingMeetingGuideAgendaItemTimer?.isActive ?? false;

  bool get guideCardTakeover =>
      liveMeetingProvider.liveMeetingViewType ==
          LiveMeetingViewType.bradyBunch ||
      [AgendaItemType.video, AgendaItemType.wordCloud]
          .contains(meetingGuideCardAgendaItem?.type);

  bool get isPlayingVideo =>
      meetingGuideCardAgendaItem?.type == AgendaItemType.video;

  void initialize() {
    agendaProvider.addListener(_onAgendaChange);

    _onAgendaChange(notify: false);
  }

  @override
  void dispose() {
    _resetParticipantAgendaItemDetails();
    agendaProvider.removeListener(_onAgendaChange);

    _pendingMeetingGuideAgendaItemTimer?.cancel();

    super.dispose();
  }

  void _onAgendaChange({bool notify = true}) {
    _loadParticipantAgendaItemDetails();

    _checkPendingMeetingGuideAgendaItem();

    if (notify) notifyListeners();
  }

  /// Where hand raises live when no agenda item is running.
  ///
  /// A raised hand means "I'd like to speak", which is true between items,
  /// after the agenda finishes, and in a breakout with no agenda at all --
  /// none of which depend on an agenda item existing. Storage is keyed by one
  /// anyway, and the security rules match `{agendaItemId}` as a bare wildcard
  /// without checking that it names a real item, so a sentinel id gives those
  /// hands somewhere to live without a rules change.
  static const String kMeetingWideScopeId = meetingWideAgendaItemId;

  /// The scope hand raises are read from and written to right now.
  String get handRaiseScopeId =>
      currentAgendaModelItemId ?? kMeetingWideScopeId;

  bool getHandIsRaised(String userId) => getHandRaisedTime(userId) != null;

  bool get isMyHandRaised {
    final userId = userService.currentUserId;
    return userId != null && getHandIsRaised(userId);
  }

  /// Raise or lower the current user's hand.
  ///
  /// Lives here rather than at each control: the agenda card, the mobile
  /// control bar and the desktop control bar all offer this, and the write --
  /// which scope, which path, which direction -- is the same from all three.
  Future<void> toggleHandRaise() async {
    final userId = userService.currentUserId;
    if (userId == null) return;
    await firestoreMeetingGuideService.toggleHandRaise(
      agendaItemId: handRaiseScopeId,
      userId: userId,
      // Breakout-scoped whenever you're in one: activeLiveMeetingPath points
      // at the room's own live meeting, so a hand raised in a breakout is
      // written and read under that room and is invisible outside it.
      liveMeetingPath: agendaProvider.liveMeetingPath,
      isHandRaised: !getHandIsRaised(userId),
    );
  }
  DateTime? getHandRaisedTime(String userId) {
    return participantAgendaItemDetails
        ?.firstWhereOrNull((a) => a.userId == userId)
        ?.handRaisedTime;
  }

  /// Loads the details for all participants for this particular agenda item.
  ///
  /// As the agenda item changes, this stream exposes how users have interacted with the meeting
  /// guide card.
  void _loadParticipantAgendaItemDetails() {
    final scopeId = handRaiseScopeId;
    // Used to bail out when there was no agenda item, which left nothing
    // subscribed and nowhere for a hand raise to be read back from.
    if (_participantAgendaItemDetailsId != scopeId) {
      _resetParticipantAgendaItemDetails();
      _participantAgendaItemDetailsStream = wrapInBehaviorSubject(
        firestoreMeetingGuideService.participantAgendaItemDetailsStream(
          liveMeetingPath: agendaProvider.liveMeetingPath,
          agendaItemId: scopeId,
        ),
      );
      _participantAgendaItemDetailsSubscription =
          _participantAgendaItemDetailsStream!.listen(
        (_) => notifyListeners(),
        onError: (Object error, StackTrace stackTrace) {
          logStreamErrorUnlessPermissionDenied(
            'MeetingGuideCardStore participant agenda details stream error',
            error,
            stackTrace,
          );
        },
      );
      _participantAgendaItemDetailsId = scopeId;
    }
  }

  void _resetParticipantAgendaItemDetails() {
    _participantAgendaItemDetailsStream?.dispose();
    _participantAgendaItemDetailsSubscription?.cancel();
    _participantAgendaItemDetailsStream = null;
    _participantAgendaItemDetailsId = null;
  }

  /// This method checks the current agenda item from the [AgendaProvider].
  void _checkPendingMeetingGuideAgendaItem() {
    final isAgendaItemTimerActive =
        _pendingMeetingGuideAgendaItemTimer?.isActive ?? false;
    final meetingGuideMatchesLiveMeeting =
        _currentMeetingGuideAgendaItemId == _agendaProviderCurrentItemId;

    if (!agendaProvider.isInBreakouts ||
        agendaProvider.isMeetingFinished ||
        _currentMeetingGuideAgendaItemId == null ||
        _agendaProviderCurrentItemId ==
            MeetingGuideCardStore.startAgendaItemId) {
      // Skip the timer if we are at the beginning, end, if the meeting is hosted, or if we haven't
      // seen a card yet.
      _pendingMeetingGuideAgendaItemTimer?.cancel();
      _setCurrentMeetingGuideAgendaItemId(_agendaProviderCurrentItemId);
    } else if (!meetingGuideMatchesLiveMeeting && !isAgendaItemTimerActive) {
      // If the current agenda item has changed, it waits 3 seconds and updates
      // [_currentMeetingGuideAgendaItemId] to match. During this time a timer is shown counting
      // down to the new agenda item.
      _pendingMeetingGuideAgendaItemTimer?.cancel();
      _pendingMeetingGuideAgendaItemTimer = Timer(Duration(seconds: 3), () {
        _setCurrentMeetingGuideAgendaItemId(_agendaProviderCurrentItemId);

        liveMeetingProvider.setAudioTemporarilyDisabled(
          disabled: isPlayingVideo,
        );
        notifyListeners();
      });
      pendingMeetingGuideAgendaItemElapsed.reset();
    }

    // If the meeting agenda item is or was playing a video, we need to update everyone to be muted
    // or not.
    liveMeetingProvider.setAudioTemporarilyDisabled(disabled: isPlayingVideo);
  }

  /// Using this instead of a setter since it is already a private field.
  ///
  /// Should probably figure out how to shield it more so people dont update that field directly
  /// in the future.
  void _setCurrentMeetingGuideAgendaItemId(String? newItemId) {
    if (_currentMeetingGuideAgendaItemId == newItemId) return;

    _currentMeetingGuideAgendaItemId = newItemId;

    _loadParticipantAgendaItemDetails();

    Future.microtask(
      () => liveMeetingProvider.updateGuideCardIsMinimized(
        isMinimized: agendaProvider.isMeetingFinished,
      ),
    );
  }

  Duration? get getTimeRemainingInCard {
    final currentAgendaItem = meetingGuideCardAgendaItem;
    final totalSectionTimeInSeconds = currentAgendaItem?.timeInSeconds;
    final currentAgendaItemId = currentAgendaItem?.id;
    if (currentAgendaItem == null ||
        totalSectionTimeInSeconds == null ||
        currentAgendaItemId == null) return null;

    final totalSectionTime = Duration(seconds: totalSectionTimeInSeconds);
    final timeInSection = agendaProvider.timeInSection(currentAgendaItemId);

    final remaining = totalSectionTime - timeInSection;

    return remaining;
  }

  bool isReadyToAdvance(
    List<ParticipantAgendaItemDetails>? participantAgendaItemDetailsList,
    String? userId,
  ) {
    return participantAgendaItemDetailsList
            ?.firstWhereOrNull((p) => p.userId == userId)
            ?.readyToAdvance ??
        false;
  }

  Future<void> goToPreviousAgendaItem() async {
    final currentAgendaItemId = meetingGuideCardAgendaItem?.id;
    final currentAgendaItemIndex = agendaProvider.agendaItems
        .indexWhere((a) => a.id == currentAgendaItemId);

    final AgendaItem prevAgendaItem;
    if (currentAgendaItemIndex < 0 && agendaProvider.isMeetingFinished) {
      prevAgendaItem = agendaProvider.agendaItems.last;
    } else if (currentAgendaItemIndex < 0) {
      throw VisibleException('Meeting Guide entry not found.');
    } else {
      prevAgendaItem =
          agendaProvider.agendaItems.skip(currentAgendaItemIndex - 1).first;
    }

    await agendaProvider.goToPreviousAgendaItem(prevAgendaItem.id);
  }

  static MeetingGuideCardStore? watch(BuildContext context) =>
      providerOrNull(() => Provider.of<MeetingGuideCardStore>(context));

  static MeetingGuideCardStore? read(BuildContext context) => providerOrNull(
        () => Provider.of<MeetingGuideCardStore>(context, listen: false),
      );
}
