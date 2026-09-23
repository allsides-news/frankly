// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pre_post_survey.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
    'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#custom-getters-and-methods');

PrePostSurveyItem _$PrePostSurveyItemFromJson(Map<String, dynamic> json) {
  return _PrePostSurveyItem.fromJson(json);
}

/// @nodoc
mixin _$PrePostSurveyItem {
  String get id => throw _privateConstructorUsedError;
  String get text => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PrePostSurveyItemCopyWith<PrePostSurveyItem> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrePostSurveyItemCopyWith<$Res> {
  factory $PrePostSurveyItemCopyWith(
          PrePostSurveyItem value, $Res Function(PrePostSurveyItem) then) =
      _$PrePostSurveyItemCopyWithImpl<$Res, PrePostSurveyItem>;
  @useResult
  $Res call({String id, String text});
}

/// @nodoc
class _$PrePostSurveyItemCopyWithImpl<$Res, $Val extends PrePostSurveyItem>
    implements $PrePostSurveyItemCopyWith<$Res> {
  _$PrePostSurveyItemCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? text = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$_PrePostSurveyItemCopyWith<$Res>
    implements $PrePostSurveyItemCopyWith<$Res> {
  factory _$$_PrePostSurveyItemCopyWith(_$_PrePostSurveyItem value,
          $Res Function(_$_PrePostSurveyItem) then) =
      __$$_PrePostSurveyItemCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, String text});
}

