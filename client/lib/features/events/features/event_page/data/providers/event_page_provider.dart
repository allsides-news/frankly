import 'dart:async';

import 'package:beamer/beamer.dart';
import 'package:client/features/auth/utils/auth_utils.dart';
import 'package:client/core/utils/navigation_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/event_page/presentation/views/pre_post_event_dialog_page.dart';
import 'package:client/features/events/features/event_page/presentation/views/survey_dialog.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/utils/visible_exception.dart';
import 'package:client/core/utils/web_utils.dart';
import 'package:client/core/widgets/confirm_dialog.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/features/auth/presentation/views/sign_in_dialog.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/core/data/services/logging_service.dart';
import 'package:client/services.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/community/community_tag.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';

import '../../../../../../core/routing/locations.dart';

class JoinEventResults {
  final bool isJoined;
  final List<BreakoutQuestion>? surveyQuestions;

  JoinEventResults({required this.isJoined, this.surveyQuestions});
}

Future<bool> verifyAvailableForEvent(Event event) async {
  final scheduledTime = event.scheduledTime!;
  final date = DateFormat('E, MMM d').format(scheduledTime);
  final formattedTime = DateFormat('h:mm a').format(scheduledTime);
  final timezone = getTimezoneAbbreviation(scheduledTime);
  final time = timezone == null || timezone.isEmpty
      ? formattedTime
      : '$formattedTime $timezone';

  final cancel = await ConfirmDialog(
    title: appLocalizationService.getLocalization().confirm,
    subText:
        'Please confirm that you are available at $time on $date to participate in this event.',
    confirmText: 'I\'ll be there!',
    cancelText: 'No, cancel',
  ).show();
  return cancel;
}

class EventPageProvider with ChangeNotifier {
  final EventProvider eventProvider;
  final CommunityProvider communityProvider;
  final NavBarProvider navBarProvider;
  final bool cancelParam;

  bool _cancelProcessed = false;
  bool _isEnteredMeeting = false;
  bool _isInstant = false;
  bool _joinEventCFCalled = false;

  BehaviorSubjectWrapper<List<CommunityTag>>? _tagsStream;
  StreamSubscription? _tagListener;

  EventPageProvider({
    required this.eventProvider,
    required this.communityProvider,
    required this.navBarProvider,
    required this.cancelParam,
  });

  bool get isEnteredMeeting => _isEnteredMeeting;

  void leaveMeetingPrescreen() {
    _isEnteredMeeting = false;
    notifyListeners();
  }

  bool get isInstant => _isInstant;

  List<CommunityTag> get tags =>
      _tagsStream?.stream.valueOrNull?.take(5).toList() ?? [];

