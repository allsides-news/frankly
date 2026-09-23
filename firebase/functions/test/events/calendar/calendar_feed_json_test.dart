import 'dart:convert';
import 'dart:io';

import 'package:data_models/events/event.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'package:functions/events/calendar/calendar_feed_json.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

import '../../util/community_test_utils.dart';
import '../../util/event_test_utils.dart';
import '../../util/function_test_fixture.dart';

void main() {
  late String communityId;
  const templateId = '9654988';
  final communityTestUtils = CommunityTestUtils();
  final eventTestUtils = EventTestUtils();
  setupTestFixture();

  setUp(() async {
    communityId = await communityTestUtils.createTestCommunity();
  });

  test('JSON calendar feed generated', () async {
    const eventId = '123411000ff2837';
    var event = Event(
      id: eventId,
      status: EventStatus.active,
      communityId: communityId,
      templateId: templateId,
      creatorId: adminUserId,
      nullableEventType: EventType.hosted,
      collectionPath: '',
      title: 'My Test Event',
      isPublic: true,
      scheduledTime: DateTime.now().add(const Duration(hours: 24)),
      agendaItems: [
        AgendaItem(
          id: '55005',
          title: "Role call",
          content: "Shout out if you're here",
        ),
      ],
    );
    event = await eventTestUtils.createEvent(
      event: event,
      userId: adminUserId,
    );

    registerFallbackValue(event);
    final mockRequest = MockExpressHttpRequest();
    final mockResponse = MockHttpResponse();
    final mockHeaders = MockHttpHeaders();

    when(() => mockRequest.response).thenReturn(mockResponse);
    when(() => mockRequest.requestedUri).thenReturn(
      Uri(
        scheme: 'https',
        host: 'myapp.org',
        path: 'space/$communityId/upcoming-events.json',
      ),
    );
    when(() => mockResponse.headers).thenReturn(mockHeaders);

    String? writtenData;
    when(() => mockResponse.write(any())).thenAnswer((invocation) {
      writtenData = invocation.positionalArguments.first as String;
    });

    when(() => mockResponse.close()).thenAnswer((_) async {});

    final calFeed = CalendarFeedJson();

    await calFeed.expressAction(mockRequest);

    verify(
      () => mockHeaders.set('Access-Control-Allow-Origin', '*'),
    ).called(1);

    expect(writtenData, isNotNull);

    final decoded = jsonDecode(writtenData!) as Map<String, dynamic>;
    final events = decoded['events'] as List<dynamic>;

    expect(events.length, 1);

    final firstEvent = events.first as Map<String, dynamic>;

    expect(firstEvent['spaceName'], 'Testing Community');
    expect(firstEvent['communityName'], 'Testing Community');
    expect(firstEvent['title'], 'My Test Event');
    expect(firstEvent['dateTime'], isNotEmpty);
    expect(
      firstEvent['registrationUrl'],
      contains('/space/$communityId/discuss/$templateId/$eventId'),
    );
  });
}

class MockExpressHttpRequest extends Mock implements ExpressHttpRequest {}

class MockHttpResponse extends Mock implements HttpResponse {}

class MockHttpHeaders extends Mock implements HttpHeaders {}
