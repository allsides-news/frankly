import 'dart:async';
import 'dart:convert';

import 'package:firebase_admin_interop/firebase_admin_interop.dart'
    hide EventType;
import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    hide CloudFunction;
import 'package:timezone/standalone.dart' as tz;
import 'package:uuid/uuid.dart';
import '../cloud_function.dart';
import '../utils/infra/firebase_auth_utils.dart';
import '../utils/infra/firestore_utils.dart';
import '../utils/timezone_utils.dart';
import 'live_meetings/breakouts/check_hostless_go_to_breakouts.dart';
import 'live_meetings/mux_client.dart';
import 'notifications/event_emails.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/media_item.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/events/pre_post_card_attribute.dart';
import 'package:data_models/events/pre_post_survey.dart';
import 'package:data_models/events/pre_post_url_params.dart';
import 'package:data_models/templates/template.dart';
import 'package:data_models/utils/utils.dart';

/// Error with an HTTP status code so validation failures return proper
/// 4xx responses instead of a generic 500.
class _ApiException implements Exception {
  final int statusCode;
  final String message;

  _ApiException(this.statusCode, this.message);
}

/// HTTP endpoint (POST + JSON) for creating an Event in a Space (community)
/// from outside the app, e.g. curl or another backend.
///
/// Mirrors the client "Create a new Event" pathway
/// (create_event_dialog_model.dart + FirestoreEventService.createEventIfNotExists
/// + the createEvent onCall follow-up): event doc, owner participant (RSVP),
/// and membership upgrade are written in one transaction, then the sign-up
/// confirmation email, reminder scheduling, and (for hostless events) the
/// go-to-breakouts check run best-effort, with failures reported in
/// `warnings` rather than failing the request (the event already exists, so
/// a retry would duplicate it).
///
/// Auth: requires an `x-api-key` header matching the
/// `app.create_space_api_key` functions config value (shared with
/// createCommunityApi). Fails closed (503) if the key is not configured.
///
/// Example payload: see scripts/create-event-example.json
class CreateEventApi implements CloudFunction {
  @override
  final String functionName = 'createEventApi';

  static const _uuid = Uuid();

  /// Default agenda when neither the payload nor the template provides one.
  /// Mirrors the client's defaultAgendaItems (meeting_agenda_provider.dart) /
  /// English l10n strings.
  static final List<AgendaItem> _defaultAgendaItems = [
    AgendaItem(
      id: 'default-intro-0',
      title: 'Introductions',
      content:
          '_Introduce yourselves!  Each take one minute to answer one of the '
          'following questions._\n\n'
          '* What\'s something you did recently that was a lot of fun?\n'
          '* Who is your favorite cartoon character and why?\n'
          '* What\'s one thing you wish to accomplish before you die?\n'
          '* What movie did you NOT like?\n',
    ),
  ];

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

      // Fail closed: refuse all requests until an API key is configured via
      // `firebase functions:config:set app.create_space_api_key="..."`.
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