/// @nodoc
class __$$_PrePostSurveyItemCopyWithImpl<$Res>
    extends _$PrePostSurveyItemCopyWithImpl<$Res, _$_PrePostSurveyItem>
    implements _$$_PrePostSurveyItemCopyWith<$Res> {
  __$$_PrePostSurveyItemCopyWithImpl(
      _$_PrePostSurveyItem _value, $Res Function(_$_PrePostSurveyItem) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? text = null,
  }) {
    return _then(_$_PrePostSurveyItem(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      text: null == text
          ? _value.text
          : text // ignore: cast_nullable_to_non_nullable
              as String,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$_PrePostSurveyItem implements _PrePostSurveyItem {
  _$_PrePostSurveyItem({required this.id, this.text = ''});

  factory _$_PrePostSurveyItem.fromJson(Map<String, dynamic> json) =>
      _$$_PrePostSurveyItemFromJson(json);

  @override
  final String id;
  @override
  @JsonKey()
  final String text;

  @override
  String toString() {
    return 'PrePostSurveyItem(id: $id, text: $text)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$_PrePostSurveyItem &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.text, text) || other.text == text));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, id, text);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$_PrePostSurveyItemCopyWith<_$_PrePostSurveyItem> get copyWith =>
      __$$_PrePostSurveyItemCopyWithImpl<_$_PrePostSurveyItem>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$_PrePostSurveyItemToJson(
      this,
    );
  }
}

abstract class _PrePostSurveyItem implements PrePostSurveyItem {
  factory _PrePostSurveyItem({required final String id, final String text}) =
      _$_PrePostSurveyItem;

  factory _PrePostSurveyItem.fromJson(Map<String, dynamic> json) =
      _$_PrePostSurveyItem.fromJson;

  @override
  String get id;
  @override
  String get text;
  @override
  @JsonKey(ignore: true)
  _$$_PrePostSurveyItemCopyWith<_$_PrePostSurveyItem> get copyWith =>
      throw _privateConstructorUsedError;
}

PrePostSurveyQuestion _$PrePostSurveyQuestionFromJson(
    Map<String, dynamic> json) {
  return _PrePostSurveyQuestion.fromJson(json);
}

/// @nodoc
mixin _$PrePostSurveyQuestion {
  String get id => throw _privateConstructorUsedError;

  /// Unknown types (added in newer app versions) decode to an empty
  /// multiple choice question, which [hasData] filters out, so older
  /// deployed functions and clients don't crash parsing the event.
  @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
  PrePostSurveyQuestionType get type => throw _privateConstructorUsedError;

  /// The question text for [PrePostSurveyQuestionType.multipleChoice]
  /// questions. Unused for agree/disagree questions which render a fixed
  /// section header above their statements.
  String get title => throw _privateConstructorUsedError;

  /// Answer options for [PrePostSurveyQuestionType.multipleChoice] questions.
  List<PrePostSurveyItem> get options => throw _privateConstructorUsedError;

  /// Statements to be rated for [PrePostSurveyQuestionType.agreeDisagree]
  /// questions.
  List<PrePostSurveyItem> get statements => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PrePostSurveyQuestionCopyWith<PrePostSurveyQuestion> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrePostSurveyQuestionCopyWith<$Res> {
  factory $PrePostSurveyQuestionCopyWith(PrePostSurveyQuestion value,
          $Res Function(PrePostSurveyQuestion) then) =
      _$PrePostSurveyQuestionCopyWithImpl<$Res, PrePostSurveyQuestion>;
  @useResult
  $Res call(
      {String id,
      @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
      PrePostSurveyQuestionType type,
      String title,
      List<PrePostSurveyItem> options,
      List<PrePostSurveyItem> statements});
}

/// @nodoc
class _$PrePostSurveyQuestionCopyWithImpl<$Res,
        $Val extends PrePostSurveyQuestion>
    implements $PrePostSurveyQuestionCopyWith<$Res> {
  _$PrePostSurveyQuestionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? title = null,
    Object? options = null,
    Object? statements = null,
  }) {
    return _then(_value.copyWith(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as PrePostSurveyQuestionType,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value.options
          : options // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyItem>,
      statements: null == statements
          ? _value.statements
          : statements // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyItem>,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$_PrePostSurveyQuestionCopyWith<$Res>
    implements $PrePostSurveyQuestionCopyWith<$Res> {
  factory _$$_PrePostSurveyQuestionCopyWith(_$_PrePostSurveyQuestion value,
          $Res Function(_$_PrePostSurveyQuestion) then) =
      __$$_PrePostSurveyQuestionCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String id,
      @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
      PrePostSurveyQuestionType type,
      String title,
      List<PrePostSurveyItem> options,
      List<PrePostSurveyItem> statements});
}

/// @nodoc
class __$$_PrePostSurveyQuestionCopyWithImpl<$Res>
    extends _$PrePostSurveyQuestionCopyWithImpl<$Res, _$_PrePostSurveyQuestion>
    implements _$$_PrePostSurveyQuestionCopyWith<$Res> {
  __$$_PrePostSurveyQuestionCopyWithImpl(_$_PrePostSurveyQuestion _value,
      $Res Function(_$_PrePostSurveyQuestion) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? type = null,
    Object? title = null,
    Object? options = null,
    Object? statements = null,
  }) {
    return _then(_$_PrePostSurveyQuestion(
      id: null == id
          ? _value.id
          : id // ignore: cast_nullable_to_non_nullable
              as String,
      type: null == type
          ? _value.type
          : type // ignore: cast_nullable_to_non_nullable
              as PrePostSurveyQuestionType,
      title: null == title
          ? _value.title
          : title // ignore: cast_nullable_to_non_nullable
              as String,
      options: null == options
          ? _value.options
          : options // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyItem>,
      statements: null == statements
          ? _value.statements
          : statements // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyItem>,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$_PrePostSurveyQuestion extends _PrePostSurveyQuestion {
  _$_PrePostSurveyQuestion(
      {required this.id,
      @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
      required this.type,
      this.title = '',
      this.options = const [],
      this.statements = const []})
      : super._();

  factory _$_PrePostSurveyQuestion.fromJson(Map<String, dynamic> json) =>
      _$$_PrePostSurveyQuestionFromJson(json);

  @override
  final String id;

  /// Unknown types (added in newer app versions) decode to an empty
  /// multiple choice question, which [hasData] filters out, so older
  /// deployed functions and clients don't crash parsing the event.
  @override
  @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
  final PrePostSurveyQuestionType type;

  /// The question text for [PrePostSurveyQuestionType.multipleChoice]
  /// questions. Unused for agree/disagree questions which render a fixed
  /// section header above their statements.
  @override
  @JsonKey()
  final String title;

  /// Answer options for [PrePostSurveyQuestionType.multipleChoice] questions.
  @override
  @JsonKey()
  final List<PrePostSurveyItem> options;

  /// Statements to be rated for [PrePostSurveyQuestionType.agreeDisagree]
  /// questions.
  @override
  @JsonKey()
  final List<PrePostSurveyItem> statements;

  @override
  String toString() {
    return 'PrePostSurveyQuestion(id: $id, type: $type, title: $title, options: $options, statements: $statements)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$_PrePostSurveyQuestion &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.type, type) || other.type == type) &&
            (identical(other.title, title) || other.title == title) &&
            const DeepCollectionEquality().equals(other.options, options) &&
            const DeepCollectionEquality()
                .equals(other.statements, statements));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      id,
      type,
      title,
      const DeepCollectionEquality().hash(options),
      const DeepCollectionEquality().hash(statements));

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$_PrePostSurveyQuestionCopyWith<_$_PrePostSurveyQuestion> get copyWith =>
      __$$_PrePostSurveyQuestionCopyWithImpl<_$_PrePostSurveyQuestion>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$_PrePostSurveyQuestionToJson(
      this,
    );
  }
}

abstract class _PrePostSurveyQuestion extends PrePostSurveyQuestion {
  factory _PrePostSurveyQuestion(
      {required final String id,
      @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
      required final PrePostSurveyQuestionType type,
      final String title,
      final List<PrePostSurveyItem> options,
      final List<PrePostSurveyItem> statements}) = _$_PrePostSurveyQuestion;
  _PrePostSurveyQuestion._() : super._();

  factory _PrePostSurveyQuestion.fromJson(Map<String, dynamic> json) =
      _$_PrePostSurveyQuestion.fromJson;

  @override
  String get id;
  @override

  /// Unknown types (added in newer app versions) decode to an empty
  /// multiple choice question, which [hasData] filters out, so older
  /// deployed functions and clients don't crash parsing the event.
  @JsonKey(unknownEnumValue: PrePostSurveyQuestionType.multipleChoice)
  PrePostSurveyQuestionType get type;
  @override

  /// The question text for [PrePostSurveyQuestionType.multipleChoice]
  /// questions. Unused for agree/disagree questions which render a fixed
  /// section header above their statements.
  String get title;
  @override

  /// Answer options for [PrePostSurveyQuestionType.multipleChoice] questions.
  List<PrePostSurveyItem> get options;
  @override

  /// Statements to be rated for [PrePostSurveyQuestionType.agreeDisagree]
  /// questions.
  List<PrePostSurveyItem> get statements;
  @override
  @JsonKey(ignore: true)
  _$$_PrePostSurveyQuestionCopyWith<_$_PrePostSurveyQuestion> get copyWith =>
      throw _privateConstructorUsedError;
}

PrePostSurveyAnswer _$PrePostSurveyAnswerFromJson(Map<String, dynamic> json) {
  return _PrePostSurveyAnswer.fromJson(json);
}

/// @nodoc
mixin _$PrePostSurveyAnswer {
  String get questionId => throw _privateConstructorUsedError;
  PrePostSurveyQuestionType get questionType =>
      throw _privateConstructorUsedError;

  /// The question (multiple choice) or statement (agree/disagree) text as it
  /// was when the participant answered.
  String get questionText => throw _privateConstructorUsedError;

  /// For agree/disagree: the statement being rated.
  String? get statementId => throw _privateConstructorUsedError;

  /// For multiple choice: the selected answer option.
  String? get optionId => throw _privateConstructorUsedError;
  String? get optionText => throw _privateConstructorUsedError;

  /// For agree/disagree: the selected level of agreement.
  @JsonKey(unknownEnumValue: null)
  AgreeDisagreeAnswer? get agreement => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PrePostSurveyAnswerCopyWith<PrePostSurveyAnswer> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrePostSurveyAnswerCopyWith<$Res> {
  factory $PrePostSurveyAnswerCopyWith(
          PrePostSurveyAnswer value, $Res Function(PrePostSurveyAnswer) then) =
      _$PrePostSurveyAnswerCopyWithImpl<$Res, PrePostSurveyAnswer>;
  @useResult
  $Res call(
      {String questionId,
      PrePostSurveyQuestionType questionType,
      String questionText,
      String? statementId,
      String? optionId,
      String? optionText,
      @JsonKey(unknownEnumValue: null) AgreeDisagreeAnswer? agreement});
}

/// @nodoc
class _$PrePostSurveyAnswerCopyWithImpl<$Res, $Val extends PrePostSurveyAnswer>
    implements $PrePostSurveyAnswerCopyWith<$Res> {
  _$PrePostSurveyAnswerCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? questionId = null,
    Object? questionType = null,
    Object? questionText = null,
    Object? statementId = freezed,
    Object? optionId = freezed,
    Object? optionText = freezed,
    Object? agreement = freezed,
  }) {
    return _then(_value.copyWith(
      questionId: null == questionId
          ? _value.questionId
          : questionId // ignore: cast_nullable_to_non_nullable
              as String,
      questionType: null == questionType
          ? _value.questionType
          : questionType // ignore: cast_nullable_to_non_nullable
              as PrePostSurveyQuestionType,
      questionText: null == questionText
          ? _value.questionText
          : questionText // ignore: cast_nullable_to_non_nullable
              as String,
      statementId: freezed == statementId
          ? _value.statementId
          : statementId // ignore: cast_nullable_to_non_nullable
              as String?,
      optionId: freezed == optionId
          ? _value.optionId
          : optionId // ignore: cast_nullable_to_non_nullable
              as String?,
      optionText: freezed == optionText
          ? _value.optionText
          : optionText // ignore: cast_nullable_to_non_nullable
              as String?,
      agreement: freezed == agreement
          ? _value.agreement
          : agreement // ignore: cast_nullable_to_non_nullable
              as AgreeDisagreeAnswer?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$_PrePostSurveyAnswerCopyWith<$Res>
    implements $PrePostSurveyAnswerCopyWith<$Res> {
  factory _$$_PrePostSurveyAnswerCopyWith(_$_PrePostSurveyAnswer value,
          $Res Function(_$_PrePostSurveyAnswer) then) =
      __$$_PrePostSurveyAnswerCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String questionId,
      PrePostSurveyQuestionType questionType,
      String questionText,
      String? statementId,
      String? optionId,
      String? optionText,
      @JsonKey(unknownEnumValue: null) AgreeDisagreeAnswer? agreement});
}

/// @nodoc
class __$$_PrePostSurveyAnswerCopyWithImpl<$Res>
    extends _$PrePostSurveyAnswerCopyWithImpl<$Res, _$_PrePostSurveyAnswer>
    implements _$$_PrePostSurveyAnswerCopyWith<$Res> {
  __$$_PrePostSurveyAnswerCopyWithImpl(_$_PrePostSurveyAnswer _value,
      $Res Function(_$_PrePostSurveyAnswer) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? questionId = null,
    Object? questionType = null,
    Object? questionText = null,
    Object? statementId = freezed,
    Object? optionId = freezed,
    Object? optionText = freezed,
    Object? agreement = freezed,
  }) {
    return _then(_$_PrePostSurveyAnswer(
      questionId: null == questionId
          ? _value.questionId
          : questionId // ignore: cast_nullable_to_non_nullable
              as String,
      questionType: null == questionType
          ? _value.questionType
          : questionType // ignore: cast_nullable_to_non_nullable
              as PrePostSurveyQuestionType,
      questionText: null == questionText
          ? _value.questionText
          : questionText // ignore: cast_nullable_to_non_nullable
              as String,
      statementId: freezed == statementId
          ? _value.statementId
          : statementId // ignore: cast_nullable_to_non_nullable
              as String?,
      optionId: freezed == optionId
          ? _value.optionId
          : optionId // ignore: cast_nullable_to_non_nullable
              as String?,
      optionText: freezed == optionText
          ? _value.optionText
          : optionText // ignore: cast_nullable_to_non_nullable
              as String?,
      agreement: freezed == agreement
          ? _value.agreement
          : agreement // ignore: cast_nullable_to_non_nullable
              as AgreeDisagreeAnswer?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$_PrePostSurveyAnswer implements _PrePostSurveyAnswer {
  _$_PrePostSurveyAnswer(
      {required this.questionId,
      required this.questionType,
      this.questionText = '',
      this.statementId,
      this.optionId,
      this.optionText,
      @JsonKey(unknownEnumValue: null) this.agreement});

  factory _$_PrePostSurveyAnswer.fromJson(Map<String, dynamic> json) =>
      _$$_PrePostSurveyAnswerFromJson(json);

  @override
  final String questionId;
  @override
  final PrePostSurveyQuestionType questionType;

  /// The question (multiple choice) or statement (agree/disagree) text as it
  /// was when the participant answered.
  @override
  @JsonKey()
  final String questionText;

  /// For agree/disagree: the statement being rated.
  @override
  final String? statementId;

  /// For multiple choice: the selected answer option.
  @override
  final String? optionId;
  @override
  final String? optionText;

  /// For agree/disagree: the selected level of agreement.
  @override
  @JsonKey(unknownEnumValue: null)
  final AgreeDisagreeAnswer? agreement;

  @override
  String toString() {
    return 'PrePostSurveyAnswer(questionId: $questionId, questionType: $questionType, questionText: $questionText, statementId: $statementId, optionId: $optionId, optionText: $optionText, agreement: $agreement)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$_PrePostSurveyAnswer &&
            (identical(other.questionId, questionId) ||
                other.questionId == questionId) &&
            (identical(other.questionType, questionType) ||
                other.questionType == questionType) &&
            (identical(other.questionText, questionText) ||
                other.questionText == questionText) &&
            (identical(other.statementId, statementId) ||
                other.statementId == statementId) &&
            (identical(other.optionId, optionId) ||
                other.optionId == optionId) &&
            (identical(other.optionText, optionText) ||
                other.optionText == optionText) &&
            (identical(other.agreement, agreement) ||
                other.agreement == agreement));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(runtimeType, questionId, questionType,
      questionText, statementId, optionId, optionText, agreement);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$_PrePostSurveyAnswerCopyWith<_$_PrePostSurveyAnswer> get copyWith =>
      __$$_PrePostSurveyAnswerCopyWithImpl<_$_PrePostSurveyAnswer>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$_PrePostSurveyAnswerToJson(
      this,
    );
  }
}

abstract class _PrePostSurveyAnswer implements PrePostSurveyAnswer {
  factory _PrePostSurveyAnswer(
      {required final String questionId,
      required final PrePostSurveyQuestionType questionType,
      final String questionText,
      final String? statementId,
      final String? optionId,
      final String? optionText,
      @JsonKey(unknownEnumValue: null)
      final AgreeDisagreeAnswer? agreement}) = _$_PrePostSurveyAnswer;

  factory _PrePostSurveyAnswer.fromJson(Map<String, dynamic> json) =
      _$_PrePostSurveyAnswer.fromJson;

  @override
  String get questionId;
  @override
  PrePostSurveyQuestionType get questionType;
  @override

  /// The question (multiple choice) or statement (agree/disagree) text as it
  /// was when the participant answered.
  String get questionText;
  @override

  /// For agree/disagree: the statement being rated.
  String? get statementId;
  @override

  /// For multiple choice: the selected answer option.
  String? get optionId;
  @override
  String? get optionText;
  @override

  /// For agree/disagree: the selected level of agreement.
  @JsonKey(unknownEnumValue: null)
  AgreeDisagreeAnswer? get agreement;
  @override
  @JsonKey(ignore: true)
  _$$_PrePostSurveyAnswerCopyWith<_$_PrePostSurveyAnswer> get copyWith =>
      throw _privateConstructorUsedError;
}

PrePostSurveyResponse _$PrePostSurveyResponseFromJson(
    Map<String, dynamic> json) {
  return _PrePostSurveyResponse.fromJson(json);
}

/// @nodoc
mixin _$PrePostSurveyResponse {
  String get userId => throw _privateConstructorUsedError;
  List<PrePostSurveyAnswer> get preEventAnswers =>
      throw _privateConstructorUsedError;
  List<PrePostSurveyAnswer> get postEventAnswers =>
      throw _privateConstructorUsedError;
  @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
  DateTime? get preEventAnsweredDate => throw _privateConstructorUsedError;
  @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
  DateTime? get postEventAnsweredDate => throw _privateConstructorUsedError;

  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;
  @JsonKey(ignore: true)
  $PrePostSurveyResponseCopyWith<PrePostSurveyResponse> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PrePostSurveyResponseCopyWith<$Res> {
  factory $PrePostSurveyResponseCopyWith(PrePostSurveyResponse value,
          $Res Function(PrePostSurveyResponse) then) =
      _$PrePostSurveyResponseCopyWithImpl<$Res, PrePostSurveyResponse>;
  @useResult
  $Res call(
      {String userId,
      List<PrePostSurveyAnswer> preEventAnswers,
      List<PrePostSurveyAnswer> postEventAnswers,
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      DateTime? preEventAnsweredDate,
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      DateTime? postEventAnsweredDate});
}

/// @nodoc
class _$PrePostSurveyResponseCopyWithImpl<$Res,
        $Val extends PrePostSurveyResponse>
    implements $PrePostSurveyResponseCopyWith<$Res> {
  _$PrePostSurveyResponseCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userId = null,
    Object? preEventAnswers = null,
    Object? postEventAnswers = null,
    Object? preEventAnsweredDate = freezed,
    Object? postEventAnsweredDate = freezed,
  }) {
    return _then(_value.copyWith(
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      preEventAnswers: null == preEventAnswers
          ? _value.preEventAnswers
          : preEventAnswers // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyAnswer>,
      postEventAnswers: null == postEventAnswers
          ? _value.postEventAnswers
          : postEventAnswers // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyAnswer>,
      preEventAnsweredDate: freezed == preEventAnsweredDate
          ? _value.preEventAnsweredDate
          : preEventAnsweredDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      postEventAnsweredDate: freezed == postEventAnsweredDate
          ? _value.postEventAnsweredDate
          : postEventAnsweredDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ) as $Val);
  }
}

/// @nodoc
abstract class _$$_PrePostSurveyResponseCopyWith<$Res>
    implements $PrePostSurveyResponseCopyWith<$Res> {
  factory _$$_PrePostSurveyResponseCopyWith(_$_PrePostSurveyResponse value,
          $Res Function(_$_PrePostSurveyResponse) then) =
      __$$_PrePostSurveyResponseCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call(
      {String userId,
      List<PrePostSurveyAnswer> preEventAnswers,
      List<PrePostSurveyAnswer> postEventAnswers,
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      DateTime? preEventAnsweredDate,
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      DateTime? postEventAnsweredDate});
}

/// @nodoc
class __$$_PrePostSurveyResponseCopyWithImpl<$Res>
    extends _$PrePostSurveyResponseCopyWithImpl<$Res, _$_PrePostSurveyResponse>
    implements _$$_PrePostSurveyResponseCopyWith<$Res> {
  __$$_PrePostSurveyResponseCopyWithImpl(_$_PrePostSurveyResponse _value,
      $Res Function(_$_PrePostSurveyResponse) _then)
      : super(_value, _then);

  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? userId = null,
    Object? preEventAnswers = null,
    Object? postEventAnswers = null,
    Object? preEventAnsweredDate = freezed,
    Object? postEventAnsweredDate = freezed,
  }) {
    return _then(_$_PrePostSurveyResponse(
      userId: null == userId
          ? _value.userId
          : userId // ignore: cast_nullable_to_non_nullable
              as String,
      preEventAnswers: null == preEventAnswers
          ? _value.preEventAnswers
          : preEventAnswers // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyAnswer>,
      postEventAnswers: null == postEventAnswers
          ? _value.postEventAnswers
          : postEventAnswers // ignore: cast_nullable_to_non_nullable
              as List<PrePostSurveyAnswer>,
      preEventAnsweredDate: freezed == preEventAnsweredDate
          ? _value.preEventAnsweredDate
          : preEventAnsweredDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
      postEventAnsweredDate: freezed == postEventAnsweredDate
          ? _value.postEventAnsweredDate
          : postEventAnsweredDate // ignore: cast_nullable_to_non_nullable
              as DateTime?,
    ));
  }
}

/// @nodoc
@JsonSerializable()
class _$_PrePostSurveyResponse implements _PrePostSurveyResponse {
  _$_PrePostSurveyResponse(
      {required this.userId,
      this.preEventAnswers = const [],
      this.postEventAnswers = const [],
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      this.preEventAnsweredDate,
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      this.postEventAnsweredDate});

  factory _$_PrePostSurveyResponse.fromJson(Map<String, dynamic> json) =>
      _$$_PrePostSurveyResponseFromJson(json);

  @override
  final String userId;
  @override
  @JsonKey()
  final List<PrePostSurveyAnswer> preEventAnswers;
  @override
  @JsonKey()
  final List<PrePostSurveyAnswer> postEventAnswers;
  @override
  @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
  final DateTime? preEventAnsweredDate;
  @override
  @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
  final DateTime? postEventAnsweredDate;

  @override
  String toString() {
    return 'PrePostSurveyResponse(userId: $userId, preEventAnswers: $preEventAnswers, postEventAnswers: $postEventAnswers, preEventAnsweredDate: $preEventAnsweredDate, postEventAnsweredDate: $postEventAnsweredDate)';
  }

  @override
  bool operator ==(dynamic other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$_PrePostSurveyResponse &&
            (identical(other.userId, userId) || other.userId == userId) &&
            const DeepCollectionEquality()
                .equals(other.preEventAnswers, preEventAnswers) &&
            const DeepCollectionEquality()
                .equals(other.postEventAnswers, postEventAnswers) &&
            (identical(other.preEventAnsweredDate, preEventAnsweredDate) ||
                other.preEventAnsweredDate == preEventAnsweredDate) &&
            (identical(other.postEventAnsweredDate, postEventAnsweredDate) ||
                other.postEventAnsweredDate == postEventAnsweredDate));
  }

  @JsonKey(ignore: true)
  @override
  int get hashCode => Object.hash(
      runtimeType,
      userId,
      const DeepCollectionEquality().hash(preEventAnswers),
      const DeepCollectionEquality().hash(postEventAnswers),
      preEventAnsweredDate,
      postEventAnsweredDate);

  @JsonKey(ignore: true)
  @override
  @pragma('vm:prefer-inline')
  _$$_PrePostSurveyResponseCopyWith<_$_PrePostSurveyResponse> get copyWith =>
      __$$_PrePostSurveyResponseCopyWithImpl<_$_PrePostSurveyResponse>(
          this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$_PrePostSurveyResponseToJson(
      this,
    );
  }
}

abstract class _PrePostSurveyResponse implements PrePostSurveyResponse {
  factory _PrePostSurveyResponse(
      {required final String userId,
      final List<PrePostSurveyAnswer> preEventAnswers,
      final List<PrePostSurveyAnswer> postEventAnswers,
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      final DateTime? preEventAnsweredDate,
      @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
      final DateTime? postEventAnsweredDate}) = _$_PrePostSurveyResponse;

  factory _PrePostSurveyResponse.fromJson(Map<String, dynamic> json) =
      _$_PrePostSurveyResponse.fromJson;

  @override
  String get userId;
  @override
  List<PrePostSurveyAnswer> get preEventAnswers;
  @override
  List<PrePostSurveyAnswer> get postEventAnswers;
  @override
  @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
  DateTime? get preEventAnsweredDate;
  @override
  @JsonKey(fromJson: dateTimeFromTimestamp, toJson: serverTimestampOrNull)
  DateTime? get postEventAnsweredDate;
  @override
  @JsonKey(ignore: true)
  _$$_PrePostSurveyResponseCopyWith<_$_PrePostSurveyResponse> get copyWith =>
      throw _privateConstructorUsedError;
}