  /// Registers the current user for the event.
  ///
  /// [showBreakoutSurveyDialog] and [showPreEventCta] control whether the
  /// smart-match survey dialog and the pre-event CTA dialog are shown as part
  /// of joining. The enter-meeting flow passes false for both because
  /// [enterMeeting] shows them itself (CTA first, then smart match), for
  /// everyone entering - including owners and users who registered earlier.
  Future<JoinEventResults> joinEvent({
    bool showConfirm = true,
    bool joinCommunity = false,
    bool optInToNewsletters = false,
    bool showBreakoutSurveyDialog = true,
    bool showPreEventCta = true,
  }) async {
    final prePostEnabledFuture =
        eventProvider.communityProvider.prePostEnabled();

    final joinResults = await guardSignedIn<JoinEventResults>(() async {
          // Wait for self participant stream to load
          final selfStream = eventProvider.selfParticipantStream;
          if (selfStream != null) {
            await firstEmittedOrNull(selfStream);
          }
          if (eventProvider.isParticipant) {
            return JoinEventResults(isJoined: true);
          }
          if (eventProvider.isBanned) {
            return JoinEventResults(isJoined: false);
          }

          if (eventProvider.event.eventType == EventType.hosted &&
              showConfirm) {
            final confirmed = await verifyAvailableForEvent(
              eventProvider.event,
            );
            if (!confirmed) {
              return JoinEventResults(isJoined: false);
            }
          }

          final hasSurveyQuestions = eventProvider
                  .event.breakoutRoomDefinition?.breakoutQuestions.isNotEmpty ??
              false;
          final showSurveyDialog = showBreakoutSurveyDialog &&
              hasSurveyQuestions &&
              (!eventProvider.event.isHosted ||
                  eventProvider.allowPredefineBreakoutsOnHosted);
          SurveyDialogResult? surveyDialogResult;
          if (showSurveyDialog) {
            surveyDialogResult = await SurveyDialog.show(
              communityProvider: communityProvider,
              eventProvider: eventProvider,
            );

            if (surveyDialogResult == null) {
              return JoinEventResults(isJoined: false);
            }
          }

          await firestoreEventService.joinEvent(
            communityId: eventProvider.communityId,
            templateId: eventProvider.templateId,
            eventId: eventProvider.eventId,
            breakoutRoomSurveyResults: surveyDialogResult,
            optInToCommunity: joinCommunity,
            optInToNewsletters: optInToNewsletters,
          );

          analytics.logEvent(
            AnalyticsRsvpEventEvent(
              communityId: eventProvider.communityId,
              eventId: eventProvider.eventId,
              templateId: eventProvider.templateId,
            ),
            eventTitle: eventProvider.event.title,
          );

          if (joinCommunity) {
            await userDataService.requestChangeCommunityMembership(
              community: eventProvider.communityProvider.community,
              join: true,
            );
          }

          if (!_joinEventCFCalled) {
            _joinEventCFCalled = true;
            unawaited(
              cloudFunctionsEventService
                  .joinEvent(eventProvider.event)
                  .catchError((e) {
                loggingService.log('Error calling joinEvent function: $e');
                // Reset on failure so a transient error doesn't permanently
                // block the confirmation email for this provider instance.
                _joinEventCFCalled = false;
              }),
            );
          }
          return JoinEventResults(
            isJoined: true,
            surveyQuestions: surveyDialogResult?.questions,
          );
        }) ??
        JoinEventResults(isJoined: false);

    // A failure while showing the CTA dialog must not make a successful join
    // look like a failed one, otherwise callers would bail out before
    // entering the meeting even though the user is registered.
    if (joinResults.isJoined && showPreEventCta) {
      await swallowErrors(() async {
        final prePostEnabled = await prePostEnabledFuture;
        final preEventCardData = eventProvider.event.preEventCardData;
        if (prePostEnabled && preEventCardData != null) {
          if (preEventCardData.hasData) {
            await PrePostEventDialogPage.show(
              prePostCardData: preEventCardData,
              event: eventProvider.event,
            );
          }
        }
      });
    }

    return joinResults;
  }

