import 'package:client/styles/styles.dart';
import 'package:flutter/cupertino.dart' hide ReorderableList;
import 'package:flutter/material.dart' hide ReorderableList;
import 'package:flutter_reorderable_list/flutter_reorderable_list.dart';
import 'package:client/features/events/features/event_page/presentation/pre_post_card_widget_presenter.dart';
import 'package:client/features/events/features/event_page/presentation/views/pre_post_survey_questions_view.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/add_more_button.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/buttons/app_clickable_widget.dart';
import 'package:client/core/widgets/custom_text_field.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/pre_post_survey.dart';

/// Admin editor for the survey questions of a pre/post event CTA card.
///
/// Questions can be added (multiple choice or agree/disagree), edited,
/// deleted, and reordered via drag and drop. All state changes go through
/// [PrePostCardWidgetPresenter]; questions are persisted together with the
/// rest of the CTA card when the admin saves it.
class PrePostSurveyQuestionsEditor extends StatelessWidget {
  final List<PrePostSurveyQuestion> questions;
  final PrePostCardWidgetPresenter presenter;

  const PrePostSurveyQuestionsEditor({
    Key? key,
    required this.questions,
    required this.presenter,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ReorderableList(
      onReorder: (Key draggedKey, Key newPositionKey) =>
          presenter.reorderSurveyQuestions(draggedKey, newPositionKey),
      onReorderDone: (_) {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (questions.isNotEmpty) ...[
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final question = questions[index];
                return ReorderableItem(
                  key: Key(question.id),
                  childBuilder: (context, state) =>
                      state == ReorderableItemState.normal
                          ? _buildQuestionCard(context, question)
                          : Opacity(
                              opacity: 0.4,
                              child: _buildQuestionCard(context, question),
                            ),
                );
              },
            ),
            SizedBox(height: 20),
          ],
          AddMoreButton(
            onPressed: () => presenter
                .addSurveyQuestion(PrePostSurveyQuestionType.multipleChoice),
            label: 'Add multiple choice question',
          ),
          SizedBox(height: 10),
          AddMoreButton(
            onPressed: () => presenter
                .addSurveyQuestion(PrePostSurveyQuestionType.agreeDisagree),
            label: 'Add agree/disagree question',
          ),
          SizedBox(height: 10),
          AddMoreButton(
            onPressed: () => presenter
                .addSurveyQuestion(PrePostSurveyQuestionType.residence),
            label: 'Add "$kResidenceQuestionTitle" question',
          ),
        ],
      ),
    );
  }

  String _questionTypeLabel(PrePostSurveyQuestionType type) {
    switch (type) {
      case PrePostSurveyQuestionType.multipleChoice:
        return 'Multiple choice question';
      case PrePostSurveyQuestionType.agreeDisagree:
        return 'Agree/disagree question';
      case PrePostSurveyQuestionType.residence:
        return '"$kResidenceQuestionTitle" question';
    }
  }

  Widget _buildQuestionTypeFields(
    BuildContext context,
    PrePostSurveyQuestion question,
  ) {
    switch (question.type) {
      case PrePostSurveyQuestionType.multipleChoice:
        return _buildMultipleChoiceFields(context, question);
      case PrePostSurveyQuestionType.agreeDisagree:
        return _buildAgreeDisagreeFields(context, question);
      case PrePostSurveyQuestionType.residence:
        return _buildResidenceFields(context);
    }
  }

  Widget _buildQuestionCard(
    BuildContext context,
    PrePostSurveyQuestion question,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableListener(
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    Icons.reorder,
                    color: context.theme.colorScheme.primary,
                  ),
                ),
              ),
              Expanded(
                child: HeightConstrainedText(
                  _questionTypeLabel(question.type),
                  style: context.theme.textTheme.titleSmall,
                ),
              ),
              AppClickableWidget(
                // Gives the icon-only control an accessible name.
                tooltipMessage: 'Delete question',
                child: Icon(CupertinoIcons.delete),
                onTap: () => presenter.removeSurveyQuestion(question.id),
              ),
            ],
          ),
          SizedBox(height: 14),
          _buildQuestionTypeFields(context, question),
        ],
      ),
    );
  }

  Widget _buildResidenceFields(BuildContext context) {
    return HeightConstrainedText(
      'Participants will be asked "$kResidenceQuestionTitle" '
      '("$kResidenceQuestionSubtitle") with a dropdown of U.S. states and '
      "territories, plus an option for those who don't live in the U.S.",
      style: context.theme.textTheme.bodySmall!.copyWith(
        color: context.theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildMultipleChoiceFields(
    BuildContext context,
    PrePostSurveyQuestion question,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          key: Key('surveyQuestionTitle-${question.id}'),
          labelText: 'Enter question',
          initialValue: question.title,
          borderType: BorderType.outline,
          borderRadius: 10,
          minLines: 1,
          maxLines: 3,
          maxLength: 300,
          onChanged: (text) =>
              presenter.updateSurveyQuestionTitle(question.id, text),
          validator: (text) =>
              presenter.validateSurveyQuestionTitle(text, question.id),
        ),
        SizedBox(height: 10),
        for (var i = 0; i < question.options.length; i++) ...[
          _buildItemRow(
            context: context,
            question: question,
            item: question.options[i],
            labelText: 'Option ${i + 1}',
            isDeletable: question.options.length > 2,
          ),
          SizedBox(height: 6),
        ],
        if (question.options.length <
            PrePostSurveyQuestion.maxMultipleChoiceOptions)
          ActionButton(
            onPressed: () => presenter.addSurveyQuestionItem(question.id),
            icon: Icon(Icons.add),
            text: 'Add option',
          ),
      ],
    );
  }

  Widget _buildAgreeDisagreeFields(
    BuildContext context,
    PrePostSurveyQuestion question,
  ) {
    final answerScale = AgreeDisagreeAnswer.values
        .map((answer) => answer.text)
        .join(' / ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeightConstrainedText(
          'Statements are shown under the header "$kAgreeDisagreeSectionHeader" '
          'and participants answer each one with: $answerScale.',
          style: context.theme.textTheme.bodySmall!.copyWith(
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 14),
        for (var i = 0; i < question.statements.length; i++) ...[
          _buildItemRow(
            context: context,
            question: question,
            item: question.statements[i],
            labelText: 'Statement ${i + 1}',
            isDeletable: question.statements.length > 1,
          ),
          SizedBox(height: 6),
        ],
        if (question.statements.length <
            PrePostSurveyQuestion.maxAgreeDisagreeStatements)
          ActionButton(
            onPressed: () => presenter.addSurveyQuestionItem(question.id),
            icon: Icon(Icons.add),
            text: 'Add statement',
          ),
      ],
    );
  }

  Widget _buildItemRow({
    required BuildContext context,
    required PrePostSurveyQuestion question,
    required PrePostSurveyItem item,
    required String labelText,
    required bool isDeletable,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: CustomTextField(
            key: Key(item.id),
            labelText: labelText,
            initialValue: item.text,
            borderType: BorderType.outline,
            borderRadius: 10,
            maxLines: 1,
            maxLength: 200,
            onChanged: (text) => presenter.updateSurveyQuestionItemText(
              question.id,
              item.id,
              text,
            ),
          ),
        ),
        if (isDeletable) ...[
          SizedBox(width: 10),
          Padding(
            padding: const EdgeInsets.only(top: 25),
            child: AppClickableWidget(
              // Gives the icon-only control an accessible name, e.g.
              // "Delete option 2".
              tooltipMessage: 'Delete ${labelText.toLowerCase()}',
              child: Icon(CupertinoIcons.delete),
              onTap: () =>
                  presenter.removeSurveyQuestionItem(question.id, item.id),
            ),
          ),
        ],
      ],
    );
  }
}
