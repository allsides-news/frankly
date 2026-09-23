import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:enum_to_string/enum_to_string.dart';
import 'package:flutter/foundation.dart';
import 'package:client/features/events/features/event_page/presentation/views/survey_dialog.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/utils/visible_exception.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:client/core/utils/platform_utils.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/events/pre_post_survey.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/utils/utils.dart';
import 'package:rxdart/rxdart.dart';

class FirestoreEventService {
  static const events = 'events';
  static const kPrivateUserDataCollection = 'privateUserData';
  static const kFieldSavedMatchingQuestionAnswers =
      'savedMatchingQuestionAnswers';
  static const kFieldSavedMatchingQuestionAnswersUpdatedAt =
      'savedMatchingQuestionAnswersUpdatedAt';

  // final time = await NTP.now();
  // Future to mimic NTP.now()
  Future<DateTime> get currentTimeAsync => Future(() => clockService.now());

  CollectionReference<Map<String, dynamic>> eventsCollection({
    required String communityId,
    required String templateId,
  }) {
    return firestoreDatabase
        .templateReference(communityId: communityId, templateId: templateId)
        .collection(events);
  }

  Query<Map<String, dynamic>> _eventsCollectionGroup() =>
      firestoreDatabase.firestore.collectionGroup(events);

  Query<Map<String, dynamic>> _participantsCollectionGroup() =>
      firestoreDatabase.firestore.collectionGroup('event-participants');

  DocumentReference<Map<String, dynamic>> eventReference({
    required String communityId,
    required String templateId,
    required String eventId,
  }) {
    return eventsCollection(communityId: communityId, templateId: templateId)
        .doc(eventId);
  }

  BehaviorSubjectWrapper<List<Event>> communityEvents({
    required String communityId,
  }) {
    return wrapInBehaviorSubject(
      _eventsCollectionGroup()
          .where('communityId', isEqualTo: communityId)
          .orderBy('scheduledTime', descending: true)
          .snapshots()
          .asyncMap((snapshot) async {
        final docs = snapshot.docs;
        final events = await _convertEventListAsync(docs);

// Not all events have a status on the server as it was added later on with a default of "active".
// This also applies to templates so we do filtering on the client side
        return events
            .where((event) => event.status == EventStatus.active)
            .toList();
      }),
    );
  }

  BehaviorSubjectWrapper<List<Event>> futurePublicEvents({
    required String communityId,
    required String templateId,
  }) {
    return wrapInBehaviorSubjectAsync(() async {
      final currentTime = await currentTimeAsync;

      final query = eventsCollection(
        communityId: communityId,
        templateId: templateId,
      )
          .where('isPublic', isEqualTo: true)
          .where(
            'scheduledTime',
            isGreaterThan:
                Timestamp.fromDate(currentTime.subtract(Duration(minutes: 15))),
          )
          .orderBy('scheduledTime');

      return query.snapshots().asyncMap((snapshot) async {
        final events = await _convertEventListAsync(snapshot.docs);
        return events
            .where((event) => event.status == EventStatus.active)
            .toList();
      });
    });
  }

  Future<List<Event>> getUpcomingPublicEventsFuture({
    required String communityId,
    required String templateId,
  }) async {
    final currentTime = await currentTimeAsync;

    final query = eventsCollection(
      communityId: communityId,
      templateId: templateId,
    )
        .where('isPublic', isEqualTo: true)
        .where(
          'scheduledTime',
          isGreaterThan:
              Timestamp.fromDate(currentTime.subtract(Duration(minutes: 15))),
        )
        .orderBy('scheduledTime');

    final eventsSnapshot = await query.get();
    final events = await _convertEventListAsync(eventsSnapshot.docs);
    final toReturn =
        events.where((event) => event.status == EventStatus.active).toList();
    return toReturn;
  }

  Future<List<Event>> allPublicEventsFuture([int limit = 100]) async {
    final eventsSnapshot = await _eventsCollectionGroup()
        .where('isPublic', isEqualTo: true)
        .where('scheduledTime', isGreaterThan: clockService.now())
        .limit(limit)
        .get();
    final events = eventsSnapshot.docs
        .map((doc) => _convertEvent(doc.data()..['id'] = doc.id))
        .toList();
    return events;
  }

