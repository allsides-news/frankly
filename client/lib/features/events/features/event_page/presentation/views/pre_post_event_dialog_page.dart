import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/features/community/data/providers/user_admin_details_builder.dart';
import 'package:client/features/events/features/event_page/presentation/views/pre_post_survey_questions_view.dart';
import 'package:client/services.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/widgets/html_content.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/pre_post_card.dart';
import 'package:data_models/events/pre_post_url_params.dart';

import 'pre_post_event_dialog_contract.dart';
import '../../data/models/pre_post_event_dialog_model.dart';
import '../pre_post_event_dialog_presenter.dart';

class PrePostEventDialogPage extends StatefulWidget {
  final PrePostCard prePostCard;
  final Event event;
  final bool showSurveyQuestions;

  const PrePostEventDialogPage._({
    Key? key,
    required this.prePostCard,
    required this.event,
    required this.showSurveyQuestions,
  }) : super(key: key);

  static Future<void> show({
    required PrePostCard prePostCardData,
    required Event event,
  }) async {
    // Only prompt for the survey if this user hasn't already submitted
    // answers for this card (e.g. they answered when they registered and are
    // now re-opening the event). If the lookup fails, prompt again - an extra
    // prompt is better than silently losing required answers.
    bool hasExistingResponse = false;
    if (prePostCardData.hasSurveyQuestions) {
      hasExistingResponse = await swallowErrors(
            () => firestoreEventService.hasPrePostSurveyResponse(
              event: event,
              prePostCardType: prePostCardData.type,
            ),
          ) ??
          false;
    }
    final showSurveyQuestions =
        prePostCardData.hasSurveyQuestions && !hasExistingResponse;

    await showCustomDialog(
      // Answering configured survey questions is required, so don't allow
      // dismissing the dialog by tapping the barrier.
      isDismissible: !showSurveyQuestions,
      builder: (context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: PrePostEventDialogPage._(
            prePostCard: prePostCardData,
            event: event,
            showSurveyQuestions: showSurveyQuestions,
          ),
        );
      },
    );
  }

  @override
  _PrePostEventDialogPageState createState() => _PrePostEventDialogPageState();
}

class _PrePostEventDialogPageState extends State<PrePostEventDialogPage>
    implements PrePostEventDialogView {
  late final PrePostEventDialogModel _model;
  late final PrePostEventDialogPresenter _presenter;

  @override
  void initState() {
    super.initState();
    _model = PrePostEventDialogModel(
      widget.prePostCard,
      widget.event,
      showSurveyQuestions: widget.showSurveyQuestions,
    );
    _presenter = PrePostEventDialogPresenter(
      this,
      _model,
      userAdminDetailsProvider:
          UserAdminDetailsProvider.forUser(userService.currentUserId!),
    )..initialize();
  }

  @override
  void updateView() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bool isMobile = _presenter.isMobile(context);
    final overallPaddingSize = _presenter.getSize(context, 40, scale: 0.5);
    final iconPaddingSize = _presenter.getSize(context, 0);
    final iconSize = _presenter.getSize(context, 32);
    final maxWidth = _presenter.getSize(context, 700);
    final surveyQuestions = _presenter.surveyQuestions;

    return PopScope(
      canPop: _presenter.canDismiss,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        // The dialog grows vertically with its content and stays centered. If
        // the content exceeds the viewport height it becomes scrollable.
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.all(overallPaddingSize),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Also shown after a failed survey save (canDismiss becomes
                // true) so the participant always has a way out of the dialog.
                if (_presenter.canDismiss)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      CustomInkWell(
                        onTap: () => Navigator.pop(context),
                        boxShape: BoxShape.circle,
                        child: Padding(
                          padding: EdgeInsets.all(iconPaddingSize),
                          child: Icon(
                            Icons.close,
                            size: iconSize,
                            color: context.theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                HeightConstrainedText(
                  _model.prePostCard.headline,
                  style: context.theme.textTheme.titleLarge,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 10),
                HtmlContent(
                  _model.prePostCard.message,
                  style: context.theme.textTheme.titleSmall,
                ),
                SizedBox(height: 10),
                if (surveyQuestions.isNotEmpty) ...[
                  SizedBox(height: 10),
                  PrePostSurveyQuestionsView(
                    questions: surveyQuestions,
                    selectedOptionIds: _model.selectedOptionIds,
                    selectedAgreements: _model.selectedAgreements,
                    onOptionSelected: (question, optionId) =>
                        _presenter.selectSurveyOption(question, optionId),
                    onAgreementSelected: (question, statement, answer) =>
                        _presenter.selectSurveyAgreement(
                      question,
                      statement,
                      answer,
                    ),
                  ),
                ],
                _buildBottomSection(isMobile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isNextEnabled =>
      !_model.isSubmittingSurvey &&
      (!_presenter.isSurveyRequired || _presenter.isSurveyComplete);

  /// Saves survey answers (when a survey is configured) before closing the
  /// dialog so participants can move on.
  Future<void> _onNextPressed() async {
    if (_presenter.isSurveyRequired) {
      await alertOnError(context, () => _presenter.submitSurvey());
      // Stay open after a failed save so the participant can retry; a close
      // icon and back navigation become available so they aren't trapped.
      if (!_presenter.isSurveySubmitted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _buildBottomSection(bool isMobile) {
    final hasUrls = _model.prePostCard.prePostUrls.isNotEmpty;
    if (isMobile) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasUrls) ...[
              for (int i = 0;
                  i < _model.prePostCard.prePostUrls.length;
                  i++) ...[
                SizedBox(height: 8),
                _buildSurveyButtonWidget(_model.prePostCard.prePostUrls[i]),
              ],
              SizedBox(height: 8),
              _buildNotNowWidget(),
            ] else
              _buildNextButton(),
          ],
        ),
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (hasUrls) ...[
            _buildNotNowWidget(),
            SizedBox(width: 30),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                runSpacing: 8,
                spacing: 8,
                children: [
                  for (final url in _model.prePostCard.prePostUrls)
                    _buildSurveyButtonWidget(url),
                ],
              ),
            ),
          ] else ...[
            SizedBox.shrink(),
            _buildNextButton(),
          ],
        ],
      );
    }
  }

  Widget _buildNotNowWidget() {
    return ActionButton(
      type: ActionButtonType.outline,
      text: 'Next',
      onPressed: _isNextEnabled ? () => _onNextPressed() : null,
    );
  }

  Widget _buildSurveyButtonWidget(PrePostUrlParams urlParams) {
    final buttonText = urlParams.buttonText;
    final buttonTextNotEmpty = buttonText != null && buttonText.isNotEmpty;
    return ActionButton(
      color: context.theme.colorScheme.primary,
      type: ActionButtonType.filled,
      text: buttonTextNotEmpty ? buttonText : 'Open Link',
      onPressed: () =>
          alertOnError(context, () => _presenter.launchSurvey(urlParams)),
    );
  }

  Widget _buildNextButton() {
    return ActionButton(
      onPressed: _isNextEnabled ? () => _onNextPressed() : null,
      text: 'Next',
    );
  }
}
