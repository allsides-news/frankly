import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:client/features/events/data/services/firestore_event_service.dart';
import 'package:client/features/events/features/event_page/data/models/pre_post_event_dialog_model.dart';
import 'package:client/features/events/features/event_page/presentation/pre_post_event_dialog_presenter.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/events/pre_post_survey.dart';
import 'package:data_models/events/pre_post_url_params.dart';
import 'package:mockito/mockito.dart';

import '../../../../../../mocked_classes.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final MockBuildContext mockBuildContext = MockBuildContext();
  final MockPrePostEventDialogView mockView = MockPrePostEventDialogView();
  final MockPrePostEventDialogModel mockModel = MockPrePostEventDialogModel();
  final MockPrePostEventDialogPresenterHelper mockHelper =
      MockPrePostEventDialogPresenterHelper();
  final MockResponsiveLayoutService mockResponsiveLayoutService =
      MockResponsiveLayoutService();
  final MockUserAdminDetailsProvider mockUserAdminDetailsProvider =
      MockUserAdminDetailsProvider();
  final MockUserService mockUserService = MockUserService();

  late PrePostEventDialogPresenter presenter;

  setUp(() {
    presenter = PrePostEventDialogPresenter(
      mockView,
      mockModel,
      helper: mockHelper,
      testResponsiveLayoutService: mockResponsiveLayoutService,
      userAdminDetailsProvider: mockUserAdminDetailsProvider,
    );

    when(mockModel.event).thenReturn(
      Event(
        id: 'test-event-id',
        collectionPath: 'eventCollectionPath',
        creatorId: 'userId',
        communityId: 'communityId',
        templateId: 'templateId',
        status: EventStatus.active,
      ),
    );

    GetIt.instance.registerSingleton<UserService>(mockUserService);
    when(mockUserService.currentUserId).thenReturn('userId');
    when(mockUserAdminDetailsProvider.getInfoFuture()).thenAnswer(
      (_) => Future.value(UserAdminDetails(email: 'user@email.com')),
    );
  });

  tearDown(() {
    GetIt.instance.reset();

    reset(mockBuildContext);
    reset(mockView);
    reset(mockModel);
    reset(mockHelper);
    reset(mockResponsiveLayoutService);
    reset(mockUserAdminDetailsProvider);
    reset(mockUserService);
  });

  group('isMobile', () {
    test('true', () {
      when(mockResponsiveLayoutService.isMobile(mockBuildContext))
          .thenReturn(true);

      final result = presenter.isMobile(mockBuildContext);

      expect(result, isTrue);
    });

    test('false', () {
      when(mockResponsiveLayoutService.isMobile(mockBuildContext))
          .thenReturn(false);

      final result = presenter.isMobile(mockBuildContext);

      expect(result, isFalse);
    });
  });

  group('getSize', () {
    test('without scale param', () {
      when(mockResponsiveLayoutService.getDynamicSize(mockBuildContext, 100))
          .thenReturn(10);

      final result = presenter.getSize(mockBuildContext, 100);

      expect(result, 10);
    });

    test('without scale param', () {
      when(
        mockResponsiveLayoutService.getDynamicSize(
          mockBuildContext,
          100,
          scale: 10,
        ),
      ).thenReturn(200);

      final result = presenter.getSize(mockBuildContext, 100, scale: 10);

      expect(result, 200);
    });
  });

  group('launchSurvey', () {
    test('surveyUrl is null', () async {
      final prePostUrls = [PrePostUrlParams(attributes: [])];
      final prePostCard = PrePostCard.newCard(PrePostCardType.preEvent)
          .copyWith(prePostUrls: prePostUrls);
      when(mockModel.prePostCard).thenReturn(prePostCard);

      await presenter.launchSurvey(prePostUrls[0]);

      verifyNever(mockHelper.launchUrl(any, any));
    });

    test('surveyUrl is not null', () async {
      final prePostUrls = [
        PrePostUrlParams(surveyUrl: 'surveyUrl', attributes: []),
      ];
      final prePostCard = PrePostCard.newCard(PrePostCardType.preEvent)
          .copyWith(prePostUrls: prePostUrls);
      when(mockModel.prePostCard).thenReturn(prePostCard);

      await presenter.launchSurvey(prePostUrls[0]);

      verify(mockHelper.launchUrl('surveyUrl', any)).called(1);
    });
  });

  group('submitSurvey', () {
    final MockFirestoreEventService mockFirestoreEventService =
        MockFirestoreEventService();

    final surveyQuestion = PrePostSurveyQuestion(
      id: 'q1',
      type: PrePostSurveyQuestionType.multipleChoice,
      title: 'Question?',
      options: [PrePostSurveyItem(id: 'o1', text: 'Answer')],
    );

    late PrePostEventDialogModel model;
    late PrePostEventDialogPresenter presenterWithRealModel;

    setUp(() {
      GetIt.instance.registerSingleton<FirestoreEventService>(
        mockFirestoreEventService,
      );

      model = PrePostEventDialogModel(
        PrePostCard.newCard(PrePostCardType.preEvent)
            .copyWith(surveyQuestions: [surveyQuestion]),
        Event(
          id: 'test-event-id',
          collectionPath: 'eventCollectionPath',
          creatorId: 'userId',
          communityId: 'communityId',
          templateId: 'templateId',
          status: EventStatus.active,
        ),
      );
      presenterWithRealModel = PrePostEventDialogPresenter(
        mockView,
        model,
        helper: mockHelper,
        testResponsiveLayoutService: mockResponsiveLayoutService,
        userAdminDetailsProvider: mockUserAdminDetailsProvider,
      );
      presenterWithRealModel.selectSurveyOption(surveyQuestion, 'o1');
    });

    tearDown(() {
      reset(mockFirestoreEventService);
    });

    test('successful save marks the survey submitted', () async {
      when(
        mockFirestoreEventService.savePrePostSurveyResponse(
          event: anyNamed('event'),
          prePostCardType: anyNamed('prePostCardType'),
          answers: anyNamed('answers'),
        ),
      ).thenAnswer((_) async {});

      expect(presenterWithRealModel.canDismiss, isFalse);

      await presenterWithRealModel.submitSurvey();

      expect(model.isSurveySubmitted, isTrue);
      expect(presenterWithRealModel.canDismiss, isTrue);
    });

    test('failed save makes the dialog dismissible so the participant is not trapped',
        () async {
      when(
        mockFirestoreEventService.savePrePostSurveyResponse(
          event: anyNamed('event'),
          prePostCardType: anyNamed('prePostCardType'),
          answers: anyNamed('answers'),
        ),
      ).thenThrow(Exception('network error'));

      expect(presenterWithRealModel.canDismiss, isFalse);

      await expectLater(
        presenterWithRealModel.submitSurvey(),
        throwsException,
      );

      expect(model.isSurveySubmitted, isFalse);
      expect(model.surveySubmitFailed, isTrue);
      expect(presenterWithRealModel.canDismiss, isTrue);
    });
  });
}
