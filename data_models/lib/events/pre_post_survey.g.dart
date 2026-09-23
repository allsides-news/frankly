// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pre_post_survey.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$_PrePostSurveyItem _$$_PrePostSurveyItemFromJson(Map<String, dynamic> json) =>
    _$_PrePostSurveyItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
    );

Map<String, dynamic> _$$_PrePostSurveyItemToJson(
        _$_PrePostSurveyItem instance) =>
    <String, dynamic>{
      'id': instance.id,
      'text': instance.text,
    };

_$_PrePostSurveyQuestion _$$_PrePostSurveyQuestionFromJson(
        Map<String, dynamic> json) =>
    _$_PrePostSurveyQuestion(
      id: json['id'] as String,
      type: $enumDecode(_$PrePostSurveyQuestionTypeEnumMap, json['type'],
          unknownValue: PrePostSurveyQuestionType.multipleChoice),
      title: json['title'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map(
                  (e) => PrePostSurveyItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      statements: (json['statements'] as List<dynamic>?)
              ?.map(
                  (e) => PrePostSurveyItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$$_PrePostSurveyQuestionToJson(
        _$_PrePostSurveyQuestion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'type': _$PrePostSurveyQuestionTypeEnumMap[instance.type]!,
      'title': instance.title,
      'options': instance.options.map((e) => e.toJson()).toList(),
      'statements': instance.statements.map((e) => e.toJson()).toList(),
    };

const _$PrePostSurveyQuestionTypeEnumMap = {
  PrePostSurveyQuestionType.multipleChoice: 'multipleChoice',
  PrePostSurveyQuestionType.agreeDisagree: 'agreeDisagree',
  PrePostSurveyQuestionType.residence: 'residence',
};

_$_PrePostSurveyAnswer _$$_PrePostSurveyAnswerFromJson(
        Map<String, dynamic> json) =>
    _$_PrePostSurveyAnswer(
      questionId: json['questionId'] as String,
      questionType:
          $enumDecode(_$PrePostSurveyQuestionTypeEnumMap, json['questionType']),
      questionText: json['questionText'] as String? ?? '',
      statementId: json['statementId'] as String?,
      optionId: json['optionId'] as String?,
      optionText: json['optionText'] as String?,
      agreement:
          $enumDecodeNullable(_$AgreeDisagreeAnswerEnumMap, json['agreement']),
    );

Map<String, dynamic> _$$_PrePostSurveyAnswerToJson(
        _$_PrePostSurveyAnswer instance) =>
    <String, dynamic>{
      'questionId': instance.questionId,
      'questionType':
          _$PrePostSurveyQuestionTypeEnumMap[instance.questionType]!,
      'questionText': instance.questionText,
      'statementId': instance.statementId,
      'optionId': instance.optionId,
      'optionText': instance.optionText,
      'agreement': _$AgreeDisagreeAnswerEnumMap[instance.agreement],
    };

const _$AgreeDisagreeAnswerEnumMap = {
  AgreeDisagreeAnswer.stronglyAgree: 'stronglyAgree',
  AgreeDisagreeAnswer.somewhatAgree: 'somewhatAgree',
  AgreeDisagreeAnswer.somewhatDisagree: 'somewhatDisagree',
  AgreeDisagreeAnswer.stronglyDisagree: 'stronglyDisagree',
  AgreeDisagreeAnswer.unsure: 'unsure',
};

_$_PrePostSurveyResponse _$$_PrePostSurveyResponseFromJson(
        Map<String, dynamic> json) =>
    _$_PrePostSurveyResponse(
      userId: json['userId'] as String,
      preEventAnswers: (json['preEventAnswers'] as List<dynamic>?)
              ?.map((e) =>
                  PrePostSurveyAnswer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      postEventAnswers: (json['postEventAnswers'] as List<dynamic>?)
              ?.map((e) =>
                  PrePostSurveyAnswer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      preEventAnsweredDate: dateTimeFromTimestamp(json['preEventAnsweredDate']),
      postEventAnsweredDate:
          dateTimeFromTimestamp(json['postEventAnsweredDate']),
    );

Map<String, dynamic> _$$_PrePostSurveyResponseToJson(
        _$_PrePostSurveyResponse instance) =>
    <String, dynamic>{
      'userId': instance.userId,
      'preEventAnswers':
          instance.preEventAnswers.map((e) => e.toJson()).toList(),
      'postEventAnswers':
          instance.postEventAnswers.map((e) => e.toJson()).toList(),
      'preEventAnsweredDate':
          serverTimestampOrNull(instance.preEventAnsweredDate),
      'postEventAnsweredDate':
          serverTimestampOrNull(instance.postEventAnsweredDate),
    };