  Future<void> enterMeeting({List<BreakoutQuestion>? surveyQuestions}) async {
    // Prevent entering ended events
    if (eventProvider.event.hasEnded(clockService.now())) {
      throw VisibleException('This event has ended. You cannot enter it.');
    }

    final selfStream = eventProvider.selfParticipantStream;
    if (selfStream == null) {
      throw VisibleException(
        'Cannot enter this event yet. Sign in may still be loading—please wait '
        'a moment and try again, or refresh the page.',
      );
    }
    // Do not use .first alone: BehaviorSubject replays the last value immediately, so
    // right after joinEvent() the cache can still be pre-join until Firestore updates.
    final Participant participant;
    try {
      participant = await selfStream
          .where((p) => p.status == ParticipantStatus.active)
          .first
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw VisibleException(
        'Could not confirm your registration in time. Please wait a moment and try again, or refresh the page.',
      );
    }

    // Require answering the pre-event CTA survey before entering. This runs
    // for everyone entering the meeting - including event owners and users
    // who registered earlier - and is skipped once answers are recorded.
    // Deliberately fail-open (swallowErrors logs the error): the survey is
    // required when systems work, but a failing flag/response lookup or
    // dialog must never block participants from entering the meeting itself.
    await swallowErrors(() async {
      final preEventCardData = eventProvider.event.preEventCardData;
      if (preEventCardData == null || !preEventCardData.hasSurveyQuestions) {
        return;
      }

      final prePostEnabled =
          await eventProvider.communityProvider.prePostEnabled();
      if (!prePostEnabled) return;

      final hasAnswered = await firestoreEventService.hasPrePostSurveyResponse(
        event: eventProvider.event,
        prePostCardType: PrePostCardType.preEvent,
      );
      if (hasAnswered) return;

      await PrePostEventDialogPage.show(
        prePostCardData: preEventCardData,
        event: eventProvider.event,
      );
    });

    final participantAnswers =
        surveyQuestions ?? participant.breakoutRoomSurveyQuestions;
    final currentSurveyQuestions =
        eventProvider.event.breakoutRoomDefinition?.breakoutQuestions ?? [];
    final questionsMatch = listEquals(
      participantAnswers
          .map(
            (q) => BreakoutQuestion(
              id: q.id,
              title: q.title,
              answerOptionId: '',
              answers: q.answers,
            ),
          )
          .toList(),
      currentSurveyQuestions
          .map(
            (q) => BreakoutQuestion(
              id: q.id,
              title: q.title,
              answerOptionId: '',
              answers: q.answers,
            ),
          )
          .toList(),
    );
    final answeredAllQuestions =
        participantAnswers.every((q) => q.answerOptionId.isNotEmpty);

    final showSurveyDialog = (!questionsMatch || !answeredAllQuestions) &&
        (currentSurveyQuestions.isNotEmpty) &&
        (!eventProvider.event.isHosted ||
            eventProvider.allowPredefineBreakoutsOnHosted);
    if (showSurveyDialog) {
      final surveyDialogResult = await SurveyDialog.show(
        communityProvider: communityProvider,
        eventProvider: eventProvider,
      );

      if (surveyDialogResult == null) {
        return;
      }

      await firestoreEventService.updateParticipantBreakoutSurveyAnswers(
        event: eventProvider.event,
        surveyDialogResult: surveyDialogResult,
      );
    }

    navBarProvider.forceHideNav();
    _isEnteredMeeting = true;
    notifyListeners();
  }

  void initialize() {
    if (userService.isSignedIn &&
        (routerDelegate.currentBeamLocation.state as BeamState)
                .queryParameters['status'] ==
            'joined') {
      unawaited(
        Future.microtask(() async {
          // enterMeeting reads eventProvider.event; the first Firestore
          // snapshot may not have arrived yet when this microtask runs.
          final loaded = await firstEmittedOrNull(eventProvider.eventStream);
          if (loaded == null) return;
          final stream = eventProvider.selfParticipantStream;
          if (stream == null) return;
          await firstEmittedOrNull(stream);
          if (!eventProvider.isParticipant) return;
          _isInstant = true;
          try {
            await enterMeeting();
          } on VisibleException catch (e) {
            loggingService.log('enterMeeting after status=joined: ${e.msg}');
          } catch (e, stackTrace) {
            loggingService.log(
              'enterMeeting after status=joined failed',
              logType: LogType.error,
              error: e,
              stackTrace: stackTrace,
            );
          }
        }),
      );
    } else if (userService.isSignedIn) {
      unawaited(
        Future.microtask(() async {
          await _checkAndRejoinBreakoutRoom();
        }),
      );
    }

    final testEmail = (routerDelegate.currentBeamLocation.state as BeamState)
        .queryParameters['test'];
    if (testEmail != null) {
      _setupTest(testEmail);
    }

    if (cancelParam && !_cancelProcessed) {
      _cancelProcessed = true;
      _processCancelParam();
    }

    _tagsStream = wrapInBehaviorSubject(
      firestoreTagService.getCommunityTags(
        communityId: communityProvider.communityId,
        taggedItemId: eventProvider.templateId,
        taggedItemType: TaggedItemType.template,
      ),
    );
    _tagListener = _tagsStream?.stream.listen(
      (tags) {
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        logStreamErrorUnlessPermissionDenied(
          'EventPageProvider tags stream error',
          error,
          stackTrace,
        );
        notifyListeners();
      },
    );
  }

