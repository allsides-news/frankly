import 'dart:async';
import 'dart:convert';

import 'package:firebase_admin_interop/firebase_admin_interop.dart'
    hide EventType;
import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    hide CloudFunction;
import '../admin/payments/analytics_util.dart';
import '../cloud_function.dart';
import '../utils/infra/firebase_auth_utils.dart';
import '../utils/infra/firestore_utils.dart';
import 'notifications/event_emails.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/utils/utils.dart';

/// Error with an HTTP status code so validation failures return proper
/// 4xx responses instead of a generic 500.
class _ApiException implements Exception {
  final int statusCode;
  final String message;

  _ApiException(this.statusCode, this.message);
}

/// HTTP endpoint (POST + JSON) for registering a user for an Event (RSVP) or
/// cancelling their registration, from outside the app.
///
/// `action: "rsvp"` mirrors the app's "REGISTER NOW!" pathway
/// (EventPageProvider.joinEvent + FirestoreEventService.joinEvent + the
/// joinEvent onCall follow-up): same eligibility guards (canceled / ended /
/// locked / banned / approval-required / full), the smart-match survey
/// answers, the follow-space and newsletter opt-ins, the participant doc +
/// membership upgrade written in one transaction, the saved matching-question
/// answers on the private user doc, and the sign-up confirmation email.
/// Reminder emails need no extra work here: the 1-day/1-hour reminder tasks
/// are scheduled per event and email everyone with an active participant doc
/// at send time.
///
/// Re-RSVPing an already-active registrant is a no-op (the app offers no way
/// to re-submit the form either): the response reports `already-registered`
/// and lists any supplied registration fields in `ignoredFields`; cancel and
/// re-register to change them.
///
/// `action: "cancel"` mirrors the app's "Cancel" participation pathway
/// (FirestoreEventService.removeParticipant): the participant doc is kept
/// with status=canceled (not deleted), no membership change, no email — which
/// also stops any future reminder emails for this user.
///
/// Auth: requires an `x-api-key` header matching the
/// `app.create_space_api_key` functions config value (shared with
/// createCommunityApi / createEventApi). Fails closed (503) if unset.
///
/// Example payloads: scripts/event-rsvp-example.json and
/// scripts/event-rsvp-cancel-example.json
class EventRsvpApi implements CloudFunction {
  @override
  final String functionName = 'eventRsvpApi';

  String get _configuredApiKey =>
      functions.config.get('app.create_space_api_key') as String? ?? '';

  Future<void> _sendJson(
    ExpressHttpRequest expressRequest,
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    expressRequest.response.statusCode = statusCode;
    expressRequest.response.headers.set('Content-Type', 'application/json');
    expressRequest.response.write(jsonEncode(body));
    await expressRequest.response.close();
  }

