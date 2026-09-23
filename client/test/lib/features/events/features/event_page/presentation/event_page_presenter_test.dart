import 'package:client/core/utils/toast_utils.dart';
import 'package:client/features/events/features/event_page/data/providers/template_provider.dart';
import 'package:client/features/events/features/event_page/presentation/event_page_presenter.dart';
import 'package:client/features/events/features/event_page/presentation/views/event_page_contract.dart';
import 'package:data_models/events/event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import '../../../../../../mocked_classes.mocks.dart';

class _FakeEventPageView implements EventPageView {
  int updateCount = 0;

  @override
  void updateView() => updateCount++;

  @override
  void showMessage(String message, {ToastType toastType = ToastType.neutral}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockContext = MockBuildContext();
  final mockCloudFunctionsEventService = MockCloudFunctionsEventService();
  final mockCloudFunctionsLiveMeetingService =
      MockCloudFunctionsLiveMeetingService();
  final mockCommunityProvider = MockCommunityProvider();
  final mockEventProvider = MockEventProvider();
  final mockUserService = MockUserService();
  final mockSharedPreferencesService = MockSharedPreferencesService();
  final mockClockService = MockClockService();
  final mockFirestoreEventService = MockFirestoreEventService();
  final mockCommunityPermissionsProvider = MockCommunityPermissionsProvider();

  late _FakeEventPageView view;
  late EventPagePresenter presenter;

  Event sampleEvent() => Event(
        id: 'event-id',
        collectionPath: 'community/c/templates/t/events',
        creatorId: 'creator',
        communityId: 'community-id',
        templateId: 'misc',
        status: EventStatus.active,
      );

  setUp(() {
    view = _FakeEventPageView();
    presenter = EventPagePresenter(
      mockContext,
      view,
      testCloudFunctionsService: mockCloudFunctionsEventService,
      testCloudFunctionsLiveMeetingService:
          mockCloudFunctionsLiveMeetingService,
      communityProvider: mockCommunityProvider,
      templateProvider: TemplateProvider(
        communityId: 'community-id',
        templateId: 'template-id',
      ),
      eventProvider: mockEventProvider,
      userService: mockUserService,
      sharedPreferencesService: mockSharedPreferencesService,
      clockService: mockClockService,
      firestoreEventService: mockFirestoreEventService,
      communityPermissionsProvider: mockCommunityPermissionsProvider,
    );
  });

  test('init does not throw when the event stream completes empty', () async {
    when(mockEventProvider.eventStream)
        .thenAnswer((_) => Stream<Event>.empty());

    await presenter.init();

    expect(view.updateCount, 0);
  });

  test('init updates the view after the first event snapshot', () async {
    when(mockEventProvider.eventStream)
        .thenAnswer((_) => Stream.value(sampleEvent()));
    when(mockCommunityPermissionsProvider.canModerateContent).thenReturn(false);

    await presenter.init();

    expect(view.updateCount, 1);
  });

  test('getCombinedTemplateFromEvent is null until event and template load',
      () {
    when(mockEventProvider.eventOrNull).thenReturn(null);

    expect(presenter.getCombinedTemplateFromEvent(), isNull);

    when(mockEventProvider.eventOrNull).thenReturn(sampleEvent());

    expect(presenter.getCombinedTemplateFromEvent(), isNull);
  });
}
