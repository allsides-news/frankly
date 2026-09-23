import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:client/core/utils/date_utils.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/utils/provider_utils.dart';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/widgets/confirm_dialog.dart';
import 'package:client/config/environment.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:client/core/utils/extensions.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/chat/chat_suggestion_data.dart';
import 'package:client/features/events/features/event_page/data/registration_data_csv.dart';
import 'package:data_models/community/member_details.dart';
import 'package:data_models/events/pre_post_survey.dart';
import 'package:data_models/templates/template.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';
import 'package:universal_html/html.dart';

class EventProvider with ChangeNotifier {
  final CommunityProvider communityProvider;
  final String templateId;
  final String eventId;

  EventProvider({
    required this.communityProvider,
    required this.templateId,
    required this.eventId,
  });

  factory EventProvider.fromDocumentPath(
    String documentPath, {
    required CommunityProvider communityProvider,
  }) {
    final eventMatch =
        RegExp('/?community/([^/]+)/templates/([^/]+)/events/([^/]+)')
            .matchAsPrefix(documentPath);
    final templateId = eventMatch!.group(2)!;
    final eventId = eventMatch.group(3)!;

    return EventProvider(
      communityProvider: communityProvider,
      templateId: templateId,
      eventId: eventId,
    );
  }

  factory EventProvider.fromEvent(
    Event event, {
    required CommunityProvider communityProvider,
  }) {
    return EventProvider(
      communityProvider: communityProvider,
      templateId: event.templateId,
      eventId: event.id,
    );
  }

  late BehaviorSubjectWrapper<List<Event>> _upcomingEvents;

  late BehaviorSubject<List<Template>> _templatesStream;
  late BehaviorSubjectWrapper<Event> _eventStream;
  BehaviorSubjectWrapper<Participant>? _selfParticipantStream;
  BehaviorSubjectWrapper<List<Participant>>? _eventParticipantsStream;

  StreamSubscription? _templateStreamSubscription;
  late BehaviorSubject<Template?> _templateStream;

  StreamSubscription? _eventStreamSubscription;
  StreamSubscription? _selfParticipantStreamSubscription;
  StreamSubscription? _eventParticipantsStreamSubscription;
  StreamSubscription? _userServiceChangesSubscription;
  String? _streamsUserId;

  Future<PrivateLiveStreamInfo?>? _privateLiveStreamInfo;

  late Future<bool> _hasParticipantAttendedPrerequisiteFuture;

  bool _hasAttendedPrerequisite = false;

  /// Last event emitted by [_eventStream]. Kept across stream restarts so
  /// widgets that read [event] during an auth-driven resubscribe do not throw
  /// while Flutter's StreamBuilder still holds the previous snapshot.
  Event? _latestEvent;
  bool _eventStreamInitialized = false;

  BreakoutRoomDefinition get defaultBreakoutRoomDefinition =>
      BreakoutRoomDefinition(
        creatorId: userService.currentUserId,
        targetParticipants: 8,
        breakoutQuestions: [],
        assignmentMethod: BreakoutAssignmentMethod.targetPerRoom,
      );

  String get communityId => communityProvider.communityId;

  Stream<List<Event>> get upcomingEventsStream => _upcomingEvents.stream;

  List<Event> get upcomingEvents => _upcomingEvents.stream.value
      .where((d) => d.id != eventId && d.templateId == templateId)
      .toList();

  Stream<List<Template>> get templatesStream => _templatesStream;

  Stream<Event> get eventStream => _eventStream.stream;

  Stream<List<Participant>>? get eventParticipantsStream =>
      _eventParticipantsStream?.stream;

  Stream<Participant>? get selfParticipantStream =>
      _selfParticipantStream?.stream;

  Future<PrivateLiveStreamInfo?> get privateLiveStreamInfo =>
      _privateLiveStreamInfo ??=
          firestoreEventService.liveStreamPrivateInfo(event: event);

  Event? get eventOrNull {
    if (!_eventStreamInitialized) return _latestEvent;
    return _eventStream.stream.valueOrNull ?? _latestEvent;
  }