  Future<void> expressAction(ExpressHttpRequest expressRequest) async {
    expressRequest.response.headers.set('Access-Control-Allow-Origin', '*');

    if (expressRequest.method == 'OPTIONS') {
      expressRequest.response.headers
          .set('Access-Control-Allow-Methods', 'POST');
      expressRequest.response.headers
          .set('Access-Control-Allow-Headers', 'Content-Type, x-api-key');
      expressRequest.response.headers.set('Access-Control-Max-Age', '3600');
      expressRequest.response.statusCode = 204;
      await expressRequest.response.close();
      return;
    }

    try {
      if (expressRequest.method != 'POST') {
        throw _ApiException(405, 'Use POST with a JSON body.');
      }

      // Fail closed: refuse all requests until an API key is configured.
      final configuredKey = _configuredApiKey;
      if (configuredKey.isEmpty) {
        throw _ApiException(503, 'API key is not configured on the server.');
      }
      final providedKey = expressRequest.headers.value('x-api-key') ?? '';
      if (providedKey != configuredKey) {
        throw _ApiException(401, 'Invalid or missing x-api-key header.');
      }

      dynamic body = expressRequest.body;
      if (body is String && body.isNotEmpty) {
        // Reached when Express didn't parse the body (non-JSON content
        // type); a decode failure is client error, not a 500.
        try {
          body = jsonDecode(body);
        } on FormatException catch (e) {
          throw _ApiException(400, 'Request body is not valid JSON: $e');
        }
      }
      if (body is! Map) {
        throw _ApiException(400, 'Request body must be a JSON object.');
      }
      final json = Map<String, dynamic>.from(body);

      final action = (_optString(json, 'action') ?? '').toLowerCase();
      if (action != 'rsvp' && action != 'cancel') {
        throw _ApiException(
          400,
          '"action" is required and must be "rsvp" (register the user) or '
          '"cancel" (cancel their registration).',
        );
      }

      if (action == 'rsvp') {
        final result = await _rsvp(json);
        await _sendJson(
          expressRequest,
          result.remove('_statusCode') as int? ?? 201,
          result,
        );
      } else {
        final result = await _cancel(json);
        await _sendJson(expressRequest, 200, result);
      }
    } on _ApiException catch (e) {
      await _sendJson(expressRequest, e.statusCode, {'error': e.message});
    } catch (e, stacktrace) {
      print('Error in $functionName');
      print(e);
      print(stacktrace);
      await _sendJson(
        expressRequest,
        500,
        {'error': 'Internal error processing RSVP: $e'},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Typed payload readers (same pattern as createEventApi).
  // ---------------------------------------------------------------------------

  String? _optString(
    Map<String, dynamic> json,
    String key, [
    String prefix = '',
  ]) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw _ApiException(400, 'Field "$prefix$key" must be a string.');
    }
    return value.trim();
  }

  bool _optBool(Map<String, dynamic> json, String key, {required bool orElse}) {
    final value = json[key];
    if (value == null) return orElse;
    if (value is! bool) {
      throw _ApiException(400, 'Field "$key" must be a boolean.');
    }
    return value;
  }

  Map<String, String>? _optStringMap(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! Map ||
        value.entries.any((e) => e.key is! String || e.value is! String)) {
      throw _ApiException(
        400,
        'Field "$key" must be an object of string keys and string values.',
      );
    }
    return Map<String, String>.from(value);
  }

  String? _valueOrNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  // ---------------------------------------------------------------------------
  // Shared context loading
  // ---------------------------------------------------------------------------

  Future<_RsvpContext> _loadContext(Map<String, dynamic> json) async {
    final userId = _optString(json, 'userId') ?? '';
    if (userId.isEmpty) {
      throw _ApiException(400, 'userId is required (the registrant).');
    }

    final communityId = _optString(json, 'communityId') ?? '';
    if (communityId.isEmpty) {
      throw _ApiException(
        400,
        'communityId is required (the Space document ID).',
      );
    }

    final eventId = _optString(json, 'eventId') ?? '';
    if (eventId.isEmpty) {
      throw _ApiException(400, 'eventId is required.');
    }

    // Verify the registrant exists in Firebase Auth before touching anything.
    try {
      await firebaseAuthUtils.getUser(userId);
    } catch (_) {
      throw _ApiException(
        400,
        'No Firebase Auth user found for userId "$userId".',
      );
    }

    final communityDoc =
        await firestore.document('community/$communityId').get();
    if (!communityDoc.exists) {
      throw _ApiException(
        404,
        'No Space found with communityId "$communityId".',
      );
    }
    final community = Community.fromJson(
      firestoreUtils.fromFirestoreJson(
        communityDoc.data.toMap()..['id'] = communityDoc.documentID,
      ),
    );

    // Resolve the event. templateId is optional: without it, the synthetic
    // default template ('misc', which has no template doc) is tried first,
    // then each existing template doc in the Space.
    var templateId = _valueOrNull(_optString(json, 'templateId'));
    DocumentSnapshot? eventDoc;
    if (templateId != null) {
      eventDoc = await firestore
          .document(
            'community/$communityId/templates/$templateId/events/$eventId',
          )
          .get();
      if (!eventDoc.exists) {
        throw _ApiException(
          404,
          'No event "$eventId" found under template "$templateId" in Space '
          '"$communityId".',
        );
      }
    } else {
      final candidateTemplateIds = <String>['misc'];
      final templatesSnapshot =
          await firestore.collection('community/$communityId/templates').get();
      candidateTemplateIds.addAll(
        templatesSnapshot.documents
            .map((doc) => doc.documentID)
            .where((id) => id != 'misc'),
      );
      for (final candidate in candidateTemplateIds) {
        final doc = await firestore
            .document(
              'community/$communityId/templates/$candidate/events/$eventId',
            )
            .get();
        if (doc.exists) {
          templateId = candidate;
          eventDoc = doc;
          break;
        }
      }
      if (eventDoc == null || templateId == null) {
        throw _ApiException(
          404,
          'No event "$eventId" found in Space "$communityId". '
          'If it exists, pass its "templateId" explicitly.',
        );
      }
    }

    final event = Event.fromJson(
      firestoreUtils.fromFirestoreJson(
        eventDoc.data.toMap()..['id'] = eventDoc.documentID,
      ),
    );

    return _RsvpContext(
      userId: userId,
      communityId: communityId,
      templateId: templateId,
      eventId: eventId,
      community: community,
      event: event,
    );
  }