      final result = await _createEvent(Map<String, dynamic>.from(body));
      await _sendJson(expressRequest, 201, result);
    } on _ApiException catch (e) {
      await _sendJson(expressRequest, e.statusCode, {'error': e.message});
    } catch (e, stacktrace) {
      print('Error in $functionName');
      print(e);
      print(stacktrace);
      await _sendJson(
        expressRequest,
        500,
        {'error': 'Internal error creating event: $e'},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Typed payload readers. [prefix] qualifies error messages for nested
  // objects, e.g. 'agendaItems[2].'. Throw 400 on wrong types so bad client
  // input doesn't surface as a 500 from a cast.
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

  bool? _optBool(Map<String, dynamic> json, String key, [String prefix = '']) {
    final value = json[key];
    if (value == null) return null;
    if (value is! bool) {
      throw _ApiException(400, 'Field "$prefix$key" must be a boolean.');
    }
    return value;
  }

  int? _optInt(Map<String, dynamic> json, String key, [String prefix = '']) {
    final value = json[key];
    if (value == null) return null;
    if (value is! int) {
      throw _ApiException(400, 'Field "$prefix$key" must be an integer.');
    }
    return value;
  }

  Map<String, dynamic>? _optMap(
    Map<String, dynamic> json,
    String key, [
    String prefix = '',
  ]) {
    final value = json[key];
    if (value == null) return null;
    if (value is! Map) {
      throw _ApiException(400, 'Field "$prefix$key" must be an object.');
    }
    return Map<String, dynamic>.from(value);
  }

  List<Map<String, dynamic>>? _optListOfMaps(
    Map<String, dynamic> json,
    String key, [
    String prefix = '',
  ]) {
    final value = json[key];
    if (value == null) return null;
    if (value is! List || value.any((entry) => entry is! Map)) {
      throw _ApiException(
        400,
        'Field "$prefix$key" must be an array of objects.',
      );
    }
    return value.map((entry) => Map<String, dynamic>.from(entry)).toList();
  }

  List<String>? _optListOfStrings(
    Map<String, dynamic> json,
    String key, [
    String prefix = '',
  ]) {
    final value = json[key];
    if (value == null) return null;
    if (value is! List || value.any((entry) => entry is! String)) {
      throw _ApiException(
        400,
        'Field "$prefix$key" must be an array of strings.',
      );
    }
    return value.cast<String>().map((entry) => entry.trim()).toList();
  }

  /// Reads a `{"minutes": int, "seconds": int}` object into total seconds.
  int? _optDurationSeconds(
    Map<String, dynamic> json,
    String key, [
    String prefix = '',
  ]) {
    final raw = _optMap(json, key, prefix);
    if (raw == null) return null;
    final minutes = _optInt(raw, 'minutes', '$prefix$key.') ?? 0;
    final seconds = _optInt(raw, 'seconds', '$prefix$key.') ?? 0;
    if (minutes < 0 || seconds < 0) {
      throw _ApiException(
        400,
        '"$prefix$key" minutes/seconds must not be negative.',
      );
    }
    return minutes * 60 + seconds;
  }

  // ---------------------------------------------------------------------------
  // Main flow
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _createEvent(Map<String, dynamic> json) async {
    final ownerUserId = _optString(json, 'ownerUserId') ?? '';
    if (ownerUserId.isEmpty) {
      throw _ApiException(400, 'ownerUserId is required.');
    }

    final communityId = _optString(json, 'communityId') ?? '';
    if (communityId.isEmpty) {
      throw _ApiException(
        400,
        'communityId is required (the Space document ID).',
      );
    }

    // Verify the owner exists in Firebase Auth before creating anything.
    try {
      await firebaseAuthUtils.getUser(ownerUserId);
    } catch (_) {
      throw _ApiException(
        400,
        'No Firebase Auth user found for ownerUserId "$ownerUserId".',
      );
    }

    // Verify the Space exists; its displayId builds the event URL and its
    // event settings are the defaults for this event.
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

    // Optional event template. 'misc' is the app's synthetic default template
    // (template_provider.dart) and has no Firestore doc, so it's not fetched.
    var templateId = _optString(json, 'templateId') ?? '';
    Template? template;
    if (templateId.isEmpty) {
      templateId = 'misc';
    } else if (templateId != 'misc') {
      final templateDoc = await firestore
          .document('community/$communityId/templates/$templateId')
          .get();
      if (!templateDoc.exists) {
        throw _ApiException(
          404,
          'No template "$templateId" found in Space "$communityId".',
        );
      }
      template = Template.fromJson(
        firestoreUtils.fromFirestoreJson(
          templateDoc.data.toMap()..['id'] = templateDoc.documentID,
        ),
      );
    }

    // --- Required core fields -------------------------------------------------

    final isPublicRaw = json['isPublic'];
    if (isPublicRaw is! bool) {
      throw _ApiException(400, '"isPublic" is required and must be a boolean.');
    }
    final isPublic = isPublicRaw;

    final eventTypeName = _optString(json, 'eventType') ?? '';
    final eventType = EventType.values
        .where((type) => type.name == eventTypeName)
        .cast<EventType?>()
        .firstWhere((_) => true, orElse: () => null);
    if (eventType == null) {
      throw _ApiException(
        400,
        '"eventType" is required and must be one of: '
        '${EventType.values.map((type) => type.name).join(', ')}.',
      );
    }

    final scheduled = _parseScheduledTime(json);
    final scheduledTimeUtc = scheduled.toUtc();
    final scheduledTimeZone = scheduled.location.name;

    // Owner RSVP: true/"yes" registers the owner as a participant (the app's
    // "I'll be there!" confirmation); false/"no" creates the event without
    // registering them. Accepts a boolean or a "yes"/"no" string.
    final ownerRsvp = _parseOwnerRsvp(json);

    final eventSettings = _parseEventSettings(
      json,
      template?.eventSettings ?? community.eventSettingsMigration,
    );

    // --- Optional content fields ---------------------------------------------

    final title = _valueOrNull(_optString(json, 'title')) ??
        template?.title ??
        'My Custom Event';
    final description = _valueOrNull(_optString(json, 'description')) ??
        template?.description ??
        '';

    final durationInMinutes = _optInt(json, 'durationInMinutes') ?? 60;
    if (durationInMinutes <= 0) {
      throw _ApiException(400, '"durationInMinutes" must be greater than 0.');
    }

    final maxParticipants = _optInt(json, 'maxParticipants') ??
        (eventType == EventType.hosted
            ? Event.defaultMaxParticipants
            : Event.defaultMaxParticipantsInHostlessEvent);
    if (maxParticipants <= 0) {
      throw _ApiException(400, '"maxParticipants" must be greater than 0.');
    }

    final externalPlatform = _parsePlatform(json);

    var agendaItems = _parseAgendaItems(json);
    if (agendaItems.isEmpty) {
      agendaItems = template?.agendaItems ?? [];
    }
    if (agendaItems.isEmpty) {
      agendaItems = _defaultAgendaItems.map((item) => item.copyWith()).toList();
    }

    final waitingRoomInfo = _parseWaitingRoom(json);
    final breakoutRoomDefinition = _parseBreakouts(json, ownerUserId);

    final preEventCardData =
        _parsePrePostCard(json, 'preEventCta', PrePostCardType.preEvent) ??
            template?.preEventCardData;
    final postEventCardData =
        _parsePrePostCard(json, 'postEventCta', PrePostCardType.postEvent) ??
            template?.postEventCardData;

    // --- Livestream events need a Mux stream (mirrors CreateLiveStream) ------

    LiveStreamInfo? liveStreamInfo;
    PrivateLiveStreamInfo? privateLiveStreamInfo;
    if (eventType == EventType.livestream) {
      try {
        final liveStream = await muxApi.createLiveStream();
        liveStreamInfo = LiveStreamInfo(
          muxId: liveStream['id'],
          muxPlaybackId: (liveStream['playback_ids'] as List<dynamic>)
              .firstWhere((entry) => entry['policy'] == 'public')['id'],
        );
        privateLiveStreamInfo = PrivateLiveStreamInfo(
          streamServerUrl: 'rtmp://global-live.mux.com:5222/app',
          streamKey: liveStream['stream_key'],
        );
      } catch (e) {
        throw _ApiException(502, 'Failed to create Mux live stream: $e');
      }
    }

    // --- Build the event ------------------------------------------------------

    final eventsCollectionPath =
        'community/$communityId/templates/$templateId/events';
    final eventRef = firestore.collection(eventsCollectionPath).document();
    final eventId = eventRef.documentID;

    final event = Event(
      id: eventId,
      status: EventStatus.active,
      nullableEventType: eventType,
      collectionPath: eventsCollectionPath,
      communityId: communityId,
      templateId: templateId,
      creatorId: ownerUserId,
      prerequisiteTemplateId: template?.prerequisiteTemplateId,
      scheduledTime: scheduledTimeUtc,
      scheduledTimeZone: scheduledTimeZone,
      title: title,
      description: description,
      image: _valueOrNull(_optString(json, 'image')) ??
          template?.image ??
          'https://picsum.photos/seed/$eventId/512',
      isPublic: isPublic,
      minParticipants: Event.defaultMinParticipants,
      maxParticipants: maxParticipants,
      agendaItems: agendaItems,
      waitingRoomInfo: waitingRoomInfo,
      breakoutRoomDefinition: breakoutRoomDefinition,
      isLocked: false,
      liveStreamInfo: liveStreamInfo,
      preEventCardData: preEventCardData,
      postEventCardData: postEventCardData,
      externalPlatform: externalPlatform,
      eventSettings: eventSettings,
      durationInMinutes: durationInMinutes,
    );

    final membershipRef = firestore.document(
      'memberships/$ownerUserId/community-membership/$communityId',
    );

    try {
      await firestore.runTransaction((transaction) async {
        // Owner membership: same semantics as the client's
        // changeCommunityMembership(newStatus: attendee,
        // allowMemberDowngrade: false) - only set attendee when they aren't
        // already attendee or higher. Read inside the transaction (reads
        // must precede writes) so a concurrent promotion holds a lock and
        // can't be overwritten with attendee; the decision is re-evaluated
        // if the transaction retries.
        var setMembership = true;
        final membershipDoc = await transaction.get(membershipRef);
        if (membershipDoc.exists) {
          try {
            final membership = Membership.fromJson(
              firestoreUtils.fromFirestoreJson(membershipDoc.data.toMap()),
            );
            setMembership = !membership.isAttendee;
          } catch (e) {
            // Unparseable membership doc: leave it untouched.
            print('Could not parse membership for $ownerUserId: $e');
            setMembership = false;
          }
        }

        transaction.set(
          eventRef,
          DocumentData.fromMap(firestoreUtils.toFirestoreJson(event.toJson())),
        );

        if (ownerRsvp) {
          final participant = Participant(
            id: ownerUserId,
            communityId: communityId,
            templateId: templateId,
            status: ParticipantStatus.active,
          );
          transaction.set(
            firestore
                .document('$eventsCollectionPath/$eventId')
                .collection('event-participants')
                .document(ownerUserId),
            DocumentData.fromMap({
              ...firestoreUtils.toFirestoreJson(participant.toJson()),
              Participant.kFieldCreatedDate:
                  Firestore.fieldValues.serverTimestamp(),
            }),
          );
        }

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
                    // Only on first creation (server timestamp via the
                    // model's serializer, like the updateMembership onCall)
                    // so later status upgrades keep the original join date.
                    if (!membershipDoc.exists) Membership.kFieldFirstJoined,
                  ],
                  Membership(
                    userId: ownerUserId,
                    communityId: communityId,
                    status: MembershipStatus.attendee,
                    firstJoined: DateTime.now(),
                  ).toJson(),
                ),
              ),
            ),
            merge: true,
          );
        }

        if (privateLiveStreamInfo != null) {
          transaction.set(
            firestore.document(
              '$eventsCollectionPath/$eventId/private-live-stream-info/$eventId',
            ),
            DocumentData.fromMap(
              firestoreUtils.toFirestoreJson(privateLiveStreamInfo.toJson()),
            ),
          );
        }
      });
    } catch (e) {
      // If the event failed to persist, a Mux stream provisioned above would
      // otherwise leak as a billable orphan (and retries would provision
      // more). Deletion is best-effort; the original error is rethrown.
      final muxId = liveStreamInfo?.muxId;
      if (muxId != null) {
        try {
          await muxApi.deleteLiveStream(muxId);
          print('Deleted orphaned Mux stream $muxId after failed event write');
        } catch (deleteError) {
          print('Failed to delete orphaned Mux stream $muxId: $deleteError');
        }
      }
      rethrow;
    }

    // Post-create side effects mirror the createEvent onCall follow-up
    // (create_event.dart). Best-effort: the event is already committed, so a
    // failure here must not fail the request (a retry would duplicate the
    // event); failures are reported in `warnings` instead.
    final warnings = <String>[];

    if (ownerRsvp) {
      try {
        await EventEmails().sendEmailsToUsers(
          eventPath: event.fullPath,
          userIds: [ownerUserId],
          emailType: EventEmailType.initialSignUp,
        );
      } catch (e) {
        warnings.add('Failed to send sign-up confirmation email: $e');
      }
    }

    try {
      await EventEmails().enqueueReminders(event);
    } catch (e) {
      warnings.add('Failed to schedule reminder emails: $e');
    }

    if (eventType == EventType.hostless) {
      try {
        await CheckHostlessGoToBreakouts().enqueueScheduledCheck(event);
      } catch (e) {
        warnings.add('Failed to schedule hostless breakouts check: $e');
      }
    }

    final displayId = community.displayIds.isNotEmpty
        ? community.displayIds.first
        : communityId;

    return {
      'eventId': eventId,
      'eventPath': event.fullPath,
      'eventUrl': '/space/$displayId/discuss/$templateId/$eventId',
      'eventType': eventType.name,
      'scheduledTimeUtc': scheduledTimeUtc.toIso8601String(),
      'scheduledTimeZone': scheduledTimeZone,
      'ownerRsvped': ownerRsvp,
      if (liveStreamInfo != null)
        'liveStream': {
          'muxId': liveStreamInfo.muxId,
          'muxPlaybackId': liveStreamInfo.muxPlaybackId,
          'streamServerUrl': privateLiveStreamInfo?.streamServerUrl,
          'streamKey': privateLiveStreamInfo?.streamKey,
        },
      if (warnings.isNotEmpty) 'warnings': warnings,
    };
  }

  /// Empty strings from the payload fall through to the next default.
  String? _valueOrNull(String? value) =>
      (value == null || value.isEmpty) ? null : value;

  // ---------------------------------------------------------------------------
  // Section parsers
  // ---------------------------------------------------------------------------

  /// Combines required `scheduledDate` ("YYYY-MM-DD") + `scheduledTime`
  /// ("HH:mm", 24h) in optional `scheduledTimeZone` (IANA name, default
  /// America/Los_Angeles) into an absolute time.
  tz.TZDateTime _parseScheduledTime(Map<String, dynamic> json) {
    final dateStr = _optString(json, 'scheduledDate') ?? '';
    final timeStr = _optString(json, 'scheduledTime') ?? '';
    final zoneName = _valueOrNull(_optString(json, 'scheduledTimeZone')) ??
        'America/Los_Angeles';

    final dateMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(dateStr);
    if (dateMatch == null) {
      throw _ApiException(
        400,
        '"scheduledDate" is required, format YYYY-MM-DD.',
      );
    }
    final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(timeStr);
    if (timeMatch == null) {
      throw _ApiException(
        400,
        '"scheduledTime" is required, format HH:mm (24-hour).',
      );
    }

    tz.Location location;
    try {
      location = timezoneUtils.getLocation(zoneName);
    } catch (_) {
      throw _ApiException(
        400,
        '"scheduledTimeZone" must be a valid IANA time zone name, e.g. '
        '"America/Los_Angeles".',
      );
    }

    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);
    final hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw _ApiException(400, '"scheduledDate" is not a valid date.');
    }
    if (hour > 23 || minute > 59) {
      throw _ApiException(400, '"scheduledTime" is not a valid time of day.');
    }

    final year = int.parse(dateMatch.group(1)!);
    final scheduled = tz.TZDateTime(
      location,
      year,
      month,
      day,
      hour,
      minute,
    );
    // DateTime-based construction normalizes overflowing components (e.g.
    // Feb 31 -> Mar 3), so reject any date that didn't survive round-trip.
    // Hour/minute are deliberately not compared: a time inside a DST
    // spring-forward gap legitimately shifts to the next valid clock time.
    if (scheduled.year != year ||
        scheduled.month != month ||
        scheduled.day != day) {
      throw _ApiException(400, '"scheduledDate" is not a valid date.');
    }
    return scheduled;
  }

  bool _parseOwnerRsvp(Map<String, dynamic> json) {
    final raw = json['ownerRsvp'];
    if (raw is bool) return raw;
    if (raw is String) {
      final normalized = raw.trim().toLowerCase();
      if (normalized == 'yes') return true;
      if (normalized == 'no') return false;
    }
    throw _ApiException(
      400,
      '"ownerRsvp" is required: true or "yes" (owner will attend), '
      'false or "no" (owner not attending).',
    );
  }

  /// Required `eventSettings` object. Keys use the labels from the app's
  /// settings UI; unset keys inherit from the template's settings or the
  /// Space's default event settings. May be an empty object.
  EventSettings _parseEventSettings(
    Map<String, dynamic> json,
    EventSettings base,
  ) {
    final raw = json['eventSettings'];
    if (raw is! Map) {
      throw _ApiException(
        400,
        '"eventSettings" is required and must be an object '
        '(may be empty {} to use the Space defaults).',
      );
    }
    final settings = Map<String, dynamic>.from(raw);

    const allowedKeys = {
      'chat',
      'floatingChat',
      'record',
      'transcribe',
      'screenShare',
      'odometer',
      'agendaPreview',
    };
    final unknownKeys = settings.keys.toSet().difference(allowedKeys);
    if (unknownKeys.isNotEmpty) {
      throw _ApiException(
        400,
        'Unknown eventSettings key(s): ${unknownKeys.join(', ')}. '
        'Allowed: ${allowedKeys.join(', ')}.',
      );
    }

    // UI label -> EventSettings field mapping (see admin settings_tab.dart):
    // Floating Chat = showChatMessagesInRealTime, Record = alwaysRecord,
    // Transcribe = alwaysTranscribe, Screen Share = allowScreenshare,
    // Odometer = talkingTimer, Preview Agenda = agendaPreview.
    const prefix = 'eventSettings.';
    return EventSettings(
      reminderEmails: base.reminderEmails,
      chat: _optBool(settings, 'chat', prefix) ?? base.chat,
      showChatMessagesInRealTime: _optBool(settings, 'floatingChat', prefix) ??
          base.showChatMessagesInRealTime,
      talkingTimer: _optBool(settings, 'odometer', prefix) ?? base.talkingTimer,
      allowScreenshare:
          _optBool(settings, 'screenShare', prefix) ?? base.allowScreenshare,
      allowPredefineBreakoutsOnHosted: base.allowPredefineBreakoutsOnHosted,
      defaultStageView: base.defaultStageView,
      enableBreakoutsByCategory: base.enableBreakoutsByCategory,
      allowMultiplePeopleOnStage: base.allowMultiplePeopleOnStage,
      showSmartMatchingForBreakouts: base.showSmartMatchingForBreakouts,
      alwaysRecord: _optBool(settings, 'record', prefix) ?? base.alwaysRecord,
      alwaysTranscribe:
          _optBool(settings, 'transcribe', prefix) ?? base.alwaysTranscribe,
      enablePrerequisites: base.enablePrerequisites,
      agendaPreview:
          _optBool(settings, 'agendaPreview', prefix) ?? base.agendaPreview,
    );
  }

  PlatformItem? _parsePlatform(Map<String, dynamic> json) {
    final platformJson = _optMap(json, 'platform');
    if (platformJson == null) return null;

    final keyName =
        _valueOrNull(_optString(platformJson, 'platformKey', 'platform.')) ??
            'community';
    final platformKey = PlatformKey.values
        .where((key) => key.name == keyName)
        .cast<PlatformKey?>()
        .firstWhere((_) => true, orElse: () => null);
    if (platformKey == null) {
      throw _ApiException(
        400,
        '"platform.platformKey" must be one of: '
        '${PlatformKey.values.map((key) => key.name).join(', ')}.',
      );
    }

    final url = _optString(platformJson, 'url', 'platform.') ?? '';
    if (platformKey != PlatformKey.community && url.isEmpty) {
      throw _ApiException(
        400,
        '"platform.url" is required for external platforms.',
      );
    }

    return PlatformItem(
      url: url.isEmpty ? null : url,
      platformKey: platformKey,
    );
  }

  List<AgendaItem> _parseAgendaItems(Map<String, dynamic> json) {
    final rawItems = _optListOfMaps(json, 'agendaItems') ?? [];
    final items = <AgendaItem>[];
    for (var i = 0; i < rawItems.length; i++) {
      items.add(_parseAgendaItem(rawItems[i], 'agendaItems[$i].'));
    }
    return items;
  }

  AgendaItem _parseAgendaItem(Map<String, dynamic> item, String prefix) {
    final typeName = _optString(item, 'type', prefix) ?? '';
    final type = AgendaItemType.values
        .where((value) => value.name == typeName)
        .cast<AgendaItemType?>()
        .firstWhere((_) => true, orElse: () => null);
    if (type == null) {
      throw _ApiException(
        400,
        '"${prefix}type" is required and must be one of: '
        '${AgendaItemType.values.map((value) => value.name).join(', ')}.',
      );
    }

    final timeInSeconds = _optDurationSeconds(item, 'timebox', prefix) ??
        AgendaItem.kDefaultTimeInSeconds;

    // Field mapping mirrors the app's agenda editor (agenda_item_presenter
    // saveContent): poll question and word cloud prompt are stored in
    // `content`, the suggestions headline in `title`.
    String? title;
    String? content;
    String? videoUrl;
    String? imageUrl;
    List<String>? pollAnswers;
    var videoType = AgendaItemVideoType.url;

    switch (type) {
      case AgendaItemType.text:
        title = _optString(item, 'title', prefix) ?? '';
        content = _optString(item, 'content', prefix) ?? '';
        break;
      case AgendaItemType.video:
        title = _optString(item, 'title', prefix) ?? '';
        videoUrl = _optString(item, 'videoUrl', prefix) ?? '';
        if (videoUrl.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}videoUrl" is required for video cards.',
          );
        }
        videoType = _videoTypeForUrl(videoUrl);
        break;
      case AgendaItemType.image:
        title = _optString(item, 'title', prefix) ?? '';
        imageUrl = _optString(item, 'imageUrl', prefix) ?? '';
        if (imageUrl.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}imageUrl" is required for image cards.',
          );
        }
        break;
      case AgendaItemType.poll:
        content = _valueOrNull(_optString(item, 'question', prefix)) ??
            _optString(item, 'content', prefix) ??
            '';
        if (content.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}question" is required for poll cards.',
          );
        }
        pollAnswers = _optListOfStrings(item, 'answers', prefix) ??
            _optListOfStrings(item, 'pollAnswers', prefix) ??
            [];
        pollAnswers.removeWhere((answer) => answer.isEmpty);
        if (pollAnswers.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}answers" must have at least one option.',
          );
        }
        if (pollAnswers.toSet().length != pollAnswers.length) {
          throw _ApiException(
            400,
            '"${prefix}answers" must not contain duplicates.',
          );
        }
        break;
      case AgendaItemType.wordCloud:
        content = _valueOrNull(_optString(item, 'prompt', prefix)) ??
            _optString(item, 'content', prefix) ??
            '';
        if (content.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}prompt" is required for wordCloud cards.',
          );
        }
        break;
      case AgendaItemType.userSuggestions:
        title = _valueOrNull(_optString(item, 'headline', prefix)) ??
            _optString(item, 'title', prefix) ??
            '';
        if (title.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}headline" is required for userSuggestions cards.',
          );
        }
        break;
    }

    return AgendaItem(
      id: _uuid.v4(),
      nullableType: type,
      title: title,
      content: content,
      videoType: videoType,
      videoUrl: videoUrl,
      imageUrl: imageUrl,
      pollAnswers: pollAnswers,
      timeInSeconds: timeInSeconds,
    );
  }

  AgendaItemVideoType _videoTypeForUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return AgendaItemVideoType.youtube;
    }
    if (lower.contains('vimeo.com')) {
      return AgendaItemVideoType.vimeo;
    }
    return AgendaItemVideoType.url;
  }

  /// Media type is inferred from the URL, or forced via [explicitType]
  /// ("image"/"video").
  MediaType _mediaTypeForUrl(String url, String? explicitType, String label) {
    if (explicitType != null && explicitType.isNotEmpty) {
      switch (explicitType.toLowerCase()) {
        case 'image':
          return MediaType.image;
        case 'video':
          return MediaType.video;
        default:
          throw _ApiException(400, '"$label" must be "image" or "video".');
      }
    }
    final lower = url.toLowerCase();
    const videoMarkers = [
      '.mp4',
      '.webm',
      '.mov',
      '.m3u8',
      'youtube.com',
      'youtu.be',
      'vimeo.com',
    ];
    return videoMarkers.any(lower.contains) ? MediaType.video : MediaType.image;
  }

  WaitingRoomInfo? _parseWaitingRoom(Map<String, dynamic> json) {
    final raw = _optMap(json, 'waitingRoom');
    if (raw == null) return null;
    const prefix = 'waitingRoom.';

    MediaItem? waitingMediaItem;
    final waitingMediaUrl = _optString(raw, 'waitingMediaUrl', prefix) ?? '';
    if (waitingMediaUrl.isNotEmpty) {
      waitingMediaItem = MediaItem(
        url: waitingMediaUrl,
        type: _mediaTypeForUrl(
          waitingMediaUrl,
          _optString(raw, 'waitingMediaType', prefix),
          '${prefix}waitingMediaType',
        ),
      );
    }

    MediaItem? introMediaItem;
    final introMediaUrl = _optString(raw, 'introMediaUrl', prefix) ?? '';
    if (introMediaUrl.isNotEmpty) {
      introMediaItem = MediaItem(
        url: introMediaUrl,
        type: _mediaTypeForUrl(
          introMediaUrl,
          _optString(raw, 'introMediaType', prefix),
          '${prefix}introMediaType',
        ),
      );
    }

    // Field mapping mirrors the app's waiting room editor
    // (waiting_room_widget_presenter.dart): intro length -> durationSeconds,
    // buffer time -> waitingMediaBufferSeconds, intro text -> content.
    return WaitingRoomInfo(
      content: _optString(raw, 'introText', prefix),
      waitingMediaItem: waitingMediaItem,
      introMediaItem: introMediaItem,
      loopWaitingVideo: _optBool(raw, 'loopWaitingVideo', prefix) ?? false,
      waitingMediaBufferSeconds:
          _optDurationSeconds(raw, 'bufferTime', prefix) ?? 0,
      durationSeconds: _optDurationSeconds(raw, 'introLength', prefix) ?? 0,
    );
  }

  BreakoutRoomDefinition? _parseBreakouts(
    Map<String, dynamic> json,
    String ownerUserId,
  ) {
    final raw = _optMap(json, 'breakouts');
    if (raw == null) return null;
    const prefix = 'breakouts.';

    final methodName =
        _valueOrNull(_optString(raw, 'assignmentMethod', prefix)) ??
            BreakoutAssignmentMethod.targetPerRoom.name;
    // BreakoutAssignmentMethod.category is deliberately not accepted: in the
    // app it only appears behind the enableBreakoutsByCategory dev-settings
    // flipper, and this endpoint's contract covers the standard manual
    // pathway (by size or Smart Match).
    final method = [
      BreakoutAssignmentMethod.targetPerRoom,
      BreakoutAssignmentMethod.smartMatch,
    ]
        .where((value) => value.name == methodName)
        .cast<BreakoutAssignmentMethod?>()
        .firstWhere((_) => true, orElse: () => null);
    if (method == null) {
      throw _ApiException(
        400,
        '"${prefix}assignmentMethod" must be "targetPerRoom" (by size) or '
        '"smartMatch".',
      );
    }

    final targetParticipants = _optInt(raw, 'targetParticipants', prefix) ?? 8;
    if (targetParticipants <= 0) {
      throw _ApiException(
        400,
        '"${prefix}targetParticipants" must be greater than 0.',
      );
    }

    final questionsRaw = _optListOfMaps(raw, 'matchingQuestions', prefix) ?? [];
    if (method == BreakoutAssignmentMethod.smartMatch && questionsRaw.isEmpty) {
      throw _ApiException(
        400,
        '"${prefix}matchingQuestions" is required for smartMatch breakouts.',
      );
    }

    // Question shape mirrors the app's breakout editor
    // (breakout_room_presenter.dart): one BreakoutAnswer per answer choice,
    // each holding a single option; answerOptionId is empty on the event's
    // definition (it records a participant's choice at RSVP time).
    final breakoutQuestions = <BreakoutQuestion>[];
    for (var i = 0; i < questionsRaw.length; i++) {
      final questionPrefix = '${prefix}matchingQuestions[$i].';
      final questionJson = questionsRaw[i];
      final questionText =
          _optString(questionJson, 'question', questionPrefix) ?? '';
      if (questionText.isEmpty) {
        throw _ApiException(400, '"${questionPrefix}question" is required.');
      }
      final answers =
          _optListOfStrings(questionJson, 'answers', questionPrefix) ?? [];
      answers.removeWhere((answer) => answer.isEmpty);
      if (answers.length < 2) {
        throw _ApiException(
          400,
          '"${questionPrefix}answers" must have at least two options.',
        );
      }
      breakoutQuestions.add(
        BreakoutQuestion(
          id: _uuid.v4(),
          title: questionText,
          answerOptionId: '',
          answers: [
            for (final answer in answers)
              BreakoutAnswer(
                id: _uuid.v4(),
                options: [
                  BreakoutAnswerOption(id: _uuid.v4(), title: answer),
                ],
              ),
          ],
        ),
      );
    }

    return BreakoutRoomDefinition(
      creatorId: ownerUserId,
      targetParticipants: targetParticipants,
      assignmentMethod: method,
      breakoutQuestions: breakoutQuestions,
    );
  }

  PrePostCard? _parsePrePostCard(
    Map<String, dynamic> json,
    String key,
    PrePostCardType type,
  ) {
    final raw = _optMap(json, key);
    if (raw == null) return null;
    final prefix = '$key.';

    final surveyQuestionsRaw =
        _optListOfMaps(raw, 'surveyQuestions', prefix) ?? [];
    final surveyQuestions = <PrePostSurveyQuestion>[];
    for (var i = 0; i < surveyQuestionsRaw.length; i++) {
      surveyQuestions.add(
        _parseSurveyQuestion(
          surveyQuestionsRaw[i],
          '${prefix}surveyQuestions[$i].',
        ),
      );
    }

    final actionLinksRaw = _optListOfMaps(raw, 'actionLinks', prefix) ?? [];
    final prePostUrls = <PrePostUrlParams>[];
    for (var i = 0; i < actionLinksRaw.length; i++) {
      prePostUrls.add(
        _parseActionLink(actionLinksRaw[i], '${prefix}actionLinks[$i].'),
      );
    }

    return PrePostCard(
      headline: _optString(raw, 'headline', prefix) ?? '',
      message: _optString(raw, 'message', prefix) ?? '',
      type: type,
      surveyQuestions: surveyQuestions,
      prePostUrls: prePostUrls,
    );
  }

  PrePostSurveyQuestion _parseSurveyQuestion(
    Map<String, dynamic> questionJson,
    String prefix,
  ) {
    final typeName = _optString(questionJson, 'type', prefix) ?? '';
    final type = PrePostSurveyQuestionType.values
        .where((value) => value.name == typeName)
        .cast<PrePostSurveyQuestionType?>()
        .firstWhere((_) => true, orElse: () => null);
    if (type == null) {
      throw _ApiException(
        400,
        '"${prefix}type" is required and must be one of: '
        '${PrePostSurveyQuestionType.values.map((value) => value.name).join(', ')} '
        '(residence is the fixed "Where do you live?" question).',
      );
    }

    switch (type) {
      case PrePostSurveyQuestionType.multipleChoice:
        final question =
            _valueOrNull(_optString(questionJson, 'question', prefix)) ??
                _optString(questionJson, 'title', prefix) ??
                '';
        if (question.isEmpty) {
          throw _ApiException(400, '"${prefix}question" is required.');
        }
        final options =
            _optListOfStrings(questionJson, 'options', prefix) ?? [];
        options.removeWhere((option) => option.isEmpty);
        if (options.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}options" must have at least one option.',
          );
        }
        if (options.length > PrePostSurveyQuestion.maxMultipleChoiceOptions) {
          throw _ApiException(
            400,
            '"${prefix}options" allows at most '
            '${PrePostSurveyQuestion.maxMultipleChoiceOptions} options.',
          );
        }
        return PrePostSurveyQuestion(
          id: _uuid.v4(),
          type: type,
          title: question,
          options: [
            for (final option in options)
              PrePostSurveyItem(id: _uuid.v4(), text: option),
          ],
        );
      case PrePostSurveyQuestionType.agreeDisagree:
        final statements =
            _optListOfStrings(questionJson, 'statements', prefix) ?? [];
        statements.removeWhere((statement) => statement.isEmpty);
        if (statements.isEmpty) {
          throw _ApiException(
            400,
            '"${prefix}statements" must have at least one statement.',
          );
        }
        if (statements.length >
            PrePostSurveyQuestion.maxAgreeDisagreeStatements) {
          throw _ApiException(
            400,
            '"${prefix}statements" allows at most '
            '${PrePostSurveyQuestion.maxAgreeDisagreeStatements} statements.',
          );
        }
        return PrePostSurveyQuestion(
          id: _uuid.v4(),
          type: type,
          statements: [
            for (final statement in statements)
              PrePostSurveyItem(id: _uuid.v4(), text: statement),
          ],
        );
      case PrePostSurveyQuestionType.residence:
        // Question text and answer options are fixed in code.
        return PrePostSurveyQuestion(id: _uuid.v4(), type: type);
    }
  }

  PrePostUrlParams _parseActionLink(
    Map<String, dynamic> linkJson,
    String prefix,
  ) {
    final url = _optString(linkJson, 'url', prefix) ?? '';
    if (url.isEmpty) {
      throw _ApiException(400, '"${prefix}url" is required.');
    }

    final paramsRaw = _optListOfMaps(linkJson, 'urlParams', prefix) ?? [];
    final attributes = <PrePostCardAttribute>[];
    for (var i = 0; i < paramsRaw.length; i++) {
      final paramPrefix = '${prefix}urlParams[$i].';
      final paramJson = paramsRaw[i];
      final name = _optString(paramJson, 'name', paramPrefix) ?? '';
      if (name.isEmpty) {
        throw _ApiException(400, '"${paramPrefix}name" is required.');
      }
      attributes.add(
        PrePostCardAttribute(
          type: _attributeTypeFromValue(
            _optString(paramJson, 'value', paramPrefix) ?? '',
            '${paramPrefix}value',
          ),
          queryParam: name,
        ),
      );
    }

    return PrePostUrlParams(
      buttonText: _optString(linkJson, 'buttonText', prefix),
      surveyUrl: url,
      attributes: attributes,
    );
  }

  /// Accepts the UI labels (ParticipantID / Email / EventID) or the enum
  /// names (userId / email / eventId), case-insensitively.
  PrePostCardAttributeType _attributeTypeFromValue(String value, String label) {
    switch (value.toLowerCase()) {
      case 'participantid':
      case 'userid':
        return PrePostCardAttributeType.userId;
      case 'email':
        return PrePostCardAttributeType.email;
      case 'eventid':
        return PrePostCardAttributeType.eventId;
      default:
        throw _ApiException(
          400,
          '"$label" must be one of: ParticipantID, Email, EventID.',
        );
    }
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