  Event get event {
    final eventValue = eventOrNull;
    if (eventValue == null) {
      throw Exception('Event must be loaded before being accessed.');
    }

    return eventValue;
  }

  Template? get template => _templateStream.valueOrNull;

  Participant? get selfParticipant =>
      _selfParticipantStream?.stream.valueOrNull;

  List<Participant> get eventParticipants =>
      _eventParticipantsStream?.stream.valueOrNull
          ?.where((p) => p.status == ParticipantStatus.active)
          .toList() ??
      [];

  bool get isParticipant =>
      _selfParticipantStream?.stream.valueOrNull?.status ==
      ParticipantStatus.active;

  bool get isBanned =>
      _selfParticipantStream?.stream.valueOrNull?.status ==
      ParticipantStatus.banned;

  bool get isLiveStream => event.isLiveStream;

  bool get hasAttendedPrerequisite => _hasAttendedPrerequisite;

  final List<Participant> _fakeLiveStreamParticipantsList = [
    for (var i = 0; i < 10; i++) Participant(id: i.toString()),
  ];

  List<Participant> get fakeLiveStreamParticipantsList =>
      _fakeLiveStreamParticipantsList;

  Future<bool> get hasParticipantAttendedPrerequisiteFuture =>
      _hasParticipantAttendedPrerequisiteFuture;

  bool get showSmartMatchingForBreakouts =>
      (_settingsValue((settings) => settings.showSmartMatchingForBreakouts)) ||
      (event.breakoutRoomDefinition?.assignmentMethod ==
          BreakoutAssignmentMethod.smartMatch);

  bool get enablePrerequisites =>
      _settingsValue((settings) => settings.enablePrerequisites);

  bool get enableChat => _settingsValue((settings) => settings.chat);

  bool get enableTalkingTimer =>
      _settingsValue((settings) => settings.talkingTimer);

  bool get enableFloatingChat =>
      _settingsValue((settings) => settings.showChatMessagesInRealTime);

  bool get allowPredefineBreakoutsOnHosted =>
      _settingsValue((settings) => settings.allowPredefineBreakoutsOnHosted);

  bool get enableScreenshare =>
      const bool.fromEnvironment('ENABLE_SCREENSHARE', defaultValue: false) ||
      _settingsValue((settings) => settings.allowScreenshare);

  // Prepared for in-meeting transcription status UI (e.g. "Live Transcription" badge).
  // Not yet referenced by meeting widgets — transcription is currently start/stopped
  // server-side only.
  bool get enableTranscription =>
      _settingsValue((settings) => settings.alwaysTranscribe);

  bool get defaultStageView =>
      _settingsValue((settings) => settings.defaultStageView);

  bool get enableBreakoutsByCategory =>
      _settingsValue((settings) => settings.enableBreakoutsByCategory);

  bool get agendaPreview =>
      _settingsValue((settings) => settings.agendaPreview);

  bool _settingsValue(
    bool? Function(EventSettings) getValue, {
    defaultValue = false,
  }) {
    bool? getValueIfNotNull(EventSettings? settings) =>
        settings != null ? getValue(settings) : null;

    return getValueIfNotNull(event.eventSettings) ??
        getValueIfNotNull(template?.eventSettings) ??
        getValueIfNotNull(communityProvider.eventSettings) ??
        defaultValue;
  }

  Future<bool> _checkHasParticipantAttendedPrerequisite() async {
    final event = await firstEmittedOrNull(_eventStream);
    if (event == null) return false;
    final prerequisiteTemplateId = event.prerequisiteTemplateId;
    if (prerequisiteTemplateId != null) {
      _hasAttendedPrerequisite =
          await firestoreEventService.userHasParticipatedInTemplate(
        templateId: prerequisiteTemplateId,
      );
    }
    notifyListeners();
    return _hasAttendedPrerequisite;
  }

  bool get useParticipantCountEstimate {
    return event.useParticipantCountEstimate;
  }

  int get participantCount => useParticipantCountEstimate
      ? max(1, event.participantCountEstimate ?? 0)
      : eventParticipants.length;

