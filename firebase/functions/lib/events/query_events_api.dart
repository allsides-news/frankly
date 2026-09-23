import 'dart:async';
import 'dart:convert';

import 'package:firebase_admin_interop/firebase_admin_interop.dart'
    hide EventType;
import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    hide CloudFunction;
import '../cloud_function.dart';
import '../utils/calendar_link_util.dart';
import '../utils/infra/firebase_auth_utils.dart';
import '../utils/infra/firestore_utils.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/templates/template.dart';

/// Error with an HTTP status code so validation failures return proper
/// 4xx responses instead of a generic 500.
class _ApiException implements Exception {
  final int statusCode;
  final String message;

  _ApiException(this.statusCode, this.message);
}

/// HTTP endpoint (POST + JSON) for querying Events from outside the app,
/// e.g. to build event landing pages on 3rd-party websites.
///
/// One endpoint serves both query types (they share the same response shape):
///
/// - `userId`: every event the user is registered for (an active RSVP
///   participant doc — same collection-group query as the app's "my events")
///   OR is hosting (event `creatorId`). Each result is tagged with
///   `userRelationship` so callers can tell the two apart.
/// - `title`: case-insensitive substring match against event titles across
///   all Spaces. Firestore has no substring queries, so this scans the
///   `events` collection group (~1k docs today) and filters in memory —
///   fine at current scale, but 3rd-party callers should cache responses
///   rather than query per page view.
///
/// At least one of the two is required; when both are given they AND
/// (the user's events matching the title).
///
/// Results are paged (`limit` default 100, max 500; `offset` default 0),
/// sorted soonest-first with doc path as tie-break, and the response reports
/// `totalMatches` / `hasMore`: a broad title (e.g. "on") can match most
/// events, and serializing full docs + RSVP rosters unbounded could exceed
/// the response-size limit or timeout as the dataset grows. Matching and
/// filtering always consider everything; only hydration is paged. Callers
/// should treat `hasMore` (not `eventCount == limit`) as the end-of-results
/// signal: a page can come back short when a matched event's Space doc is
/// missing.
///
/// Each returned event carries everything the app itself shows: the full
/// event document (agenda, waiting room, breakouts, pre/post cards,
/// settings, timestamps as ISO-8601 UTC), the full hosting Space document
/// (name, tagline, about, logo/banner URLs, public/private, contact email),
/// the event page URL (registration/share/enter-meeting entry point),
/// prebuilt social share links (same construction as the app's ShareSection),
/// add-to-calendar links, and the userIds of everyone with an affirmative
/// RSVP (active participants).
///
/// Auth: requires an `x-api-key` header matching the
/// `app.create_space_api_key` functions config value (shared with
/// createCommunityApi / createEventApi / eventRsvpApi). Fails closed (503)
/// if unset.
///
/// Note: results include private Spaces/events the user belongs to (the key
/// is trusted, server-to-server); check `event.isPublic` / `space.isPublic`
/// before publishing on a public page.
///
/// Example payloads: scripts/query-events-by-user-example.json and
/// scripts/query-events-by-title-example.json
class QueryEventsApi implements CloudFunction {
  @override
  final String functionName = 'queryEventsApi';

  String get _configuredApiKey =>
      functions.config.get('app.create_space_api_key') as String? ?? '';

  String get _domain =>
      functions.config.get('app.domain') as String? ??
      'roundtables.allsides.com';

  String get _appName =>
      functions.config.get('app.name') as String? ?? 'AllSides Roundtables';

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