  // ---------------------------------------------------------------------------
  // RSVP
  // ---------------------------------------------------------------------------

  /// Mutable registration eligibility, mirroring the app
  /// (FirestoreEventService.joinEvent + EventPermissionsProvider.canJoinEvent).
  /// A host or scheduled task can flip these at any moment, so the result is
  /// only authoritative when [event] was read inside the transaction.
  _ApiException? _eligibilityConflict(Event event) {
    if (event.status == EventStatus.canceled) {
      return _ApiException(409, 'This event has been canceled.');
    }
    if (event.isEnded || event.hasEnded(DateTime.now())) {
      return _ApiException(409, 'This event has ended.');
    }
    if (event.isLocked) {
      return _ApiException(409, 'This event is locked.');
    }
    return null;
  }

  Future<Map<String, dynamic>> _rsvp(Map<String, dynamic> json) async {
    final ctx = await _loadContext(json);
    final event = ctx.event;
    final community = ctx.community;

    // Fast fail on the pre-transaction snapshot; re-checked authoritatively
    // inside the transaction below.
    final preConflict = _eligibilityConflict(event);
    if (preConflict != null) throw preConflict;

    final membershipRef = firestore.document(
      'memberships/${ctx.userId}/community-membership/${ctx.communityId}',
    );
    final participantsCollection = firestore.collection(
      '${event.collectionPath}/${ctx.eventId}/event-participants',
    );
    final participantRef = participantsCollection.document(ctx.userId);

    final answeredQuestions = _parseBreakoutSurveyAnswers(json, ctx);

    final optInToCommunity = _optBool(json, 'optInToCommunity', orElse: false);
    final optInToNewsletters =
        _optBool(json, 'optInToNewsletters', orElse: false);
    final joinParameters = _optStringMap(json, 'joinParameters');
    final zipCode = _valueOrNull(_optString(json, 'zipCode'));
    final externalCommunityId =
        _valueOrNull(_optString(json, 'externalCommunityId'));

    // Same field set the app writes in FirestoreEventService.joinEvent. The
    // scheduledTime/lastUpdatedTime converters serialize to a server
    // timestamp sentinel, matching the app's quirky behavior.
    final participant = Participant(
      id: ctx.userId,
      communityId: ctx.communityId,
      templateId: ctx.templateId,
      status: ParticipantStatus.active,
      scheduledTime: event.scheduledTime,
      externalCommunityId: externalCommunityId,
      joinParameters: joinParameters,
      utmSource: joinParameters?['utm_source'],
      utmMedium: joinParameters?['utm_medium'],
      utmCampaign: joinParameters?['utm_campaign'],
      breakoutRoomSurveyQuestions: answeredQuestions,
      zipCode: zipCode,
      optInToCommunity: optInToCommunity,
      optInToNewsletters: optInToNewsletters,
    );

    // optInToCommunity is the app's "Follow this Space" checkbox: it joins
    // the Space as a member; a plain RSVP only marks the user as attendee.
    final targetStatus =
        optInToCommunity ? MembershipStatus.member : MembershipStatus.attendee;

    // All decision-critical reads (event eligibility, participant status,
    // membership status, Space approval policy, capacity) happen inside the
    // transaction: transactional reads hold pessimistic locks, so a
    // concurrent cancel/end/lock or ban can't slip past the checks and two
    // requests can't both take the last seat. Outcomes are captured in
    // variables instead of thrown from the callback: exceptions there cross
    // a Dart->JS promise boundary and may not surface with their type
    // intact.
    final eventRef = firestore.document(event.fullPath);
    final communityRef = firestore.document('community/${ctx.communityId}');
    _ApiException? conflict;
    var alreadyRegistered = false;
    await firestore.runTransaction((transaction) async {
      // Reset in case the transaction retries.
      conflict = null;
      alreadyRegistered = false;

      // Reads must precede writes within a Firestore transaction.

      // Re-read the event so a concurrent cancel/end/lock conflicts with
      // this transaction instead of racing the pre-transaction check.
      final eventInTx = await transaction.get(eventRef);
      if (!eventInTx.exists) {
        conflict = _ApiException(404, 'This event no longer exists.');
        return;
      }
      final freshEvent = Event.fromJson(
        firestoreUtils.fromFirestoreJson(
          eventInTx.data.toMap()..['id'] = eventInTx.documentID,
        ),
      );
      conflict = _eligibilityConflict(freshEvent);
      if (conflict != null) return;

      final participantInTx = await transaction.get(participantRef);
      if (participantInTx.exists) {
        final status = participantInTx.data.toMap()['status'];
        if (status == ParticipantStatus.banned.name) {
          conflict = _ApiException(403, 'This user is banned from this event.');
          return;
        }
        if (status == ParticipantStatus.active.name) {
          alreadyRegistered = true;
          return;
        }
      }

      // Re-read the Space too: an admin can toggle requireApprovalToJoin at
      // any moment, and only a transactional read makes that update conflict
      // with this registration instead of racing past the pre-transaction
      // snapshot.
      var freshCommunity = community;
      final communityInTx = await transaction.get(communityRef);
      if (!communityInTx.exists) {
        conflict = _ApiException(404, 'This Space no longer exists.');
        return;
      }
      try {
        freshCommunity = Community.fromJson(
          firestoreUtils.fromFirestoreJson(
            communityInTx.data.toMap()..['id'] = communityInTx.documentID,
          ),
        );
      } catch (e) {
        // Unparseable Space doc: fall back to the pre-transaction snapshot.
        print('Could not parse community ${ctx.communityId}: $e');
      }

      // Membership: never downgrades (same semantics as the app's
      // changeCommunityMembership with allowMemberDowngrade: false), and a
      // concurrent ban/promotion conflicts and re-evaluates on retry.
      var setMembership = true;
      Membership? currentMembership;
      final membershipInTx = await transaction.get(membershipRef);
      if (membershipInTx.exists) {
        try {
          currentMembership = Membership.fromJson(
            firestoreUtils.fromFirestoreJson(membershipInTx.data.toMap()),
          );
        } catch (e) {
          // Unparseable membership doc: leave it untouched.
          print('Could not parse membership for ${ctx.userId}: $e');
          setMembership = false;
        }
      }
      if (currentMembership?.status == MembershipStatus.banned) {
        conflict = _ApiException(403, 'This user is banned from this Space.');
        return;
      }
      if (freshCommunity.settingsMigration.requireApprovalToJoin &&
          !(currentMembership?.isMember ?? false)) {
        conflict = _ApiException(
          403,
          'This Space requires membership approval to join events, and this '
          'user is not an approved member.',
        );
        return;
      }
      if (currentMembership != null) {
        setMembership = targetStatus == MembershipStatus.member
            ? !currentMembership.isMember
            : !currentMembership.isAttendee;
      }

      // Capacity mirrors the app's FULL state, which only exists for hosted
      // events (event_info.dart's _status short-circuits to needsParticipants
      // for non-hosted). Hostless events carry maxParticipants 10000, so
      // scanning their roster here would transactionally lock every active
      // participant doc and make concurrent registrations retry for nothing.
      // getQuery locks the scanned range, so on hosted events a concurrent
      // registration conflicts and forces a retry that re-counts.
      final maxParticipants = freshEvent.maxParticipants ?? 0;
      if (freshEvent.isHosted && maxParticipants > 0) {
        final activeParticipants = await transaction.getQuery(
          participantsCollection
              .where(
                Participant.kFieldStatus,
                isEqualTo: ParticipantStatus.active.name,
              )
              .limit(maxParticipants),
        );
        if (activeParticipants.documents.length >= maxParticipants) {
          conflict = _ApiException(409, 'This event is full.');
          return;
        }
      }

      // Merge (not overwrite), like the app: a re-RSVP after cancelling
      // reactivates the same doc.
      transaction.set(
        participantRef,
        DocumentData.fromMap({
          ...firestoreUtils.toFirestoreJson(participant.toJson()),
          Participant.kFieldCreatedDate:
              Firestore.fieldValues.serverTimestamp(),
        }),
        merge: true,
      );

      if (setMembership) {
        transaction.set(
          membershipRef,
          DocumentData.fromMap(
            firestoreUtils.toFirestoreJson(
              jsonSubset(
                [
                  Membership.kFieldUserId,
                  Membership.kFieldCommunityId,
                  Membership.kFieldStatus,
                  // Only on first creation (server timestamp via the model's
                  // serializer, like the updateMembership onCall) so later
                  // status upgrades keep the original join date.
                  if (!membershipInTx.exists) Membership.kFieldFirstJoined,
                ],
                Membership(
                  userId: ctx.userId,
                  communityId: ctx.communityId,
                  status: targetStatus,
                  firstJoined: DateTime.now(),
                ).toJson(),
              ),
            ),
          ),
          merge: true,
        );
      }
    });
    final rsvpConflict = conflict;
    if (rsvpConflict != null) throw rsvpConflict;
    if (alreadyRegistered) {
      // Mirrors the app, where an active registrant can't re-submit the RSVP
      // form: registration data is only applied on initial registration or
      // re-registration after cancel. Report what was ignored instead of
      // silently succeeding so callers don't believe updates were saved.
      const registrationFields = [
        'breakoutSurveyAnswers',
        'optInToCommunity',
        'optInToNewsletters',
        'zipCode',
        'joinParameters',
        'externalCommunityId',
      ];
      final ignoredFields = registrationFields.where(json.containsKey).toList();
      return {
        '_statusCode': 200,
        'status': 'already-registered',
        'userId': ctx.userId,
        'eventPath': event.fullPath,
        'eventUrl': ctx.eventUrl,
        if (ignoredFields.isNotEmpty) ...{
          'ignoredFields': ignoredFields,
          'note': 'User was already registered, so the supplied registration '
              'fields were not applied. Cancel and re-register to change '
              'them.',
        },
      };
    }

    // Post-registration side effects are best-effort: the registration is
    // already committed, so failures are reported as warnings, not errors.
    final warnings = <String>[];

    // Remember the user's matching-question answers on their private user
    // doc, so the app pre-fills them on their next RSVP (mirrors the app's
    // saveMatchingQuestionAnswers). Note: SetOptions(merge: true) merges
    // nested maps per key in the Admin SDK (the update mask is built from
    // leaf field paths, verified empirically), so answers saved for other
    // questions are preserved — same outcome as the app's read-then-overlay
    // transaction, without the read.
    final answersToSave = <String, String>{
      for (final question in answeredQuestions)
        if (question.answerOptionId.isNotEmpty)
          question.id: question.answerOptionId,
    };
    if (answersToSave.isNotEmpty) {
      try {
        await firestore.document('privateUserData/${ctx.userId}').setData(
              DocumentData.fromMap({
                'savedMatchingQuestionAnswers': answersToSave,
                'savedMatchingQuestionAnswersUpdatedAt':
                    Firestore.fieldValues.serverTimestamp(),
              }),
              SetOptions(merge: true),
            );
      } catch (e) {
        warnings.add('Failed to save matching-question answers: $e');
      }
    }

    // Sign-up confirmation email, with the same suppression rule as the
    // joinEvent onCall (per-event reminderEmails setting, Space fallback).
    final suppressEmail = !(event.eventSettings?.reminderEmails ??
        community.eventSettingsMigration.reminderEmails ??
        true);
    var emailQueued = false;
    if (!suppressEmail) {
      try {
        await EventEmails().sendEmailsToUsers(
          eventPath: event.fullPath,
          userIds: [ctx.userId],
          emailType: EventEmailType.initialSignUp,
        );
        emailQueued = true;
      } catch (e) {
        warnings.add('Failed to send sign-up confirmation email: $e');
      }
    }

    // Same analytics event the app fires on RSVP (event_page_provider), so
    // API registrations show up in dashboards too. Uses the server-side
    // Segment util the payments webhooks already use. Awaited: functions
    // may freeze background work once the response closes, and awaiting
    // lets config/network failures land in warnings. Still best-effort -
    // never fails a committed registration.
    try {
      await analyticsUtil.logEvent(
        userId: ctx.userId,
        event: AnalyticsRsvpEventEvent(
          communityId: ctx.communityId,
          eventId: ctx.eventId,
          templateId: ctx.templateId,
        ),
      );
    } catch (e) {
      warnings.add('Failed to log RSVP analytics event: $e');
    }

    return {
      'status': 'registered',
      'userId': ctx.userId,
      'eventId': ctx.eventId,
      'eventPath': event.fullPath,
      'eventUrl': ctx.eventUrl,
      'eventTitle': event.title,
      'scheduledTimeUtc': event.scheduledTime?.toUtc().toIso8601String(),
      'confirmationEmailQueued': emailQueued,
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }

  /// Parses `breakoutSurveyAnswers` ([{"question": ..., "answer": ...}])
  /// against the event's smart-match questions. Questions and answers match
  /// by text (case-insensitive) or by internal ID.
  ///
  /// Mirrors the app's survey dialog: when the event asks matching questions
  /// (and, for hosted events, predefined breakouts are enabled), the RSVP
  /// requires an answer to every question; otherwise answers are optional.
  List<BreakoutQuestion> _parseBreakoutSurveyAnswers(
    Map<String, dynamic> json,
    _RsvpContext ctx,
  ) {
    final event = ctx.event;
    final questions = event.breakoutRoomDefinition?.breakoutQuestions ?? [];

    final raw = json['breakoutSurveyAnswers'];
    if (raw != null && (raw is! List || raw.any((entry) => entry is! Map))) {
      throw _ApiException(
        400,
        'Field "breakoutSurveyAnswers" must be an array of '
        '{"question": ..., "answer": ...} objects.',
      );
    }
    final providedRaw = raw == null
        ? <Map<String, dynamic>>[]
        : (raw as List)
            .map((entry) => Map<String, dynamic>.from(entry as Map))
            .toList();

    if (questions.isEmpty) {
      if (providedRaw.isNotEmpty) {
        throw _ApiException(
          400,
          'This event has no matching questions; remove '
          '"breakoutSurveyAnswers".',
        );
      }
      return [];
    }

    // Same visibility rule as the app's RSVP survey dialog (event settings,
    // Space fallback; the template layer is skipped because events store
    // their resolved settings at creation).
    final allowPredefineOnHosted = event
            .eventSettings?.allowPredefineBreakoutsOnHosted ??
        ctx.community.eventSettingsMigration.allowPredefineBreakoutsOnHosted ??
        false;
    final surveyRequired = !event.isHosted || allowPredefineOnHosted;

    if (providedRaw.isEmpty && !surveyRequired) return [];

    String normalize(String value) => value.trim().toLowerCase();

    final answersByQuestion = <String, String>{};
    for (var i = 0; i < providedRaw.length; i++) {
      final entry = providedRaw[i];
      final prefix = 'breakoutSurveyAnswers[$i].';
      final questionText = _optString(entry, 'question', prefix) ?? '';
      final answerText = _optString(entry, 'answer', prefix) ?? '';
      if (questionText.isEmpty || answerText.isEmpty) {
        throw _ApiException(
          400,
          '"$prefix" requires non-empty "question" and "answer".',
        );
      }
      answersByQuestion[normalize(questionText)] = answerText;
    }

    final answered = <BreakoutQuestion>[];
    final missing = <String>[];
    final matchedKeys = <String>{};
    for (final question in questions) {
      final answerText = answersByQuestion[normalize(question.title)] ??
          answersByQuestion[normalize(question.id)];
      if (answerText == null) {
        missing.add(question.title);
        answered.add(question.copyWith(answerOptionId: ''));
        continue;
      }
      matchedKeys.add(normalize(question.title));
      matchedKeys.add(normalize(question.id));

      final options =
          question.answers.expand((answer) => answer.options).toList();
      final option = options
          .where(
            (candidate) =>
                normalize(candidate.title) == normalize(answerText) ||
                candidate.id == answerText,
          )
          .cast<BreakoutAnswerOption?>()
          .firstWhere((_) => true, orElse: () => null);
      if (option == null) {
        throw _ApiException(
          400,
          'Answer "$answerText" does not match any option of question '
          '"${question.title}". Options: '
          '${options.map((candidate) => candidate.title).join(', ')}.',
        );
      }
      answered.add(question.copyWith(answerOptionId: option.id));
    }

    final unmatched = answersByQuestion.keys
        .where((key) => !matchedKeys.contains(key))
        .toList();
    if (unmatched.isNotEmpty) {
      throw _ApiException(
        400,
        'breakoutSurveyAnswers contains unknown question(s): '
        '${unmatched.join(', ')}. This event asks: '
        '${questions.map((question) => question.title).join(', ')}.',
      );
    }

    // Supplied answers must be complete either way (the dialog's Finish
    // button is disabled until every question is answered), but only claim
    // the *event* requires them when the survey is actually required.
    if (missing.isNotEmpty) {
      throw _ApiException(
        400,
        surveyRequired
            ? 'This event requires an answer to every matching question. '
                'Missing: ${missing.join(', ')}.'
            : 'When "breakoutSurveyAnswers" is provided it must answer every '
                'matching question (or be omitted entirely). '
                'Missing: ${missing.join(', ')}.',
      );
    }

    return answered;
  }

  // ---------------------------------------------------------------------------
  // Cancel
  // ---------------------------------------------------------------------------

  // Deliberately does not gate on event eligibility (canceled/ended/locked):
  // the app's ?cancel=true email-link flow cancels participation regardless
  // of event state, and cancelling on an ended/locked event is harmless.
  Future<Map<String, dynamic>> _cancel(Map<String, dynamic> json) async {
    final ctx = await _loadContext(json);

    final participantRef = firestore.document(
      '${ctx.event.collectionPath}/${ctx.eventId}/event-participants/${ctx.userId}',
    );

    // Status is read inside the transaction (pessimistic lock) so a
    // concurrent ban can't be overwritten with `canceled`, which would let a
    // later RSVP reactivate a banned user. Outcomes are captured in
    // variables, not thrown from the callback (Dart->JS promise boundary).
    _ApiException? conflict;
    var alreadyCanceled = false;
    await firestore.runTransaction((transaction) async {
      // Reset in case the transaction retries.
      conflict = null;
      alreadyCanceled = false;

      final participantInTx = await transaction.get(participantRef);
      if (!participantInTx.exists) {
        conflict = _ApiException(
          404,
          'User "${ctx.userId}" is not registered for this event.',
        );
        return;
      }
      final status = participantInTx.data.toMap()['status'];
      if (status == ParticipantStatus.banned.name) {
        conflict = _ApiException(403, 'This user is banned from this event.');
        return;
      }
      if (status == ParticipantStatus.canceled.name) {
        alreadyCanceled = true;
        return;
      }

      // Same write as the app's removeParticipant: keep the doc, flip status
      // to canceled (also removes the user from future reminder emails).
      transaction.set(
        participantRef,
        DocumentData.fromMap(
          firestoreUtils.toFirestoreJson(
            jsonSubset(
              [Participant.kFieldLastUpdatedTime, Participant.kFieldStatus],
              Participant(
                id: ctx.userId,
                status: ParticipantStatus.canceled,
              ).toJson(),
            ),
          ),
        ),
        merge: true,
      );
    });
    final cancelConflict = conflict;
    if (cancelConflict != null) throw cancelConflict;
    if (alreadyCanceled) {
      return {
        'status': 'already-canceled',
        'userId': ctx.userId,
        'eventPath': ctx.event.fullPath,
      };
    }

    return {
      'status': 'canceled',
      'userId': ctx.userId,
      'eventId': ctx.eventId,
      'eventPath': ctx.event.fullPath,
      'eventUrl': ctx.eventUrl,
      'eventTitle': ctx.event.title,
    };
  }

  @override
  void register(FirebaseFunctions functions) {
    functions[functionName] = functions
        .runWith(
          RuntimeOptions(timeoutSeconds: 60, memory: '1GB', minInstances: 0),
        )
        .https
        .onRequest(expressAction);
  }
}

class _RsvpContext {
  final String userId;
  final String communityId;
  final String templateId;
  final String eventId;
  final Community community;
  final Event event;

  _RsvpContext({
    required this.userId,
    required this.communityId,
    required this.templateId,
    required this.eventId,
    required this.community,
    required this.event,
  });

  String get eventUrl {
    final displayId = community.displayIds.isNotEmpty
        ? community.displayIds.first
        : communityId;
    return '/space/$displayId/discuss/$templateId/$eventId';
  }
}