  BehaviorSubjectWrapper<List<Event>> futurePublicEventsForCommunity({
    required String communityId,
  }) {
    return wrapInBehaviorSubjectAsync(() async {
      // final time = await NTP.now();
      // Future to mimic NTP.now()
      final currentTime = await Future(() => clockService.now());

      return _eventsCollectionGroup()
          .where('communityId', isEqualTo: communityId)
          .where(
            'scheduledTime',
            isGreaterThan:
                Timestamp.fromDate(currentTime.subtract(Duration(hours: 1))),
          )
          .where('isPublic', isEqualTo: true)
          .orderBy('scheduledTime')
          .snapshots()
          .asyncMap((snapshot) async {
        final events = await _convertEventListAsync(snapshot.docs);
        return events
            .where((event) => event.status == EventStatus.active)
            .toList();
      });
    });
  }

  /// The soonest upcoming event for a community, or null if it has none.
  ///
  /// A one-shot read rather than [futureEventsForCommunity]'s stream, because
  /// callers like the My Spaces cards want a single value per Space and would
  /// otherwise have to own and dispose a subscription each.
  ///
  /// Note this can't be a Firestore `count()`/`limit(1)` aggregate: the active
  /// check happens in Dart, not in the query, so the server has no way to skip
  /// cancelled events. It reads a small page and takes the first live one.
  Future<Event?> nextActiveEventForCommunity({
    required String communityId,
    bool includePrivateEvents = false,
  }) async {
    final currentTime = await Future(() => clockService.now());

    var query = _eventsCollectionGroup()
        .where('communityId', isEqualTo: communityId)
        .where(
          'scheduledTime',
          isGreaterThan:
              Timestamp.fromDate(currentTime.subtract(Duration(hours: 1))),
        );

    if (!includePrivateEvents) {
      query = query.where('isPublic', isEqualTo: true);
    }

    final snapshot = await query.orderBy('scheduledTime').limit(10).get();
    final events = await _convertEventListAsync(snapshot.docs);

    for (final event in events) {
      if (event.status == EventStatus.active) return event;
    }
    return null;
  }

  /// Gets future events for a community.
  ///
  /// Private events are only included when [includePrivateEvents] is true.
  BehaviorSubjectWrapper<List<Event>> futureEventsForCommunity({
    required String communityId,
    bool includePrivateEvents = false,
  }) {
    return wrapInBehaviorSubjectAsync(() async {
      final currentTime = await Future(() => clockService.now());

      var query = _eventsCollectionGroup()
          .where('communityId', isEqualTo: communityId)
          .where(
            'scheduledTime',
            isGreaterThan:
                Timestamp.fromDate(currentTime.subtract(Duration(hours: 1))),
          );

      if (!includePrivateEvents) {
        query = query.where('isPublic', isEqualTo: true);
      }

      return query
          .orderBy('scheduledTime')
          .snapshots()
          .asyncMap((snapshot) async {
        final events = await _convertEventListAsync(snapshot.docs);
        return events
            .where((event) => event.status == EventStatus.active)
            .toList();
      });
    });
  }

  Future<List<Event>> userEventsForCommunity() async {
    final participantsQuerySnapshot = await _participantsCollectionGroup()
        .where('id', isEqualTo: userService.currentUserId)
        .where(
          'status',
          isEqualTo: EnumToString.convertToString(ParticipantStatus.active),
        )
        .get();
    final eventSnapshots = participantsQuerySnapshot.docs
        .map((doc) => doc.reference.parent.parent!.get());

    final eventDocs = await Future.wait<DocumentSnapshot<Map<String, dynamic>>>(
      eventSnapshots,
    );
    return _convertEventListAsync(eventDocs);
  }

  Future<bool> userHasParticipatedInTemplate({
    required String templateId,
  }) async {
    final participantsQuerySnapshot = await _participantsCollectionGroup()
        .where('id', isEqualTo: userService.currentUserId)
        .where('templateId', isEqualTo: templateId)
        .where(
          'status',
          isEqualTo: EnumToString.convertToString(ParticipantStatus.active),
        )
        .where('scheduledTime', isLessThan: Timestamp.now())
        .get();
    return participantsQuerySnapshot.docs.isNotEmpty;
  }

  BehaviorSubjectWrapper<Event> eventStream({
    required String communityId,
    required String templateId,
    required String eventId,
  }) {
    final eventRef = eventReference(
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
    );
    return wrapInBehaviorSubject(
      eventRef.snapshots().asyncMap((snapshot) => _convertEventAsync(snapshot)),
    );
  }

