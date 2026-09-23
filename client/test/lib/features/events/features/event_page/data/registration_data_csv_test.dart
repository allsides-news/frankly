import 'package:flutter_test/flutter_test.dart';
import 'package:client/features/events/features/event_page/data/registration_data_csv.dart';
import 'package:data_models/community/member_details.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/events/pre_post_survey.dart';

Event _event({
  PrePostCard? pre,
  PrePostCard? post,
  int smartMatchQuestions = 0,
}) {
  return Event(
    id: 'eventId',
    collectionPath: 'community/c/templates/t/events',
    creatorId: 'host',
    communityId: 'communityId',
    templateId: 'templateId',
    status: EventStatus.active,
    preEventCardData: pre,
    postEventCardData: post,
    breakoutRoomDefinition: smartMatchQuestions == 0
        ? null
        : BreakoutRoomDefinition(
            breakoutQuestions: [
              for (var i = 0; i < smartMatchQuestions; i++)
                BreakoutQuestion(
                  id: 'q$i',
                  title: 'Smart $i',
                  answerOptionId: '',
                  answers: [],
                ),
            ],
          ),
  );
}

MemberDetails _member({
  required String id,
  String? email,
  String? name,
  MembershipStatus status = MembershipStatus.attendee,
  DateTime? rsvpTime,
  List<BreakoutQuestion> smartMatch = const [],
  String? currentBreakoutRoomId,
  bool isPresent = false,
  DateTime? mostRecentPresentTime,
}) {
  return MemberDetails(
    id: id,
    email: email ?? '$id@example.com',
    displayName: name ?? id,
    membership: Membership(
      userId: id,
      communityId: 'communityId',
      status: status,
    ),
    memberEvent: MemberEventData(
      eventId: 'eventId',
      templateId: 'templateId',
      participant: Participant(
        id: id,
        createdDate: rsvpTime,
        currentBreakoutRoomId: currentBreakoutRoomId,
        isPresent: isPresent,
        mostRecentPresentTime: mostRecentPresentTime,
        breakoutRoomSurveyQuestions: smartMatch,
      ),
    ),
  );
}

