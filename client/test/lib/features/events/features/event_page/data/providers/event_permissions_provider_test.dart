import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/events/event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../../../../../mocked_classes.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockEventProvider mockEventProvider;
  late MockCommunityProvider mockCommunityProvider;
  late MockCommunityPermissionsProvider mockCommunityPermissions;
  late EventPermissionsProvider permissions;

  setUp(() {
    mockEventProvider = MockEventProvider();
    mockCommunityProvider = MockCommunityProvider();
    mockCommunityPermissions = MockCommunityPermissionsProvider();
    permissions = EventPermissionsProvider(
      eventProvider: mockEventProvider,
      communityProvider: mockCommunityProvider,
      communityPermissions: mockCommunityPermissions,
    );
  });

  test('permission getters do not throw when the event is not loaded', () {
    when(mockEventProvider.eventOrNull).thenReturn(null);
    when(mockCommunityProvider.settings).thenReturn(const CommunitySettings());

    expect(permissions.avCheckEnabled, isFalse);
    expect(permissions.canJoinEvent, isFalse);
  });

  test('avCheckEnabled is true for a loaded hosted event', () {
    when(mockEventProvider.eventOrNull).thenReturn(
      Event(
        id: 'event-id',
        collectionPath: 'community/c/templates/t/events',
        creatorId: 'creator',
        communityId: 'community-id',
        templateId: 'template-id',
        status: EventStatus.active,
        nullableEventType: EventType.hosted,
      ),
    );
    when(mockCommunityProvider.settings)
        .thenReturn(const CommunitySettings(enableAVCheck: true));

    expect(permissions.avCheckEnabled, isTrue);
  });
}