  Stream<bool> communityHasEvents({required String communityId}) =>
      _eventsCollectionGroup()
          .where('communityId', isEqualTo: communityId)
          .limit(1)
          .snapshots()
          .map((event) => event.docs.isNotEmpty);

  BehaviorSubjectWrapper<List<Participant>> eventParticipantsStream({
    required String communityId,
    required String templateId,
    required String eventId,
  }) {
    final eventRef = eventReference(
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
    );
    return wrapInBehaviorSubject(
      eventRef
          .collection('event-participants')
          .snapshots(includeMetadataChanges: true)
          .where(
            (snapshot) =>
                !snapshot.metadata.hasPendingWrites &&
                !snapshot.metadata.isFromCache,
          )
          .sampleTime(Duration(milliseconds: 500))
          .asyncMap((snapshot) => convertParticipantListAsync(snapshot)),
    );
  }

  Stream<Participant> eventParticipantStream({
    required String communityId,
    required String templateId,
    required String eventId,
    required String userId,
  }) {
    final eventRef = eventReference(
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
    );
    return eventRef
        .collection('event-participants')
        .doc(userId)
        .snapshots(includeMetadataChanges: true)
        .where(
          (snapshot) =>
              !snapshot.metadata.hasPendingWrites &&
              !snapshot.metadata.isFromCache,
        )
        .map(
          (snapshot) => _convertParticipant(snapshot.data() ?? {'id': userId}),
        );
  }

  Future<List<Event>> getEventsFromPaths(
    String communityId,
    List<String> documentPaths,
  ) async {
    final eventDocs = await Future.wait(
      documentPaths.map(
        (path) {
          final eventMatch =
              RegExp('/?community/([^/]+)/templates/([^/]+)/events/([^/]+)')
                  .matchAsPrefix(path);

          final templateId = eventMatch?.group(2);
          final eventId = eventMatch?.group(3);

          if (templateId == null || eventId == null) {
            throw Exception('No template or event found.');
          }

          return eventReference(
            communityId: communityId,
            templateId: templateId,
            eventId: eventId,
          ).get();
        },
      ),
    );

    return eventDocs
        .map((e) => _convertEvent((e.data() ?? {})..['id'] = e.id))
        .toList();
  }

