import 'package:collection/collection.dart';
import 'package:enum_to_string/enum_to_string.dart';
import 'package:data_models/community/member_details.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/events/pre_post_survey.dart';

/// Column title used for residence survey questions, matching the participant UI.
const String kRegistrationCsvResidenceQuestionTitle = 'Where do you live?';

class RegistrationCsvSurveyColumn {
  final String header;
  final String questionId;
  final String? statementId;
  final bool isPreEvent;

  const RegistrationCsvSurveyColumn({
    required this.header,
    required this.questionId,
    required this.isPreEvent,
    this.statementId,
  });
}

/// Builds rows for the Members Registration Data CSV, including Smart Match
/// answers, pre/post survey answers, and whether the registrant attended.
List<List<dynamic>> buildRegistrationDataCsvRows({
  required String appName,
  required List<MemberDetails> registrationData,
  Event? event,
  Map<String, PrePostSurveyResponse> surveyResponsesByUserId = const {},
  Set<String> attendedUserIds = const {},
  bool hasRealBreakoutRooms = false,
  bool attendanceKnown = false,
}) {
  final smartMatchQuestionCount =
      event?.breakoutRoomDefinition?.breakoutQuestions.length ?? 0;
  final preColumns = _surveyColumnsForCard(
    event?.preEventCardData,
    prefix: 'Pre-survey: ',
    isPreEvent: true,
  );
  final postColumns = _surveyColumnsForCard(
    event?.postEventCardData,
    prefix: 'Post-survey: ',
    isPreEvent: false,
  );

  final header = <dynamic>[
    '$appName ID',
    'Name',
    'Email',
    'Member status',
    'RSVP Time',
    'Opted In To Space',
    'Opted In To Newsletters',
    for (var i = 0; i < smartMatchQuestionCount; i++) 'Answer ${i + 1}',
    ...preColumns.map((column) => column.header),
    ...postColumns.map((column) => column.header),
    'attended',
  ];

  final rows = <List<dynamic>>[header];

  for (final member in registrationData) {
    final participant = member.memberEvent?.participant;
    final row = <dynamic>[
      member.id,
      member.displayName ?? '',
      member.email ?? '',
      EnumToString.convertToString(member.membership?.status),
      participant?.createdDate?.toUtc(),
      participant?.optInToCommunity ?? false,
      participant?.optInToNewsletters ?? false,
    ];

    row.addAll(
      _smartMatchAnswers(
        questions: participant?.breakoutRoomSurveyQuestions ?? [],
        expectedCount: smartMatchQuestionCount,
      ),
    );

    final response = surveyResponsesByUserId[member.id];
    for (final column in preColumns) {
      row.add(_surveyAnswerText(response, column));
    }
    for (final column in postColumns) {
      row.add(_surveyAnswerText(response, column));
    }

    row.add(
      _attendedCell(
        userId: member.id,
        currentBreakoutRoomId: participant?.currentBreakoutRoomId,
        isPresent: participant?.isPresent ?? false,
        mostRecentPresentTime: participant?.mostRecentPresentTime,
        attendedUserIds: attendedUserIds,
        hasRealBreakoutRooms: hasRealBreakoutRooms,
        attendanceKnown: attendanceKnown,
      ),
    );

    rows.add(row);
  }

  return rows;
}

List<RegistrationCsvSurveyColumn> _surveyColumnsForCard(
  PrePostCard? card, {
  required String prefix,
  required bool isPreEvent,
}) {
  if (card == null) return const [];

  final columns = <RegistrationCsvSurveyColumn>[];
  for (final question in card.surveyQuestions.where((q) => q.hasData)) {
    switch (question.type) {
      case PrePostSurveyQuestionType.multipleChoice:
        columns.add(
          RegistrationCsvSurveyColumn(
            header: '$prefix${question.title}',
            questionId: question.id,
            isPreEvent: isPreEvent,
          ),
        );
        break;
      case PrePostSurveyQuestionType.residence:
        final title = question.title.trim().isNotEmpty
            ? question.title
            : kRegistrationCsvResidenceQuestionTitle;
        columns.add(
          RegistrationCsvSurveyColumn(
            header: '$prefix$title',
            questionId: question.id,
            isPreEvent: isPreEvent,
          ),
        );
        break;
      case PrePostSurveyQuestionType.agreeDisagree:
        for (final statement in question.statements
            .where((statement) => statement.text.trim().isNotEmpty)) {
          columns.add(
            RegistrationCsvSurveyColumn(
              header: '$prefix${statement.text}',
              questionId: question.id,
              statementId: statement.id,
              isPreEvent: isPreEvent,
            ),
          );
        }
        break;
    }
  }
  return columns;
}

List<dynamic> _smartMatchAnswers({
  required List<BreakoutQuestion> questions,
  required int expectedCount,
}) {
  final answers = <dynamic>[];
  for (var i = 0; i < expectedCount; i++) {
    if (i >= questions.length) {
      answers.add('');
      continue;
    }
    final question = questions[i];
    final options = question.answers.map((e) => e.options).flattened.toList();
    final answerId = question.answerOptionId;
    if (answerId.isEmpty) {
      answers.add('');
      continue;
    }
    final option = options.firstWhereOrNull((element) => element.id == answerId);
    answers.add(option?.title ?? '');
  }
  return answers;
}

String _surveyAnswerText(
  PrePostSurveyResponse? response,
  RegistrationCsvSurveyColumn column,
) {
  if (response == null) return '';
  final answers =
      column.isPreEvent ? response.preEventAnswers : response.postEventAnswers;
  final match = answers.firstWhereOrNull((answer) {
    if (answer.questionId != column.questionId) return false;
    if (column.statementId == null) return true;
    return answer.statementId == column.statementId;
  });
  if (match == null) return '';

  if (match.questionType == PrePostSurveyQuestionType.agreeDisagree) {
    return match.agreement?.text ?? '';
  }
  return match.optionText ?? '';
}

String _attendedCell({
  required String userId,
  required String? currentBreakoutRoomId,
  required bool isPresent,
  required DateTime? mostRecentPresentTime,
  required Set<String> attendedUserIds,
  required bool hasRealBreakoutRooms,
  required bool attendanceKnown,
}) {
  final attended = _didAttend(
    userId: userId,
    currentBreakoutRoomId: currentBreakoutRoomId,
    isPresent: isPresent,
    mostRecentPresentTime: mostRecentPresentTime,
    attendedUserIds: attendedUserIds,
    hasRealBreakoutRooms: hasRealBreakoutRooms,
  );

  if (attended) return 'TRUE';
  if (!attendanceKnown) return '';
  return 'FALSE';
}

bool _didAttend({
  required String userId,
  required String? currentBreakoutRoomId,
  required bool isPresent,
  required DateTime? mostRecentPresentTime,
  required Set<String> attendedUserIds,
  required bool hasRealBreakoutRooms,
}) {
  if (attendedUserIds.contains(userId)) return true;
  if (_isRealBreakoutRoom(currentBreakoutRoomId)) return true;
  if (hasRealBreakoutRooms) return false;
  return isPresent || mostRecentPresentTime != null;
}

bool _isRealBreakoutRoom(String? roomId) {
  return roomId != null &&
      roomId.isNotEmpty &&
      roomId != breakoutsWaitingRoomId &&
      roomId != reassignNewRoomId;
}
