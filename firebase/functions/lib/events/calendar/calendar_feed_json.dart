import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:enum_to_string/enum_to_string.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import '../../utils/infra/firestore_utils.dart';
import 'abstract_calendar_feed.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/events/event.dart';

/// Generate and return a JSON feed of upcoming events for a given space.
/// This function expects the space id to be present as the second request path
/// parameter, as in '/space/[space_id]/upcoming-events.json'.
class CalendarFeedJson extends AbstractCalendarFeed {
  @override
  final String functionName = 'CalendarFeedJson';

  @override
  Future<String> generateData({required Community community}) async {
    final events = (await firestore
            .collectionGroup('events')
            .where(Event.kFieldCommunityId, isEqualTo: community.id)
            .where(Event.kFieldIsPublic, isEqualTo: true)
            .where(
              Event.kFieldStatus,
              isEqualTo: EnumToString.convertToString(EventStatus.active),
            )
            .where(
              Event.kFieldScheduledTime,
              isGreaterThanOrEqualTo: DateTime.now(),
            )
            .orderBy(Event.kFieldScheduledTime)
            .get())
        .documents
        .map(
          (doc) => Event.fromJson(
            firestoreUtils.fromFirestoreJson(doc.data.toMap()),
          ),
        )
        .where((event) => event.scheduledTime != null)
        .toList();

    final domain = functions.config.get('app.domain') as String? ??
        'roundtables.allsides.com';

    final communityLogo =
        community.profileImageUrl ?? community.bannerImageUrl ?? '';

    final eventJson = events.map((event) {
      return {
        'spaceName': community.name ?? '',
        'spaceLogo': communityLogo,
        'communityName': community.name ?? '',
        'communityLogo': communityLogo,
        'title': event.title ?? 'Event',
        'dateTime': event.scheduledTime!.toIso8601String(),
        'registrationUrl':
            'https://$domain/space/${community.displayId}/discuss/${event.templateId}/${event.id}',
      };
    }).toList();

    return jsonEncode({
      'events': eventJson,
    });
  }

  @override
  void setResponseHeaders(HttpHeaders headers) {
    headers.set('Access-Control-Allow-Origin', '*');
  }

  @override
  ContentType getContentType() {
    return ContentType('application', 'json', charset: 'utf-8');
  }
}
