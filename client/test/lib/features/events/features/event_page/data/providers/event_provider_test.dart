import 'dart:async';

import 'package:client/core/data/services/firestore_database.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/features/events/data/services/firestore_event_service.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/templates/template.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/mockito.dart';
import 'package:rxdart/rxdart.dart';

import '../../../../../../../mocked_classes.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCommunityProvider mockCommunityProvider;
  late MockFirestoreEventService mockEventService;
  late MockFirestoreDatabase mockDatabase;
  late MockUserService mockUserService;
  late StreamController<Event> firstEventStream;
  late StreamController<Event> restartedEventStream;
  late StreamController<String> userChanges;
  late int eventStreamCalls;

  Event sampleEvent() => Event(
        id: 'event-id',
        collectionPath: 'community/c/templates/t/events',
        creatorId: 'creator',
        communityId: 'community-id',
        templateId: 'template-id',
        status: EventStatus.active,
      );

  setUp(() {
    mockCommunityProvider = MockCommunityProvider();
    mockEventService = MockFirestoreEventService();
    mockDatabase = MockFirestoreDatabase();
    mockUserService = MockUserService();
    firstEventStream = StreamController<Event>.broadcast();
    restartedEventStream = StreamController<Event>.broadcast();
    userChanges = StreamController<String>.broadcast();
    eventStreamCalls = 0;

    when(mockCommunityProvider.communityId).thenReturn('community-id');
    when(mockUserService.currentUserId).thenReturn('user-1');
    when(mockUserService.currentUserChanges)
        .thenAnswer((_) => userChanges.stream);

    when(
      mockEventService.futurePublicEventsForCommunity(
        communityId: anyNamed('communityId'),
      ),
    ).thenAnswer((_) => wrapInBehaviorSubject(Stream.value(<Event>[])));

    when(
      mockEventService.eventStream(
        communityId: anyNamed('communityId'),
        templateId: anyNamed('templateId'),
        eventId: anyNamed('eventId'),
      ),
    ).thenAnswer((_) {
      eventStreamCalls++;
      return wrapInBehaviorSubject(
        eventStreamCalls == 1
            ? firstEventStream.stream
            : restartedEventStream.stream,
      );
    });

    when(
      mockEventService.eventParticipantStream(
        communityId: anyNamed('communityId'),
        templateId: anyNamed('templateId'),
        eventId: anyNamed('eventId'),
        userId: anyNamed('userId'),
      ),
    ).thenAnswer((_) => const Stream<Participant>.empty());

    when(
      mockEventService.eventParticipantsStream(
        communityId: anyNamed('communityId'),
        templateId: anyNamed('templateId'),
        eventId: anyNamed('eventId'),
      ),
    ).thenAnswer(
      (_) => wrapInBehaviorSubject(Stream.value(<Participant>[])),
    );

    when(mockDatabase.communityTemplatesStream(any))
        .thenAnswer((_) => Stream.value(<Template>[]));
    when(
      mockDatabase.templateStream(
        communityId: anyNamed('communityId'),
        templateId: anyNamed('templateId'),
      ),
    ).thenAnswer((_) => Stream<Template?>.value(null));

    GetIt.instance.registerSingleton<FirestoreEventService>(mockEventService);
    GetIt.instance.registerSingleton<FirestoreDatabase>(mockDatabase);
    GetIt.instance.registerSingleton<UserService>(mockUserService);
  });

  tearDown(() async {
    await firstEventStream.close();
    await restartedEventStream.close();
    await userChanges.close();
    await GetIt.instance.reset();
  });

  test('dispose before initialize does not throw', () {
    final provider = EventProvider(
      communityProvider: mockCommunityProvider,
      templateId: 'template-id',
      eventId: 'event-id',
    );

    expect(provider.dispose, returnsNormally);
  });

  test('event getter throws before the first snapshot', () {
    final provider = EventProvider(
      communityProvider: mockCommunityProvider,
      templateId: 'template-id',
      eventId: 'event-id',
    )..initialize();

    expect(provider.eventOrNull, isNull);
    expect(
      () => provider.event,
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Event must be loaded before being accessed.'),
        ),
      ),
    );

    provider.dispose();
  });

  test('initialize does not notify on the currentUserChanges replay', () {
    final users = BehaviorSubject<String>.seeded('user-1');
    addTearDown(users.close);
    when(mockUserService.currentUserChanges).thenAnswer((_) => users);

    var notifications = 0;
    final provider = EventProvider(
      communityProvider: mockCommunityProvider,
      templateId: 'template-id',
      eventId: 'event-id',
    )..addListener(() => notifications++);
    addTearDown(provider.dispose);

    provider.initialize();

    expect(notifications, 0);
  });

  test('event stays available after auth restarts the Firestore listener',
      () async {
    final provider = EventProvider(
      communityProvider: mockCommunityProvider,
      templateId: 'template-id',
      eventId: 'event-id',
    )..initialize();
    addTearDown(provider.dispose);

    firstEventStream.add(sampleEvent());
    await Future<void>.delayed(Duration.zero);

    expect(provider.event.id, 'event-id');
    expect(eventStreamCalls, 1);

    when(mockUserService.currentUserId).thenReturn('user-2');
    userChanges.add('user-2');
    await Future<void>.delayed(Duration.zero);

    expect(eventStreamCalls, 2);
    expect(provider.eventOrNull?.id, 'event-id');
    expect(provider.event.id, 'event-id');
  });
}