  /// Returns the actual participant count from the stream, regardless of whether
  /// the event uses estimates. Use this when displaying counts to users with permission.
  /// Note: This will initialize the participant stream if not already initialized.
  int get actualParticipantCount {
    _ensureParticipantStreamInitialized();
    return eventParticipants.length;
  }

  int get presentParticipantCount => useParticipantCountEstimate
      ? max(1, event.presentParticipantCountEstimate ?? 0)
      : eventParticipants.where((p) => p.isPresent).length;

  /// Ensures the participant stream is initialized, even for hostless/livestream events.
  /// This is called when we need to access actual participant data (e.g., for users with permission).
  void _ensureParticipantStreamInitialized() {
    if (_eventParticipantsStream == null) {
      _eventParticipantsStream = firestoreEventService.eventParticipantsStream(
        communityId: communityId,
        templateId: templateId,
        eventId: eventId,
      );
      _listenToParticipantsStream();
    }
  }

  void initialize() {
    if (_eventStreamInitialized) return;

    _upcomingEvents = firestoreEventService.futurePublicEventsForCommunity(
      communityId: communityId,
    );

    _eventStream = firestoreEventService.eventStream(
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
    );

    _templatesStream = wrapInBehaviorSubject(
      firestoreDatabase.communityTemplatesStream(communityId).map(
            (templates) => templates
              ..sort((a, b) {
                final aPriority = a.orderingPriority;
                final bPriority = b.orderingPriority;

                if (bPriority == null) {
                  return -1;
                } else if (aPriority == null) {
                  return 1;
                }
                return aPriority.compareTo(bPriority);
              }),
          ),
    ).stream;

    _userServiceChangesSubscription =
        userService.currentUserChanges.listen((_) => _handleUserChanged());
    _streamsUserId ??= userService.currentUserId;
    _templateStream = wrapInBehaviorSubject(
      firestoreDatabase.templateStream(
        communityId: communityId,
        templateId: templateId,
      ),
    ).stream;

    _listenToStreams();
    _hasParticipantAttendedPrerequisiteFuture =
        _checkHasParticipantAttendedPrerequisite();
    _eventStreamInitialized = true;
  }

  void _handleUserChanged() {
    _recreateSelfParticipantStream();

    final userId = userService.currentUserId;
    // Recreate the event listener when the signed-in account changes.
    // A permission-denied snapshot listener does not recover after login;
    // without this the page stays on "Something went wrong" until reload.
    if (_streamsUserId != null && _streamsUserId != userId) {
      _restartEventStream();
    }
    _streamsUserId = userId;
    // currentUserChanges is a BehaviorSubject; listen() replays during
    // initialize() which runs in ChangeNotifierProvider.create. A sync
    // notify there trips debug `!_dirty`.
    if (!_eventStreamInitialized) return;
    notifyListeners();
  }

  void _recreateSelfParticipantStream() {
    _selfParticipantStreamSubscription?.cancel();
    _selfParticipantStream?.dispose();
    if (userService.currentUserId != null) {
      _selfParticipantStream = wrapInBehaviorSubject(
        firestoreEventService.eventParticipantStream(
          communityId: communityId,
          templateId: templateId,
          eventId: eventId,
          userId: userService.currentUserId!,
        ),
      );
    } else {
      _selfParticipantStream = null;
    }

    _selfParticipantStreamSubscription = _selfParticipantStream?.stream.listen(
      (_) => notifyListeners(),
      onError: (Object error, StackTrace stackTrace) {
        logStreamErrorUnlessPermissionDenied(
          'EventProvider self-participant stream error',
          error,
          stackTrace,
        );
        notifyListeners();
      },
    );
  }

  void _restartEventStream() {
    _eventStreamSubscription?.cancel();
    _eventParticipantsStreamSubscription?.cancel();
    _eventStream.dispose();
    _eventParticipantsStream?.dispose();
    _eventParticipantsStream = null;

    _eventStream = firestoreEventService.eventStream(
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
    );
    _listenToEventStream();
    _hasParticipantAttendedPrerequisiteFuture =
        _checkHasParticipantAttendedPrerequisite();
  }