  Query<Map<String, dynamic>> eventParticipantsQuery({
    required Event event,
  }) {
    return eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    )
        .collection('event-participants')
        .where(
          'status',
          isEqualTo: EnumToString.convertToString(ParticipantStatus.active),
        )
        .orderBy('createdDate');
  }

  /// Like [eventParticipantsQuery] but filtered to only participants who are
  /// currently present in the meeting (isPresent == true). Used by the admin
  /// panel's live participant list so it mirrors the breakout-room presence
  /// semantics and doesn't show registered-but-absent ghost participants.
  ///
  /// Covered by the existing composite index:
  ///   event-participants COLLECTION (isPresent ASC, createdDate ASC)
  Query<Map<String, dynamic>> presentParticipantsQuery({
    required Event event,
  }) {
    return eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    )
        .collection('event-participants')
        .where('isPresent', isEqualTo: true)
        .orderBy('createdDate');
  }

  Future<List<Participant>> getEventParticipants({
    required Event event,
  }) async {
    final eventRef = eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    );
    final participantDocs =
        await eventRef.collection('event-participants').get();

    return convertParticipantListAsync(participantDocs);
  }

  Future<PrivateLiveStreamInfo?> liveStreamPrivateInfo({
    required Event event,
  }) async {
    final eventRef = firestoreDatabase.firestore.doc(
      '${event.fullPath}/private-live-stream-info/${event.id}',
    );
    final doc = await eventRef.get();
    final data = doc.data();

    if (data == null) return null;

    return PrivateLiveStreamInfo.fromJson(fromFirestoreJson(data));
  }

  Future<Event> createEventIfNotExists({
    required Event event,
    PrivateLiveStreamInfo? privateLiveStreamInfo,
    bool record = false,
  }) async {
    final eventRef = eventsCollection(
      communityId: event.communityId,
      templateId: event.templateId,
    ).doc(event.id);

    final timeZone = getTimezone();

    final newEvent = event.copyWith(
      id: eventRef.id,
      collectionPath: eventRef.parent.path,
      status: EventStatus.active,
      creatorId: userService.currentUserId!,
      scheduledTimeZone: timeZone,
    );

    final newParticipant = Participant(
      id: userService.currentUserId!,
      communityId: event.communityId,
      templateId: event.templateId,
      status: ParticipantStatus.active,
    );
    final participantRef =
        eventRef.collection('event-participants').doc(newParticipant.id);

    return firestoreDatabase.firestore.runTransaction((transaction) async {
      if (!isNullOrEmpty(event.id)) {
        final snapshot = await transaction.get(eventRef);
        final snapshotData = snapshot.data();

        if (snapshotData != null) {
          return Event.fromJson(fromFirestoreJson(snapshotData));
        }
      }

      transaction.set(eventRef, toFirestoreJson(newEvent.toJson()));
      transaction.set(participantRef, {
        ...toFirestoreJson(newParticipant.toJson()),
        Participant.kFieldCreatedDate: FieldValue.serverTimestamp(),
      });

      await userDataService.changeCommunityMembership(
        userId: userService.currentUserId!,
        communityId: event.communityId,
        newStatus: MembershipStatus.attendee,
        allowMemberDowngrade: false,
      );

      if (record) {
        transaction.set(
          firestoreDatabase.firestore.doc(
            firestoreLiveMeetingService.getLiveMeetingPath(newEvent),
          ),
          jsonSubset(
            [LiveMeeting.kFieldRecord],
            LiveMeeting(record: record).toJson(),
          ),
        );
      }

      if (privateLiveStreamInfo != null) {
        transaction.set(
          eventRef.collection('private-live-stream-info').doc(eventRef.id),
          toFirestoreJson(privateLiveStreamInfo.toJson()),
        );
      }

      return newEvent;
    });
  }

  Future<void> updateEvent({
    required Event event,
    required Iterable<String> keys,
  }) async {
    final docRef = eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    );

    final dataMap = jsonSubset(keys, toFirestoreJson(event.toJson()));
    loggingService.log(
      'FirestoreEventService.updateEvent: Path: ${docRef.path}, Data: $dataMap',
    );

    await docRef.update(dataMap);
  }

  Future<void> addLiveStreamEventDetails({
    required Event event,
    PrivateLiveStreamInfo? privateLiveStreamInfo,
  }) async {
    final eventRef = eventsCollection(
      communityId: event.communityId,
      templateId: event.templateId,
    ).doc(event.id);

    if (!isNullOrEmpty(event.id) && privateLiveStreamInfo != null) {
      await eventRef
          .collection('private-live-stream-info')
          .doc(eventRef.id)
          .set(toFirestoreJson(privateLiveStreamInfo.toJson()));
    }
  }

  Future<Map<String, String>> getSavedMatchingQuestionAnswers() async {
    final uid = userService.currentUserId;
    if (uid == null) return {};

    try {
      final snapshot = await firestoreDatabase.firestore
          .collection(kPrivateUserDataCollection)
          .doc(uid)
          .get();

      final savedAnswers = snapshot.data()?[kFieldSavedMatchingQuestionAnswers];

      if (savedAnswers is! Map) return {};

      final parsedAnswers = <String, String>{};
      savedAnswers.forEach((key, value) {
        if (key is String && value is String && value.isNotEmpty) {
          parsedAnswers[key] = value;
        }
      });

      return parsedAnswers;
    } catch (e) {
      loggingService.log(
        'FirestoreEventService.getSavedMatchingQuestionAnswers failed: $e',
      );
      return {};
    }
  }

  Future<void> saveMatchingQuestionAnswers(
    List<BreakoutQuestion>? questions,
  ) async {
    final uid = userService.currentUserId;
    if (uid == null || questions == null || questions.isEmpty) return;

    final answers = <String, String>{};
    for (final question in questions) {
      if (question.id.isNotEmpty && question.answerOptionId.isNotEmpty) {
        answers[question.id] = question.answerOptionId;
      }
    }

    if (answers.isEmpty) return;

    try {
      final docRef = firestoreDatabase.firestore
          .collection(kPrivateUserDataCollection)
          .doc(uid);

      await firestoreDatabase.firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        final savedAnswers =
            snapshot.data()?[kFieldSavedMatchingQuestionAnswers];

        final existingAnswers = <String, String>{};
        if (savedAnswers is Map) {
          savedAnswers.forEach((key, value) {
            if (key is String && value is String && value.isNotEmpty) {
              existingAnswers[key] = value;
            }
          });
        }

        transaction.set(
          docRef,
          {
            kFieldSavedMatchingQuestionAnswers: {
              ...existingAnswers,
              ...answers,
            },
            kFieldSavedMatchingQuestionAnswersUpdatedAt:
                FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      loggingService.log(
        'FirestoreEventService.saveMatchingQuestionAnswers failed: $e',
      );
    }
  }

  Future<void> joinEvent({
    required String communityId,
    required String templateId,
    required String eventId,
    String? externalCommunityId,
    bool setAttendeeStatus = true,
    SurveyDialogResult? breakoutRoomSurveyResults,
    bool optInToCommunity = false,
    bool optInToNewsletters = false,
  }) async {
    final uid = userService.currentUserId!;

    final reference = eventReference(
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
    );

    final snapshot = await reference.get();
    final event = await _convertEventAsync(snapshot);

    if (event.status == EventStatus.canceled) {
      throw VisibleException(
          'Sorry, this event has been cancelled so you cannot '
          'join it. Consider creating a new event!');
    }

    // Check if event has ended based on its duration
    if (event.hasEnded(clockService.now())) {
      throw VisibleException(
        'This event has ended. You can no longer join it.',
      );
    }

    final joinParameters = queryParametersService.mostRecentQueryParameters;
    final utmSource = joinParameters?['utm_source'];
    final utmMedium = joinParameters?['utm_medium'];
    final utmCampaign = joinParameters?['utm_campaign'];

    final participant = Participant(
      id: uid,
      communityId: communityId,
      templateId: templateId,
      status: ParticipantStatus.active,
      scheduledTime: event.scheduledTime,
      externalCommunityId: externalCommunityId,
      joinParameters: joinParameters,
      utmSource: utmSource,
      utmMedium: utmMedium,
      utmCampaign: utmCampaign,
      breakoutRoomSurveyQuestions: breakoutRoomSurveyResults?.questions ?? [],
      zipCode: breakoutRoomSurveyResults?.zipCode,
      optInToCommunity: optInToCommunity,
      optInToNewsletters: optInToNewsletters,
    );
    print('Participant $participant');
    final participantRef = reference.collection('event-participants').doc(uid);

    if (setAttendeeStatus) {
      await userDataService.changeCommunityMembership(
        userId: uid,
        communityId: communityId,
        newStatus: MembershipStatus.attendee,
        allowMemberDowngrade: false,
      );
    }

    print('Setting participant');
    await participantRef.set(
      {
        ...toFirestoreJson(participant.toJson()),
        Participant.kFieldCreatedDate: FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await saveMatchingQuestionAnswers(
      breakoutRoomSurveyResults?.questions,
    );

    print('Finished setting participant');
  }

  /// Returns whether the current user has already submitted answers to the
  /// pre or post event CTA survey for [event].
  Future<bool> hasPrePostSurveyResponse({
    required Event event,
    required PrePostCardType prePostCardType,
  }) async {
    final uid = userService.currentUserId!;

    final snapshot = await eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    ).collection('pre-post-survey-responses').doc(uid).get();

    final answersField = prePostCardType == PrePostCardType.preEvent
        ? PrePostSurveyResponse.kFieldPreEventAnswers
        : PrePostSurveyResponse.kFieldPostEventAnswers;
    final answers = snapshot.data()?[answersField];
    return answers is List && answers.isNotEmpty;
  }

  /// Records a participant's answers to the pre or post event CTA survey
  /// questions under `events/{eventId}/pre-post-survey-responses/{userId}`.
  Future<void> savePrePostSurveyResponse({
    required Event event,
    required PrePostCardType prePostCardType,
    required List<PrePostSurveyAnswer> answers,
  }) async {
    final uid = userService.currentUserId!;

    final responseRef = eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    ).collection('pre-post-survey-responses').doc(uid);

    final isPreEvent = prePostCardType == PrePostCardType.preEvent;
    final response = PrePostSurveyResponse(
      userId: uid,
      preEventAnswers: isPreEvent ? answers : [],
      postEventAnswers: isPreEvent ? [] : answers,
      preEventAnsweredDate: isPreEvent ? clockService.now() : null,
      postEventAnsweredDate: isPreEvent ? null : clockService.now(),
    );

    await responseRef.set(
      jsonSubset(
        [
          PrePostSurveyResponse.kFieldUserId,
          if (isPreEvent) ...[
            PrePostSurveyResponse.kFieldPreEventAnswers,
            PrePostSurveyResponse.kFieldPreEventAnsweredDate,
          ] else ...[
            PrePostSurveyResponse.kFieldPostEventAnswers,
            PrePostSurveyResponse.kFieldPostEventAnsweredDate,
          ],
        ],
        toFirestoreJson(response.toJson()),
      ),
      SetOptions(merge: true),
    );
  }

  /// All pre/post survey responses for [event], keyed by user ID.
  Future<Map<String, PrePostSurveyResponse>> getPrePostSurveyResponses({
    required Event event,
  }) async {
    final snapshot = await eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    ).collection('pre-post-survey-responses').get();

    final responses = <String, PrePostSurveyResponse>{};
    for (final doc in snapshot.docs) {
      try {
        responses[doc.id] = PrePostSurveyResponse.fromJson(
          fromFirestoreJson(doc.data()),
        );
      } catch (e) {
        loggingService.log(
          'Failed to parse pre-post survey response ${doc.id}: $e',
        );
      }
    }
    return responses;
  }

  Future<void> removeParticipant({
    required String communityId,
    required String templateId,
    required String eventId,
    required String participantId,
  }) async {
    final participantRef = eventReference(
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
    ).collection('event-participants').doc(participantId);
    await participantRef.set(
      jsonSubset(
        [Participant.kFieldLastUpdatedTime, Participant.kFieldStatus],
        toFirestoreJson(
          Participant(
            id: participantId,
            status: ParticipantStatus.canceled,
          ).toJson(),
        ),
      ),
      SetOptions(merge: true),
    );
  }

  Future<void> upsertAgendaItem({
    required Event event,
    required AgendaItem updatedItem,
  }) {
    return firestoreDatabase.firestore.runTransaction((transaction) async {
      final ref = firestoreDatabase.firestore.doc(event.fullPath);
      final snapshot = await transaction.get(ref);
      var eventSnapshot = await _convertEventAsync(snapshot);

      final agendaItems = eventSnapshot.agendaItems;
      final index = agendaItems.indexWhere((item) => item.id == updatedItem.id);
      if (index < 0) {
        agendaItems.add(updatedItem);
      } else {
        agendaItems[index] = updatedItem;
      }

      eventSnapshot = eventSnapshot.copyWith(agendaItems: agendaItems);
      transaction.update(
        snapshot.reference,
        jsonSubset(
          [Event.kFieldAgendaItems],
          toFirestoreJson(eventSnapshot.toJson()),
        ),
      );
    });
  }

  Future<void> setAgendaItemsLegacy({
    required Event event,
    required List<AgendaItem> agendaItems,
  }) {
    return firestoreDatabase.firestore.runTransaction((transaction) async {
      final ref = firestoreDatabase.firestore.doc(event.fullPath);
      final snapshot = await transaction.get(ref);
      var eventSnapshot = await _convertEventAsync(snapshot);

      if (eventSnapshot.agendaItems.isNotEmpty) {
        return;
      }

      eventSnapshot = eventSnapshot.copyWith(agendaItems: agendaItems);
      transaction.update(
        snapshot.reference,
        jsonSubset(
          [Event.kFieldAgendaItems],
          toFirestoreJson(eventSnapshot.toJson()),
        ),
      );
    });
  }

  Future<void> deleteTemplateAgendaItem({
    required Event event,
    required String itemId,
  }) {
    return firestoreDatabase.firestore.runTransaction((transaction) async {
      final ref = firestoreDatabase.firestore.doc(event.fullPath);
      final snapshot = await transaction.get(ref);
      var eventSnapshot = await _convertEventAsync(snapshot);

      final agendaItems = eventSnapshot.agendaItems;
      agendaItems.removeWhere((item) => item.id == itemId);

      eventSnapshot = eventSnapshot.copyWith(agendaItems: agendaItems);
      transaction.update(
        snapshot.reference,
        jsonSubset(
          [Event.kFieldAgendaItems],
          toFirestoreJson(eventSnapshot.toJson()),
        ),
      );
    });
  }

  Future<void> updateAgendaOrdering({
    required Event event,
    required List<String> ordering,
  }) {
    return firestoreDatabase.firestore.runTransaction((transaction) async {
      final ref = firestoreDatabase.firestore.doc(event.fullPath);
      final snapshot = await transaction.get(ref);
      var eventSnapshot = await _convertEventAsync(snapshot);

      final agendaItems = eventSnapshot.agendaItems;
      final agendaItemMap = Map.fromIterable(
        agendaItems,
        key: (item) => (item as AgendaItem).id,
      );

      if (!setEquals(ordering.toSet(), agendaItemMap.keys.toSet())) {
        throw VisibleException(
          'Error in updating agenda ordering. Please refresh.',
        );
      }

      final List<AgendaItem> newAgenda = ordering
          .map((itemId) => agendaItemMap[itemId] as AgendaItem)
          .toList();

      eventSnapshot = eventSnapshot.copyWith(agendaItems: newAgenda);
      transaction.update(
        snapshot.reference,
        jsonSubset(
          [Event.kFieldAgendaItems],
          toFirestoreJson(eventSnapshot.toJson()),
        ),
      );
    });
  }

  Future<void> kickParticipant({
    required Event event,
    required String kickedUserId,
    bool lockRoom = false,
  }) async {
    final eventPath = event.fullPath;
    final eventDoc = firestoreDatabase.firestore.doc(eventPath);
    final snapshot = await eventDoc.get();
    final firestoreEvent = await _convertEventAsync(snapshot);
    if (firestoreEvent.creatorId == kickedUserId) {
      throw VisibleException('Can\'t kick the event creator.');
    }

    final participantRef = eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    ).collection('event-participants').doc(kickedUserId);

    loggingService.log('setting the users status to banned: $kickedUserId');
    await participantRef.set(
      jsonSubset(
        [Participant.kFieldLastUpdatedTime, Participant.kFieldStatus],
        toFirestoreJson(
          Participant(
            id: kickedUserId,
            status: ParticipantStatus.banned,
          ).toJson(),
        ),
      ),
      SetOptions(merge: true),
    );

    if (lockRoom) {
      await updateEvent(
        event: firestoreEvent.copyWith(isLocked: true),
        keys: [Event.kFieldIsLocked],
      );
    }
  }

  Future<void> updateParticipantBreakoutSurveyAnswers({
    required Event event,
    bool lockRoom = false,
    required SurveyDialogResult surveyDialogResult,
  }) async {
    final userId = userService.currentUserId!;
    final participant = Participant(
      id: userId,
      breakoutRoomSurveyQuestions: surveyDialogResult.questions,
      zipCode: surveyDialogResult.zipCode,
    );
    final participantRef = eventReference(
      communityId: event.communityId,
      templateId: event.templateId,
      eventId: event.id,
    ).collection('event-participants').doc(userId);

    loggingService.log('Updating survey answers for $userId');
    await participantRef.set(
      jsonSubset(
        [
          Participant.kFieldBreakoutRoomSurveyQuestions,
          Participant.kFieldZipCode,
        ],
        toFirestoreJson(participant.toJson()),
      ),
      SetOptions(merge: true),
    );

    await saveMatchingQuestionAnswers(surveyDialogResult.questions);
  }

  static Future<List<Event>> _convertEventListAsync(
    List<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final events = <Event?>[
      for (final doc in docs)
        await swallowErrors(
          () => compute<Map<String, dynamic>, Event>(
            _convertEvent,
            (doc.data() ?? {})..['id'] = doc.id,
          ),
          errorMessage:
              'Error parsing event: ${doc.reference.path}/${doc.reference.id}',
        ),
    ];

    for (var i = 0; i < events.length; i++) {
      events[i] = events[i]?.copyWith(id: docs[i].id);
    }

    return <Event>[
      for (final event in events)
        if (event != null) event,
    ];
  }

  static Future<Event> _convertEventAsync(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final event = await compute<Map<String, dynamic>, Event>(
      _convertEvent,
      (doc.data() ?? {})..['id'] = doc.id,
    );
    return event.copyWith(id: doc.id);
  }

  static Event _convertEvent(Map<String, dynamic> data) {
    return Event.fromJson(fromFirestoreJson(data));
  }

  static Future<List<Participant>> convertParticipantListAsync(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final snapshotDocs = snapshot.docs;

    final events = await Future.wait(
      snapshotDocs.map((doc) => compute(_convertParticipant, doc.data())),
    );

    for (var i = 0; i < events.length; i++) {
      events[i] = events[i].copyWith(
        id: snapshotDocs[i].id,
      );
    }

    return events;
  }

  static Participant _convertParticipant(Map<String, dynamic> data) {
    try {
      return Participant.fromJson(fromFirestoreJson(data));
    } catch (exception) {
      print('Failed on $data');
      rethrow;
    }
  }
}