  Future<void> _checkAndRejoinBreakoutRoom() async {
    final storedEventId = sharedPreferencesService.getActiveBreakoutEventId();
    final storedRoomId = sharedPreferencesService.getActiveBreakoutRoomId();
    final storedSessionId =
        sharedPreferencesService.getActiveBreakoutSessionId();

    if (storedEventId == null ||
        storedRoomId == null ||
        storedSessionId == null) {
      return;
    }

    // This runs from a microtask in initialize(), before the event stream's
    // first Firestore snapshot arrives — reading eventProvider.event here
    // throws. Await the first snapshot instead.
    Event event;
    try {
      final loaded = await firstEmittedOrNull(eventProvider.eventStream);
      if (loaded == null) return;
      event = loaded;
    } catch (e) {
      loggingService.log('Error awaiting event for breakout rejoin', error: e);
      return;
    }
    if (storedEventId != event.id) {
      return;
    }

    final selfParticipantStream = eventProvider.selfParticipantStream;
    if (selfParticipantStream == null) {
      return;
    }

    await selfParticipantStream.first;
    if (!eventProvider.isParticipant) {
      await sharedPreferencesService.clearActiveBreakoutRoomInfo();
      return;
    }

    final liveMeetingStream = firestoreLiveMeetingService.liveMeetingStream(
      parentDoc: event.fullPath,
      id: event.id,
    );

    try {
      final liveMeeting = await liveMeetingStream.stream.first;
      final currentBreakoutSession = liveMeeting.currentBreakoutSession;

      if (currentBreakoutSession == null ||
          currentBreakoutSession.breakoutRoomSessionId != storedSessionId ||
          currentBreakoutSession.breakoutRoomStatus !=
              BreakoutRoomStatus.active) {
        await sharedPreferencesService.clearActiveBreakoutRoomInfo();
        return;
      }

      final confirmed = await ConfirmDialog(
        title: 'Rejoin Breakout Room?',
        mainText:
            'You were previously in a breakout room. Would you like to rejoin your conversation?',
        confirmText: 'Rejoin',
        cancelText: 'Stay in waiting room',
      ).show();

      if (confirmed) {
        _isInstant = true;
        await enterMeeting();
      } else {
        await sharedPreferencesService.clearActiveBreakoutRoomInfo();
      }
    } finally {
      await liveMeetingStream.dispose();
    }
  }

  Future<void> _setupTest(String email) async {
    // Sign in with email
    await userService.registerWithEmail(
      displayName: email,
      email: email,
      password: 'password',
    );

    await Future.delayed(Duration(seconds: 5));

    // Register
    await joinEvent(showConfirm: false);

    // Enter meeting
    await enterMeeting();
  }

  Future<bool> cancelEvent() async {
    final cancel = await ConfirmDialog(
      title: appLocalizationService.getLocalization().cancelEvent,
      mainText: 'Are you sure you want to cancel event? This '
          'cannot be undone and will notify all participants.',
      confirmText: 'Yes, cancel',
      cancelText: appLocalizationService.getLocalization().no,
    ).show();
    if (!cancel) return false;

    await firestoreEventService.updateEvent(
      event: eventProvider.event.copyWith(
        status: EventStatus.canceled,
      ),
      keys: [Event.kFieldStatus],
    );

    return true;
  }

  Future<void> _processCancelParam() async {
    if (!userService.isSignedIn) {
      await Future.microtask(() => SignInDialog.show());
    }

    if (!userService.isSignedIn) return;

    Event event;
    try {
      final loaded = await firstEmittedOrNull(eventProvider.eventStream);
      if (loaded == null) return;
      event = loaded;
      final selfStream = eventProvider.selfParticipantStream;
      if (selfStream != null) {
        await firstEmittedOrNull(selfStream);
      }
    } catch (e) {
      loggingService.log('Error during cancel param processing', error: e);
      return;
    }

    if (event.creatorId == userService.currentUserId) {
      await cancelEvent();
    } else if (eventProvider.isParticipant) {
      final cancelParticipation = await ConfirmDialog(
        title: appLocalizationService.getLocalization().cancelParticipation,
        mainText: 'Are you sure you want to cancel?',
        confirmText: appLocalizationService.getLocalization().yes,
        cancelText: appLocalizationService.getLocalization().no,
      ).show();
      if (cancelParticipation) {
        await alertOnError(
          navigatorState.context,
          () => firestoreEventService.removeParticipant(
            communityId: event.communityId,
            templateId: event.templateId,
            eventId: event.id,
            participantId: userService.currentUserId!,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tagListener?.cancel();
    _tagsStream?.dispose();
    super.dispose();
  }
}
