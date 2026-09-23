import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/utils/firestore_utils.dart';

part 'pre_post_survey.freezed.dart';
part 'pre_post_survey.g.dart';

enum PrePostSurveyQuestionType {
  multipleChoice,
  agreeDisagree,

  /// Fixed "Where do you live?" question answered from a dropdown of U.S.
  /// states and territories (see [ResidenceOptions]).
  residence,
}

/// Fixed answer options for [PrePostSurveyQuestionType.residence] questions:
/// U.S. states, D.C., territories, and an option for non-U.S. residents.
/// IDs are USPS codes so recorded answers stay stable if names are reworded.
class ResidenceOptions {
  static const String nonUsOptionId = 'nonUS';

  static final List<PrePostSurveyItem> all = [
    PrePostSurveyItem(id: 'AL', text: 'Alabama'),
    PrePostSurveyItem(id: 'AK', text: 'Alaska'),
    PrePostSurveyItem(id: 'AZ', text: 'Arizona'),
    PrePostSurveyItem(id: 'AR', text: 'Arkansas'),
    PrePostSurveyItem(id: 'CA', text: 'California'),
    PrePostSurveyItem(id: 'CO', text: 'Colorado'),
    PrePostSurveyItem(id: 'CT', text: 'Connecticut'),
    PrePostSurveyItem(id: 'DE', text: 'Delaware'),
    PrePostSurveyItem(id: 'DC', text: 'District of Columbia'),
    PrePostSurveyItem(id: 'FL', text: 'Florida'),
    PrePostSurveyItem(id: 'GA', text: 'Georgia'),
    PrePostSurveyItem(id: 'HI', text: 'Hawaii'),
    PrePostSurveyItem(id: 'ID', text: 'Idaho'),
    PrePostSurveyItem(id: 'IL', text: 'Illinois'),
    PrePostSurveyItem(id: 'IN', text: 'Indiana'),
    PrePostSurveyItem(id: 'IA', text: 'Iowa'),
    PrePostSurveyItem(id: 'KS', text: 'Kansas'),
    PrePostSurveyItem(id: 'KY', text: 'Kentucky'),
    PrePostSurveyItem(id: 'LA', text: 'Louisiana'),
    PrePostSurveyItem(id: 'ME', text: 'Maine'),
    PrePostSurveyItem(id: 'MD', text: 'Maryland'),
    PrePostSurveyItem(id: 'MA', text: 'Massachusetts'),
    PrePostSurveyItem(id: 'MI', text: 'Michigan'),
    PrePostSurveyItem(id: 'MN', text: 'Minnesota'),
    PrePostSurveyItem(id: 'MS', text: 'Mississippi'),
    PrePostSurveyItem(id: 'MO', text: 'Missouri'),
    PrePostSurveyItem(id: 'MT', text: 'Montana'),
    PrePostSurveyItem(id: 'NE', text: 'Nebraska'),
    PrePostSurveyItem(id: 'NV', text: 'Nevada'),
    PrePostSurveyItem(id: 'NH', text: 'New Hampshire'),
    PrePostSurveyItem(id: 'NJ', text: 'New Jersey'),
    PrePostSurveyItem(id: 'NM', text: 'New Mexico'),
    PrePostSurveyItem(id: 'NY', text: 'New York'),
    PrePostSurveyItem(id: 'NC', text: 'North Carolina'),
    PrePostSurveyItem(id: 'ND', text: 'North Dakota'),
    PrePostSurveyItem(id: 'OH', text: 'Ohio'),
    PrePostSurveyItem(id: 'OK', text: 'Oklahoma'),
    PrePostSurveyItem(id: 'OR', text: 'Oregon'),
    PrePostSurveyItem(id: 'PA', text: 'Pennsylvania'),
    PrePostSurveyItem(id: 'RI', text: 'Rhode Island'),
    PrePostSurveyItem(id: 'SC', text: 'South Carolina'),
    PrePostSurveyItem(id: 'SD', text: 'South Dakota'),
    PrePostSurveyItem(id: 'TN', text: 'Tennessee'),
    PrePostSurveyItem(id: 'TX', text: 'Texas'),
    PrePostSurveyItem(id: 'UT', text: 'Utah'),
    PrePostSurveyItem(id: 'VT', text: 'Vermont'),
    PrePostSurveyItem(id: 'VA', text: 'Virginia'),
    PrePostSurveyItem(id: 'WA', text: 'Washington'),
    PrePostSurveyItem(id: 'WV', text: 'West Virginia'),
    PrePostSurveyItem(id: 'WI', text: 'Wisconsin'),
    PrePostSurveyItem(id: 'WY', text: 'Wyoming'),
    PrePostSurveyItem(id: 'AS', text: 'American Samoa'),
    PrePostSurveyItem(id: 'GU', text: 'Guam'),
    PrePostSurveyItem(id: 'MP', text: 'Northern Mariana Islands'),
    PrePostSurveyItem(id: 'PR', text: 'Puerto Rico'),
    PrePostSurveyItem(id: 'VI', text: 'U.S. Virgin Islands'),
    PrePostSurveyItem(id: nonUsOptionId, text: "I don't live in the U.S."),
  ];
}