      final result = await _query(json);
      await _sendJson(expressRequest, 200, result);
    } on _ApiException catch (e) {
      await _sendJson(expressRequest, e.statusCode, {'error': e.message});
    } catch (e, stacktrace) {
      print('Error in $functionName');
      print(e);
      print(stacktrace);
      await _sendJson(
        expressRequest,
        500,
        {'error': 'Internal error querying events: $e'},
      );
    }
  }

  String? _optString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value == null) return null;
    if (value is! String) {
      throw _ApiException(400, 'Field "$key" must be a string.');
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  bool _optBool(Map<String, dynamic> json, String key, {required bool orElse}) {
    final value = json[key];
    if (value == null) return orElse;
    if (value is! bool) {
      throw _ApiException(400, 'Field "$key" must be a boolean.');
    }
    return value;
  }

  int _optInt(
    Map<String, dynamic> json,
    String key, {
    required int orElse,
    required int min,
    int? max,
  }) {
    final value = json[key];
    if (value == null) return orElse;
    if (value is! int) {
      throw _ApiException(400, 'Field "$key" must be an integer.');
    }
    if (value < min || (max != null && value > max)) {
      throw _ApiException(
        400,
        max == null
            ? 'Field "$key" must be at least $min.'
            : 'Field "$key" must be between $min and $max.',
      );
    }
    return value;
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _query(Map<String, dynamic> json) async {
    final userId = _optString(json, 'userId');
    final title = _optString(json, 'title');
    final upcomingOnly = _optBool(json, 'upcomingOnly', orElse: false);
    // Bound the response: a broad title (e.g. "on") can match most events,
    // and each result carries full event + Space docs + RSVP roster. Matching
    // and filtering still consider everything; only hydration/serialization
    // is paged.
    final limit = _optInt(json, 'limit', orElse: 100, min: 1, max: 500);
    final offset = _optInt(json, 'offset', orElse: 0, min: 0);

    if (userId == null && title == null) {
      throw _ApiException(
        400,
        'Provide "userId" (events the user hosts or is registered for), '
        '"title" (case-insensitive title search), or both (AND).',
      );
    }
    if (title != null && title.length < 2) {
      throw _ApiException(
        400,
        '"title" must be at least 2 characters.',
      );
    }

    // Matched events keyed by document path (dedupes owner+registered).
    final matched = <String, _MatchedEvent>{};

    if (userId != null) {
      // Verify the user exists so a typo\'d userId is a clear 400, not an
      // empty result set.
      try {
        await firebaseAuthUtils.getUser(userId);
      } catch (_) {
        throw _ApiException(
          400,
          'No Firebase Auth user found for userId "$userId".',
        );
      }

      // Registered: same collection-group query the app uses for the user\'s
      // events (index on id+status already deployed), then fetch each
      // parent event doc.
      final participantDocs = await firestore
          .collectionGroup('event-participants')
          .where('id', isEqualTo: userId)
          .where(
            Participant.kFieldStatus,
            isEqualTo: ParticipantStatus.active.name,
          )
          .get();
      final eventPaths = participantDocs.documents
          .map((doc) {
            // .../events/{eventId}/event-participants/{userId} -> event path
            final segments = doc.reference.path.split('/');
            return segments.length >= 2
                ? segments.sublist(0, segments.length - 2).join('/')
                : null;
          })
          .whereType<String>()
          .toSet();
      final registeredDocs = await _chunkedFutures(
        eventPaths.map((path) => () => firestore.document(path).get()),
      );
      for (final doc in registeredDocs) {
        if (!doc.exists) continue;
        matched
            .putIfAbsent(doc.reference.path, () => _MatchedEvent(doc))
            .isRegistered = true;
      }

      // Hosting: events the user created. Uses the creatorId collection-group
      // index (firestore.indexes.json fieldOverrides). No kFieldCreatorId
      // constant exists on Event.
      final hostedDocs = await firestore
          .collectionGroup('events')
          .where('creatorId', isEqualTo: userId)
          .get();
      for (final doc in hostedDocs.documents) {
        matched
            .putIfAbsent(doc.reference.path, () => _MatchedEvent(doc))
            .isOwner = true;
      }
    }

    if (title != null) {
      final needle = title.toLowerCase();
      if (userId != null) {
        // AND semantics: narrow the user\'s events by title.
        matched.removeWhere((_, m) {
          final t = m.doc.data.toMap()[Event.kFieldTitle];
          return t is! String || !t.toLowerCase().contains(needle);
        });
      } else {
        // Full collection-group scan; Firestore cannot substring-match.
        final allEvents = await firestore.collectionGroup('events').get();
        for (final doc in allEvents.documents) {
          final t = doc.data.toMap()[Event.kFieldTitle];
          if (t is String && t.toLowerCase().contains(needle)) {
            matched.putIfAbsent(doc.reference.path, () => _MatchedEvent(doc));
          }
        }
      }
    }

    // Parse events; skip docs that don\'t fit the model (legacy/corrupt).
    final parsed = <_MatchedEvent>[];
    for (final m in matched.values) {
      try {
        m.event = Event.fromJson(
          firestoreUtils.fromFirestoreJson(
            m.doc.data.toMap()..['id'] = m.doc.documentID,
          ),
        );
        parsed.add(m);
      } catch (e) {
        print('Skipping unparseable event ${m.doc.reference.path}: $e');
      }
    }

    final now = DateTime.now();
    final results = upcomingOnly
        ? parsed
            .where(
              (m) =>
                  m.event!.status == EventStatus.active &&
                  !m.event!.isEnded &&
                  !m.event!.hasEnded(now),
            )
            .toList()
        : parsed;

    // Soonest first; events without a scheduled time last; doc path as
    // tie-break so pagination is stable across requests.
    results.sort((a, b) {
      final at = a.event!.scheduledTime;
      final bt = b.event!.scheduledTime;
      if (at == null && bt == null) {
        return a.doc.reference.path.compareTo(b.doc.reference.path);
      }
      if (at == null) return 1;
      if (bt == null) return -1;
      final byTime = at.compareTo(bt);
      if (byTime != 0) return byTime;
      return a.doc.reference.path.compareTo(b.doc.reference.path);
    });

    final totalMatches = results.length;
    final pageEnd =
        (offset + limit) > totalMatches ? totalMatches : offset + limit;
    final page = offset >= totalMatches
        ? <_MatchedEvent>[]
        : results.sublist(offset, pageEnd);

    // Hydrate the hosting Spaces (one read per distinct Space), for the
    // returned page only.
    final communityIds = page
        .map((m) => m.event!.communityId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final communities = <String, Community>{};
    final communityDocs = <String, Map<String, dynamic>>{};
    final communitySnapshots = await _chunkedFutures(
      communityIds.map((id) => () => firestore.document('community/$id').get()),
    );
    for (final doc in communitySnapshots) {
      if (!doc.exists) continue;
      final data = doc.data.toMap()..['id'] = doc.documentID;
      try {
        communities[doc.documentID] = Community.fromJson(
          firestoreUtils.fromFirestoreJson(Map<String, dynamic>.from(data)),
        );
        communityDocs[doc.documentID] = data;
      } catch (e) {
        print('Skipping unparseable community ${doc.documentID}: $e');
      }
    }

    // Affirmative RSVPs (active participants) for every event in the page.
    final rsvpLists = await _chunkedFutures(
      page.map(
        (m) => () async {
          final snapshot = await firestore
              .collection('${m.doc.reference.path}/event-participants')
              .where(
                Participant.kFieldStatus,
                isEqualTo: ParticipantStatus.active.name,
              )
              .get();
          return snapshot.documents.map((d) => d.documentID).toList();
        },
      ),
    );

    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < page.length; i++) {
      final m = page[i];
      final community = communities[m.event!.communityId];
      if (community == null) {
        // Space doc missing/unparseable: the event can\'t be rendered the way
        // the app would render it, so skip rather than return half an item.
        print(
          'Skipping event ${m.doc.reference.path}: Space '
          '${m.event!.communityId} not found.',
        );
        continue;
      }
      items.add(
        _buildEventItem(
          m: m,
          community: community,
          communityDoc: communityDocs[m.event!.communityId]!,
          rsvpUserIds: rsvpLists[i],
          includeRelationship: userId != null,
        ),
      );
    }

    return {
      'query': {
        if (userId != null) 'userId': userId,
        if (title != null) 'title': title,
        'upcomingOnly': upcomingOnly,
        'limit': limit,
        'offset': offset,
      },
      'totalMatches': totalMatches,
      // eventCount can be below limit even when hasMore is true (an event
      // whose Space doc is missing/unparseable is dropped from the page
      // above), so hasMore - not eventCount == limit - is the end-of-results
      // signal; offsets are positions in the match list, not in the output.
      'eventCount': items.length,
      'hasMore': pageEnd < totalMatches,
      'events': items,
    };
  }

  // ---------------------------------------------------------------------------
  // Response building
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _buildEventItem({
    required _MatchedEvent m,
    required Community community,
    required Map<String, dynamic> communityDoc,
    required List<String> rsvpUserIds,
    required bool includeRelationship,
  }) {
    final event = m.event!;
    final displayId = community.displayId;
    final eventUrl =
        'https://$_domain/space/$displayId/discuss/${event.templateId}/${event.id}';
    final spaceUrl = 'https://$_domain/space/$displayId';

    // Same message construction as the app\'s event page ShareSection.
    final shareBody = (event.title != null && community.name != null)
        ? 'Join me in a conversation about "${event.title}" on '
            '${community.name}!'
        : 'Join an event with me on $_appName!';
    final shareSubject = 'Join my event on $_appName!';

    // In-app events are entered from the event page; external-platform
    // events (Zoom / Meet / Teams) carry their own meeting URL.
    final externalUrl = event.externalPlatform?.url;
    final enterMeetingUrl = (externalUrl != null && externalUrl.isNotEmpty)
        ? externalUrl
        : eventUrl;

    // Calendar links only need title/time/duration; template title is just a
    // fallback when the event has none, so a synthetic Template avoids a
    // Firestore read (misc events have no template doc anyway).
    final template = Template(
      id: event.templateId,
      title: event.title ?? 'Event',
    );
    Map<String, dynamic> calendarLinks;
    try {
      calendarLinks = {
        'google': calendarLinkUtil.getGoogleLink(
          community: community,
          template: template,
          event: event,
        ),
        'office365': calendarLinkUtil.getOffice365Link(
          community: community,
          template: template,
          event: event,
        ),
        'outlook': calendarLinkUtil.getOutlookLink(
          community: community,
          template: template,
          event: event,
        ),
      };
    } catch (e) {
      // Calendar-link JS lib failure shouldn\'t sink the whole query.
      print('Calendar links failed for ${event.fullPath}: $e');
      calendarLinks = {};
    }

    final now = DateTime.now();
    return {
      'eventId': event.id,
      'communityId': event.communityId,
      'templateId': event.templateId,
      'eventPath': event.fullPath,
      'eventUrl': eventUrl,
      'enterMeetingUrl': enterMeetingUrl,
      'shareLinks': {
        'facebook': 'http://www.facebook.com/share.php?'
            '${Uri(queryParameters: {'u': eventUrl}).query}',
        'twitter': 'https://twitter.com/intent/tweet?'
            '${Uri(
          queryParameters: {
            'url': eventUrl,
            'text': shareBody,
          },
        ).query}',
        'linkedin': 'https://www.linkedin.com/sharing/share-offsite/?'
            '${Uri(queryParameters: {'url': eventUrl}).query}',
        'email': Uri(
          scheme: 'mailto',
          queryParameters: {
            'subject': shareSubject,
            'body': '$shareBody $eventUrl',
          },
        ).toString().replaceAll('+', '%20'),
      },
      'calendarLinks': calendarLinks,
      if (includeRelationship)
        'userRelationship': {
          'isOwner': m.isOwner,
          'isRegistered': m.isRegistered,
        },
      'status': event.status.name,
      'hasEnded': event.isEnded || event.hasEnded(now),
      'scheduledTimeUtc': event.scheduledTime?.toUtc().toIso8601String(),
      'scheduledEndTimeUtc': event.scheduledEndTime?.toUtc().toIso8601String(),
      'rsvps': {
        'count': rsvpUserIds.length,
        'userIds': rsvpUserIds,
      },
      // Full raw documents, exactly as the app reads them (timestamps as
      // ISO-8601 UTC strings).
      'event': _jsonSafe(m.doc.data.toMap()..['id'] = m.doc.documentID),
      'space': {
        ..._jsonSafe(communityDoc),
        'spaceUrl': spaceUrl,
      },
    };
  }

  /// Recursively converts Firestore values (Timestamps) into JSON-encodable
  /// ones (ISO-8601 UTC strings).
  Map<String, dynamic> _jsonSafe(Map<dynamic, dynamic> json) {
    dynamic convert(dynamic value) {
      if (value is Timestamp) {
        return value.toDateTime().toUtc().toIso8601String();
      }
      if (value is DateTime) return value.toUtc().toIso8601String();
      if (value is Map) {
        return {
          for (final entry in value.entries)
            entry.key.toString(): convert(entry.value),
        };
      }
      if (value is List) return value.map(convert).toList();
      return value;
    }

    return convert(Map<String, dynamic>.from(json)) as Map<String, dynamic>;
  }

  /// Runs async operations in chunks of 25 to avoid flooding the Firestore
  /// client with hundreds of parallel requests.
  Future<List<T>> _chunkedFutures<T>(
    Iterable<Future<T> Function()> operations,
  ) async {
    final all = operations.toList();
    final output = <T>[];
    for (var i = 0; i < all.length; i += 25) {
      final chunk = all.sublist(
        i,
        i + 25 > all.length ? all.length : i + 25,
      );
      output.addAll(
        await Future.wait(chunk.map((operation) => operation())),
      );
    }
    return output;
  }

  @override
  void register(FirebaseFunctions functions) {
    functions[functionName] = functions
        .runWith(
          RuntimeOptions(timeoutSeconds: 120, memory: '1GB', minInstances: 0),
        )
        .https
        .onRequest(expressAction);
  }
}

class _MatchedEvent {
  final DocumentSnapshot doc;
  bool isOwner = false;
  bool isRegistered = false;
  Event? event;

  _MatchedEvent(this.doc);
}