  void _listenToStreams() {
    _templateStreamSubscription = _templateStream.stream.listen(
      (value) {
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        logStreamErrorUnlessPermissionDenied(
          'EventProvider template stream error',
          error,
          stackTrace,
        );
        notifyListeners();
      },
    );
    _listenToEventStream();
  }

  void _listenToParticipantsStream() {
    _eventParticipantsStreamSubscription =
        _eventParticipantsStream?.stream.listen(
      (_) => notifyListeners(),
      onError: (Object error, StackTrace stackTrace) {
        // Private-event roster reads are often denied for non-participants.
        // Swallow those so they do not hit the zone / Sentry; log anything else.
        logStreamErrorUnlessPermissionDenied(
          'EventProvider participants stream error',
          error,
          stackTrace,
        );
        notifyListeners();
      },
    );
  }

  void _listenToEventStream() {
    _eventStreamSubscription = _eventStream.stream.listen(
      (event) {
        _latestEvent = event;
        if (!useParticipantCountEstimate && _eventParticipantsStream == null) {
          _eventParticipantsStream =
              firestoreEventService.eventParticipantsStream(
            communityId: communityId,
            templateId: templateId,
            eventId: eventId,
          );
          _listenToParticipantsStream();
        }
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        logStreamErrorUnlessPermissionDenied(
          'EventProvider event stream error',
          error,
          stackTrace,
        );
        notifyListeners();
      },
    );
  }

  Future<void> updateEventSettings(EventSettings newSettings) {
    return firestoreEventService.updateEvent(
      event: event.copyWith(eventSettings: newSettings),
      keys: [Event.kFieldEventSettings],
    );
  }

  @override
  void dispose() {
    _userServiceChangesSubscription?.cancel();
    _eventStreamSubscription?.cancel();
    _selfParticipantStreamSubscription?.cancel();
    _eventParticipantsStreamSubscription?.cancel();
    _templateStreamSubscription?.cancel();
    // Safe if disposed before [initialize] (e.g. leave discuss before
    // EventPage.initState, or a sibling provider throws during create).
    if (_eventStreamInitialized) {
      _templatesStream.close();
      _templateStream.close();
      _upcomingEvents.dispose();
      _eventStream.dispose();
    }
    _selfParticipantStream?.dispose();
    _eventParticipantsStream?.dispose();
    super.dispose();
  }

  static EventProvider watch(BuildContext context) =>
      Provider.of<EventProvider>(context);

  static EventProvider read(BuildContext context) =>
      Provider.of<EventProvider>(context, listen: false);

  static EventProvider? readOrNull(BuildContext context) => providerOrNull(
        () => Provider.of<EventProvider>(context, listen: false),
      );

  Future<void> refreshEvent(Template template, Event event) async {
    await firestoreEventService.updateEvent(
      event: event.copyWith(agendaItems: template.agendaItems),
      keys: [Event.kFieldAgendaItems],
    );
  }

  Future<void> cancelParticipation({required String participantId}) async {
    final participantIsUser = userService.currentUserId == participantId;
    final identifier = participantIsUser ? 'your' : 'this user\'s';
    final cancelParticipation = await ConfirmDialog(
      title: appLocalizationService.getLocalization().cancel,
      mainText:
          'Are you sure you want to cancel $identifier participation in this event?',
      confirmText: 'Yes, cancel',
      cancelText: appLocalizationService.getLocalization().no,
    ).show();
    if (cancelParticipation) {
      await firestoreEventService.removeParticipant(
        communityId: event.communityId,
        templateId: event.templateId,
        eventId: event.id,
        participantId: participantId,
      );
    }
  }