/// Fixed answer scale for [PrePostSurveyQuestionType.agreeDisagree] statements.
enum AgreeDisagreeAnswer {
  stronglyAgree,
  somewhatAgree,
  somewhatDisagree,
  stronglyDisagree,
  unsure,
}

extension AgreeDisagreeAnswerExtension on AgreeDisagreeAnswer {
  String get text {
    switch (this) {
      case AgreeDisagreeAnswer.stronglyAgree:
        return 'Strongly agree';
      case AgreeDisagreeAnswer.somewhatAgree:
        return 'Somewhat agree';
      case AgreeDisagreeAnswer.somewhatDisagree:
        return 'Somewhat disagree';
      case AgreeDisagreeAnswer.stronglyDisagree:
        return 'Strongly disagree';
      case AgreeDisagreeAnswer.unsure:
        return 'Unsure';
    }
  }
}

/// A single admin-defined text entry within a survey question: either a
/// multiple choice answer option or an agree/disagree statement.
@Freezed(makeCollectionsUnmodifiable: false)
class PrePostSurveyItem with _$PrePostSurveyItem implements SerializeableRequest {
  factory PrePostSurveyItem({
    required String id,
    @Default('') String text,
  }) = _PrePostSurveyItem;

  factory PrePostSurveyItem.fromJson(Map<String, dynamic> json) =>
      _$PrePostSurveyItemFromJson(json);
}

@Freezed(makeCollectionsUnmodifiable: false)
class PrePostSurveyQuestion
    with _$PrePostSurveyQuestion
    implements SerializeableRequest {
  static const int maxMultipleChoiceOptions = 10;
  static const int maxAgreeDisagreeStatements = 25;

  const PrePostSurveyQuestion._();

  factory PrePostSurveyQuestion({
    required String id,

    /// Unknown types (added in newer app versions) decode to an empty
    /// multiple choice question, which [hasData] filters out, so older
    /// deployed functions and clients don't crash parsing the event.
    @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
    required PrePostSurveyQuestionType type,

    /// The question text for [PrePostSurveyQuestionType.multipleChoice]
    /// questions. Unused for agree/disagree questions which render a fixed
    /// section header above their statements.
    @Default('') String title,

    /// Answer options for [PrePostSurveyQuestionType.multipleChoice] questions.
    @Default([]) List<PrePostSurveyItem> options,

    /// Statements to be rated for [PrePostSurveyQuestionType.agreeDisagree]
    /// questions.
    @Default([]) List<PrePostSurveyItem> statements,
  }) = _PrePostSurveyQuestion;

  factory PrePostSurveyQuestion.fromJson(Map<String, dynamic> json) =>
      _$PrePostSurveyQuestionFromJson(json);

  bool get hasData {
    switch (type) {
      case PrePostSurveyQuestionType.multipleChoice:
        return title.trim().isNotEmpty &&
            options.any((option) => option.text.trim().isNotEmpty);
      case PrePostSurveyQuestionType.agreeDisagree:
        return statements.any((statement) => statement.text.trim().isNotEmpty);
      case PrePostSurveyQuestionType.residence:
        // Question text and options are fixed in code.
        return true;
    }
  }
}

/// A participant's answer to a single multiple choice question or a single
/// agree/disagree statement.
@Freezed(makeCollectionsUnmodifiable: false)
class PrePostSurveyAnswer
    with _$PrePostSurveyAnswer
    implements SerializeableRequest {
  factory PrePostSurveyAnswer({
    required String questionId,
    required PrePostSurveyQuestionType questionType,

    /// The question (multiple choice) or statement (agree/disagree) text as it
    /// was when the participant answered.
    @Default('') String questionText,

    /// For agree/disagree: the statement being rated.
    String? statementId,

    /// For multiple choice: the selected answer option.
    String? optionId,
    String? optionText,

    /// For agree/disagree: the selected level of agreement.
    @JsonKey(unknownEnumValue: null) AgreeDisagreeAnswer? agreement,
  }) = _PrePostSurveyAnswer;

  factory PrePostSurveyAnswer.fromJson(Map<String, dynamic> json) =>
      _$PrePostSurveyAnswerFromJson(json);
}

/// A participant's survey answers for one event, stored under
/// `events/{eventId}/pre-post-survey-responses/{userId}`.
@Freezed(makeCollectionsUnmodifiable: false)
class PrePostSurveyResponse
    with _$PrePostSurveyResponse
    implements SerializeableRequest {
  static const String kFieldUserId = 'userId';
  static const String kFieldPreEventAnswers = 'preEventAnswers';
  static const String kFieldPostEventAnswers = 'postEventAnswers';
  static const String kFieldPreEventAnsweredDate = 'preEventAnsweredDate';
  static const String kFieldPostEventAnsweredDate = 'postEventAnsweredDate';

  factory PrePostSurveyResponse({
    required String userId,
    @Default([]) List<PrePostSurveyAnswer> preEventAnswers,
    @Default([]) List<PrePostSurveyAnswer> postEventAnswers,
    @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
    DateTime? preEventAnsweredDate,
    @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
    DateTime? postEventAnsweredDate,
  }) = _PrePostSurveyResponse;

  factory PrePostSurveyResponse.fromJson(Map<String, dynamic> json) =>
      _$PrePostSurveyResponseFromJson(json);
}
