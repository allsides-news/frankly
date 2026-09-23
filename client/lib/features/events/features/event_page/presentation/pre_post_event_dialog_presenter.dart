import 'package:client/core/utils/navigation_utils.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:client/features/community/data/providers/user_admin_details_builder.dart';
import 'package:client/core/data/services/responsive_layout_service.dart';
import 'package:client/services.dart';
import 'package:data_models/events/pre_post_survey.dart';
import 'package:data_models/events/pre_post_url_params.dart';

import 'views/pre_post_event_dialog_contract.dart';
import 'views/pre_post_survey_questions_view.dart';
import '../data/models/pre_post_event_dialog_model.dart';

class PrePostEventDialogPresenter {
  final PrePostEventDialogView _view;
  final PrePostEventDialogModel _model;
  final PrePostEventDialogPresenterHelper _helper;
  final ResponsiveLayoutService _responsiveLayoutService;
  final UserAdminDetailsProvider userAdminDetailsProvider;

  PrePostEventDialogPresenter(
    this._view,
    this._model, {
    PrePostEventDialogPresenterHelper? helper,
    ResponsiveLayoutService? testResponsiveLayoutService,
    required this.userAdminDetailsProvider,
  })  : _helper = helper ?? PrePostEventDialogPresenterHelper(),
        _responsiveLayoutService =
            testResponsiveLayoutService ?? responsiveLayoutService;

  void initialize() {
    // Start loading email
    userAdminDetailsProvider.getInfoFuture();
  }

  bool isMobile(BuildContext context) {
    return _responsiveLayoutService.isMobile(context);
  }

  double getSize(BuildContext context, double initialSize, {double? scale}) {
    return _responsiveLayoutService.getDynamicSize(
      context,
      initialSize,
      scale: scale,
    );
  }

  List<PrePostSurveyQuestion> get surveyQuestions => _model.showSurveyQuestions
      ? _model.prePostCard.surveyQuestions
          .where((question) => question.hasData)
          .toList()
      : [];

  /// Whether survey questions are configured, in which case answering them is
  /// required before the dialog can be dismissed.
  bool get isSurveyRequired => surveyQuestions.isNotEmpty;

  bool get isSurveyComplete {
    for (final question in surveyQuestions) {
      switch (question.type) {
        case PrePostSurveyQuestionType.multipleChoice:
          if (_model.selectedOptionIds[question.id] == null) return false;
          break;
        case PrePostSurveyQuestionType.agreeDisagree:
          final agreements =
              _model.selectedAgreements[question.id] ?? const {};
          final statements = question.statements
              .where((statement) => statement.text.trim().isNotEmpty);
          if (statements.any((statement) => agreements[statement.id] == null)) {
            return false;
          }
          break;
        case PrePostSurveyQuestionType.residence:
          if (_model.selectedOptionIds[question.id] == null) return false;
          break;
      }
    }
    return true;
  }

  // Dismissible after a failed save attempt (fail-open) so persistent
  // network/permission errors never trap the participant in the dialog.
  bool get canDismiss =>
      !isSurveyRequired ||
      _model.isSurveySubmitted ||
      _model.surveySubmitFailed;

  bool get isSurveySubmitted => _model.isSurveySubmitted;

  void selectSurveyOption(PrePostSurveyQuestion question, String optionId) {
    _model.selectedOptionIds[question.id] = optionId;
    _view.updateView();
  }

  void selectSurveyAgreement(
    PrePostSurveyQuestion question,
    PrePostSurveyItem statement,
    AgreeDisagreeAnswer answer,
  ) {
    _model.selectedAgreements.putIfAbsent(question.id, () => {})[statement.id] =
        answer;
    _view.updateView();
  }

  /// Records the participant's answers to the configured survey questions.
  Future<void> submitSurvey() async {
    if (_model.isSubmittingSurvey || _model.isSurveySubmitted) return;

    _model.isSubmittingSurvey = true;
    _view.updateView();

    try {
      final answers = <PrePostSurveyAnswer>[];
      for (final question in surveyQuestions) {
        switch (question.type) {
          case PrePostSurveyQuestionType.multipleChoice:
            final optionId = _model.selectedOptionIds[question.id];
            final option = question.options
                .firstWhereOrNull((option) => option.id == optionId);
            if (option == null) continue;
            answers.add(
              PrePostSurveyAnswer(
                questionId: question.id,
                questionType: question.type,
                questionText: question.title,
                optionId: option.id,
                optionText: option.text,
              ),
            );
            break;
          case PrePostSurveyQuestionType.agreeDisagree:
            final agreements =
                _model.selectedAgreements[question.id] ?? const {};
            for (final statement in question.statements
                .where((statement) => statement.text.trim().isNotEmpty)) {
              final agreement = agreements[statement.id];
              if (agreement == null) continue;
              answers.add(
                PrePostSurveyAnswer(
                  questionId: question.id,
                  questionType: question.type,
                  questionText: statement.text,
                  statementId: statement.id,
                  agreement: agreement,
                ),
              );
            }
            break;
          case PrePostSurveyQuestionType.residence:
            final optionId = _model.selectedOptionIds[question.id];
            final option = ResidenceOptions.all
                .firstWhereOrNull((option) => option.id == optionId);
            if (option == null) continue;
            answers.add(
              PrePostSurveyAnswer(
                questionId: question.id,
                questionType: question.type,
                questionText: kResidenceQuestionTitle,
                optionId: option.id,
                optionText: option.text,
              ),
            );
            break;
        }
      }

      await firestoreEventService.savePrePostSurveyResponse(
        event: _model.event,
        prePostCardType: _model.prePostCard.type,
        answers: answers,
      );
      _model.isSurveySubmitted = true;
    } catch (_) {
      _model.surveySubmitFailed = true;
      rethrow;
    } finally {
      _model.isSubmittingSurvey = false;
      _view.updateView();
    }
  }

  Future<void> launchSurvey(PrePostUrlParams urlInfo) async {
    final details = await userAdminDetailsProvider.getInfoFuture();
    final surveyUrl = _model.prePostCard.getFinalisedUrl(
      userId: userService.currentUserId,
      event: _model.event,
      email: details?.email,
      urlInfo: urlInfo,
    );

    if (surveyUrl.isNotEmpty) {
      await _helper.launchUrl(surveyUrl, kIsWeb);
    }
  }
}

@visibleForTesting
class PrePostEventDialogPresenterHelper {
  Future<void> launchUrl(String surveyUrl, bool isWeb) async {
    await launch(surveyUrl, isWeb: isWeb);
  }
}