  Future<void> generateRegistrationDataCsvFile({
    required List<MemberDetails> registrationData,
    required String? eventId,
  }) async {
    final event = _eventStream.value;

    var surveyResponses = const <String, PrePostSurveyResponse>{};
    var attendedUserIds = const <String>{};
    var hasRealBreakoutRooms = false;
    var attendanceKnown = false;

    if (event != null) {
      try {
        surveyResponses =
            await firestoreEventService.getPrePostSurveyResponses(event: event);
      } catch (e) {
        loggingService.log('Failed to load pre/post survey responses: $e');
      }

      try {
        final attendance =
            await firestoreLiveMeetingService.getBreakoutAttendance(
          event: event,
        );
        attendedUserIds = attendance.attendeeIds;
        hasRealBreakoutRooms = attendance.hasRealBreakoutRooms;
        final now = clockService.now();
        final scheduledTime = event.scheduledTime;
        attendanceKnown = attendance.liveMeetingExists ||
            event.isEnded ||
            event.hasEnded(now) ||
            (scheduledTime != null && !scheduledTime.isAfter(now));
      } catch (e) {
        loggingService.log('Failed to load breakout attendance: $e');
      }
    }

    final rows = buildRegistrationDataCsvRows(
      appName: Environment.appName,
      registrationData: registrationData,
      event: event,
      surveyResponsesByUserId: surveyResponses,
      attendedUserIds: attendedUserIds,
      hasRealBreakoutRooms: hasRealBreakoutRooms,
      attendanceKnown: attendanceKnown,
    );

    String csv = const ListToCsvConverter().convert(rows);

    final stringToBase64 = utf8.fuse(base64);
    final content = stringToBase64.encode(csv);
    final fileName = 'registration-data-$eventId.csv';

    AnchorElement(
      href: 'data:application/octet-stream;charset=utf-8;base64,$content',
    )
      ..setAttribute('download', fileName)
      ..click();
  }

  Future<void> generateChatAndSugguestionsDataCsv({
    required GetMeetingChatsSuggestionsDataResponse response,
    required String? eventId,
  }) async {
    List<List<dynamic>> rows = [];

    List<dynamic> firstRow = [];
    firstRow.add('Type');
    firstRow.add('#');
    firstRow.add('Created');
    firstRow.add('Name');
    firstRow.add('Email');
    firstRow.add('Message');
    firstRow.add('RoomId');
    firstRow.add('Deleted');
    rows.add(firstRow);

    var chatsData = response.chatsSuggestionsList
            ?.where((e) => e.type == ChatSuggestionType.chat)
            .toList() ??
        [];

    for (int i = 0; i < chatsData.length; i++) {
      List<dynamic> row = [];
      row.add('Chat');
      row.add(i + 1);
      row.add(dateTimeFormat(date: chatsData[i].createdDate!));
      row.add(chatsData[i].creatorName ?? '');
      row.add(chatsData[i].creatorEmail ?? '');
      row.add(chatsData[i].message ?? chatsData[i].emotionType?.stringEmoji);
      row.add(chatsData[i].roomId);
      row.add(chatsData[i].deleted);
      rows.add(row);
    }

    var suggestionsData = response.chatsSuggestionsList
            ?.where((e) => e.type == ChatSuggestionType.suggestion)
            .toList() ??
        [];

    if (suggestionsData.isNotEmpty) {
      firstRow.add('Upvotes');
      firstRow.add('Downvotes');
      firstRow.add('AgendaItemId');
    }

    for (int i = 0; i < suggestionsData.length; i++) {
      List<dynamic> row = [];
      row.add('Suggestion');
      row.add(i + 1);
      row.add(dateTimeFormat(date: suggestionsData[i].createdDate!));
      row.add(suggestionsData[i].creatorName ?? '');
      row.add(suggestionsData[i].creatorEmail ?? '');
      row.add(suggestionsData[i].message ?? '');
      row.add(suggestionsData[i].roomId);
      row.add(suggestionsData[i].deleted ?? false);
      row.add(suggestionsData[i].upvotes ?? '');
      row.add(suggestionsData[i].downvotes ?? '');
      row.add(suggestionsData[i].agendaItemId ?? '');
      rows.add(row);
    }

    String csv = const ListToCsvConverter().convert(rows);

    final stringToBase64 = utf8.fuse(base64);
    final content = stringToBase64.encode(csv);
    final fileName = 'chats-suggestions-data-$eventId.csv';

    AnchorElement(
      href: 'data:application/octet-stream;charset=utf-8;base64,$content',
    )
      ..setAttribute('download', fileName)
      ..click();
  }
}
