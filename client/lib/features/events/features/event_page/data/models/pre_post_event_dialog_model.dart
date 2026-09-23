import 'package:data_models/events/event.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/events/pre_post_survey.dart';

class PrePostEventDialogModel {
  final PrePostCard prePostCard;
  final Event event;

  /// Whether to prompt for configured survey questions. False when the user
  /// has already submitted answers for this card.
  final bool showSurveyQuestions;

  /// Selected multiple choice option ID per survey question ID.
  final Map<String, String> selectedOptionIds = {};

  /// Selected agreement per statement ID, per survey question ID.
  final Map<String, Map<String, AgreeDisagreeAnswer>> selectedAgreements = {};

  bool isSubmittingSurvey = false;
  bool isSurveySubmitted = false;

  /// Set once a save attempt fails so the dialog becomes dismissible and the
  /// participant is never trapped by persistent network/permission errors.
  bool surveySubmitFailed = false;

  PrePostEventDialogModel(
    this.prePostCard,
    this.event, {
    this.showSurveyQuestions = true,
  });
}