void main() {
  group('buildRegistrationDataCsvRows', () {
    test('keeps existing columns and adds attended', () {
      final rows = buildRegistrationDataCsvRows(
        appName: 'AllSides Roundtables',
        registrationData: [_member(id: 'u1', name: 'Ada')],
      );

      expect(rows.first, [
        'AllSides Roundtables ID',
        'Name',
        'Email',
        'Member status',
        'RSVP Time',
        'Opted In To Space',
        'Opted In To Newsletters',
        'attended',
      ]);
      expect(rows[1][0], 'u1');
      expect(rows[1][1], 'Ada');
      expect(rows[1][2], 'u1@example.com');
      expect(rows[1][3], 'attendee');
      expect(rows[1].last, '');
    });

    test('adds pre and post survey question columns with answers', () {
      final pre = PrePostCard(
        headline: 'Pre',
        message: '',
        type: PrePostCardType.preEvent,
        surveyQuestions: [
          PrePostSurveyQuestion(
            id: 'pre-mc',
            type: PrePostSurveyQuestionType.multipleChoice,
            title: 'How hopeful are you?',
            options: [
              PrePostSurveyItem(id: 'opt-a', text: 'Very'),
            ],
          ),
          PrePostSurveyQuestion(
            id: 'pre-ad',
            type: PrePostSurveyQuestionType.agreeDisagree,
            statements: [
              PrePostSurveyItem(id: 'stmt-1', text: 'The American Dream is alive'),
            ],
          ),
          PrePostSurveyQuestion(
            id: 'pre-res',
            type: PrePostSurveyQuestionType.residence,
          ),
        ],
      );
      final post = PrePostCard(
        headline: 'Post',
        message: '',
        type: PrePostCardType.postEvent,
        surveyQuestions: [
          PrePostSurveyQuestion(
            id: 'post-mc',
            type: PrePostSurveyQuestionType.multipleChoice,
            title: 'How hopeful are you?',
            options: [
              PrePostSurveyItem(id: 'opt-b', text: 'Less'),
            ],
          ),
        ],
      );

      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(pre: pre, post: post),
        registrationData: [_member(id: 'u1')],
        surveyResponsesByUserId: {
          'u1': PrePostSurveyResponse(
            userId: 'u1',
            preEventAnswers: [
              PrePostSurveyAnswer(
                questionId: 'pre-mc',
                questionType: PrePostSurveyQuestionType.multipleChoice,
                questionText: 'How hopeful are you?',
                optionId: 'opt-a',
                optionText: 'Very',
              ),
              PrePostSurveyAnswer(
                questionId: 'pre-ad',
                questionType: PrePostSurveyQuestionType.agreeDisagree,
                questionText: 'The American Dream is alive',
                statementId: 'stmt-1',
                agreement: AgreeDisagreeAnswer.somewhatAgree,
              ),
              PrePostSurveyAnswer(
                questionId: 'pre-res',
                questionType: PrePostSurveyQuestionType.residence,
                questionText: 'Where do you live?',
                optionId: 'CA',
                optionText: 'California',
              ),
            ],
            postEventAnswers: [
              PrePostSurveyAnswer(
                questionId: 'post-mc',
                questionType: PrePostSurveyQuestionType.multipleChoice,
                questionText: 'How hopeful are you?',
                optionId: 'opt-b',
                optionText: 'Less',
              ),
            ],
          ),
        },
      );

      expect(
        rows.first.sublist(7),
        [
          'Pre-survey: How hopeful are you?',
          'Pre-survey: The American Dream is alive',
          'Pre-survey: Where do you live?',
          'Post-survey: How hopeful are you?',
          'attended',
        ],
      );
      expect(rows[1][7], 'Very');
      expect(rows[1][8], 'Somewhat agree');
      expect(rows[1][9], 'California');
      expect(rows[1][10], 'Less');
    });

    test('leaves survey answers blank when the registrant has no response', () {
      final pre = PrePostCard(
        headline: 'Pre',
        message: '',
        type: PrePostCardType.preEvent,
        surveyQuestions: [
          PrePostSurveyQuestion(
            id: 'pre-mc',
            type: PrePostSurveyQuestionType.multipleChoice,
            title: 'How hopeful are you?',
            options: [PrePostSurveyItem(id: 'opt-a', text: 'Very')],
          ),
        ],
      );

      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(pre: pre),
        registrationData: [_member(id: 'u1')],
      );

      expect(rows[1][7], '');
      expect(rows[1].last, '');
    });

    test('marks attended TRUE/FALSE when attendance is known', () {
      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(),
        registrationData: [
          _member(id: 'attended-user'),
          _member(id: 'no-show'),
        ],
        attendedUserIds: {'attended-user'},
        hasRealBreakoutRooms: true,
        attendanceKnown: true,
      );

      expect(rows[1].last, 'TRUE');
      expect(rows[2].last, 'FALSE');
    });

    test('leaves attended blank when the event has not happened yet', () {
      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(),
        registrationData: [_member(id: 'u1')],
        attendanceKnown: false,
      );

      expect(rows[1].last, '');
    });

    test('counts currentBreakoutRoomId as attendance', () {
      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(),
        registrationData: [
          _member(id: 'u1', currentBreakoutRoomId: 'room-3'),
        ],
        attendanceKnown: true,
        hasRealBreakoutRooms: true,
      );

      expect(rows[1].last, 'TRUE');
    });

    test('does not count waiting room as attendance', () {
      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(),
        registrationData: [
          _member(id: 'u1', currentBreakoutRoomId: 'waiting-room'),
        ],
        attendanceKnown: true,
        hasRealBreakoutRooms: true,
      );

      expect(rows[1].last, 'FALSE');
    });

    test('falls back to presence when no breakout rooms ran', () {
      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(),
        registrationData: [
          _member(id: 'u1', mostRecentPresentTime: DateTime.utc(2026, 8, 15)),
          _member(id: 'u2'),
        ],
        hasRealBreakoutRooms: false,
        attendanceKnown: true,
      );

      expect(rows[1].last, 'TRUE');
      expect(rows[2].last, 'FALSE');
    });

    test('includes Smart Match answers before survey columns', () {
      final member = _member(
        id: 'u1',
        smartMatch: [
          BreakoutQuestion(
            id: 'sm1',
            title: 'Lean',
            answerOptionId: 'opt-1',
            answers: [
              BreakoutAnswer(
                id: 'a1',
                options: [
                  BreakoutAnswerOption(id: 'opt-1', title: 'Center'),
                ],
              ),
            ],
          ),
        ],
      );
      final pre = PrePostCard(
        headline: 'Pre',
        message: '',
        type: PrePostCardType.preEvent,
        surveyQuestions: [
          PrePostSurveyQuestion(
            id: 'pre-mc',
            type: PrePostSurveyQuestionType.multipleChoice,
            title: 'Hope',
            options: [PrePostSurveyItem(id: 'h1', text: 'High')],
          ),
        ],
      );

      final rows = buildRegistrationDataCsvRows(
        appName: 'App',
        event: _event(pre: pre, smartMatchQuestions: 1),
        registrationData: [member],
        attendanceKnown: true,
      );

      expect(rows.first[7], 'Answer 1');
      expect(rows.first[8], 'Pre-survey: Hope');
      expect(rows[1][7], 'Center');
      expect(rows[1][8], '');
      expect(rows[1].last, 'FALSE');
    });
  });
}
