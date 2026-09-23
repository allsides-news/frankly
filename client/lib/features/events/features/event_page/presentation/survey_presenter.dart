import 'package:flutter/material.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/services.dart';
import 'package:data_models/events/event.dart';

class SurveyPresenter extends ChangeNotifier {
  final CommunityProvider communityProvider;
  final EventProvider eventProvider;
  final Map<String, String> savedMatchingQuestionAnswers;

  SurveyPresenter({
    required this.communityProvider,
    required this.eventProvider,
    this.savedMatchingQuestionAnswers = const {},
  });

  late List<BreakoutQuestion> _surveyQuestions;
  bool _savedAnswersApplied = false;

  final zipCodeController = TextEditingController();

  List<BreakoutQuestion> get surveyQuestions => _surveyQuestions;
  bool get savedAnswersApplied => _savedAnswersApplied;

  void initialize() {
    final breakoutQuestions =
        eventProvider.event.breakoutRoomDefinition?.breakoutQuestions ?? [];

    var savedAnswersApplied = false;
    _surveyQuestions = breakoutQuestions.map((question) {
      final savedAnswerOptionId = savedMatchingQuestionAnswers[question.id];
      final savedAnswerStillExists = savedAnswerOptionId != null &&
          savedAnswerOptionId.isNotEmpty &&
          question.answers
              .expand((answer) => answer.options)
              .any((option) => option.id == savedAnswerOptionId);

      if (savedAnswerStillExists) {
        savedAnswersApplied = true;
        return question.copyWith(answerOptionId: savedAnswerOptionId);
      }

      return question.copyWith();
    }).toList();
    _savedAnswersApplied = savedAnswersApplied;

    zipCodeController.addListener(notifyListeners);
  }

  @override
  void dispose() {
    zipCodeController.removeListener(notifyListeners);
    super.dispose();
  }

  void setQuestionAnswer({required String id, required String answerOptionId}) {
    final questionIndex = _surveyQuestions.indexWhere((q) => q.id == id);

    if (questionIndex < 0) {
      loggingService.log(
        'SurveyPresenter.setQuestionAnswer: question is null, questionID: $id',
      );
      return;
    }

    _surveyQuestions[questionIndex] = _surveyQuestions[questionIndex]
        .copyWith(answerOptionId: answerOptionId);

    notifyListeners();
  }

  bool checkSurveyCompleted() {
    final surveyCompleted =
        !surveyQuestions.any((q) => q.answerOptionId.isEmpty);

    return surveyCompleted;
  }
}
