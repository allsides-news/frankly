import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/pre_post_survey.dart';

/// Fixed section header shown above agree/disagree survey statements.
const String kAgreeDisagreeSectionHeader =
    'Please indicate how much you AGREE or DISAGREE with the following statements.';

/// Fixed copy for residence survey questions.
const String kResidenceQuestionTitle = 'Where do you live?';
const String kResidenceQuestionSubtitle =
    'If in the U.S., please choose your state.';

/// Renders pre/post event CTA survey questions with radio button answers.
///
/// Used by the participant-facing pre/post event dialog to collect answers,
/// and in read-only mode (null selection callbacks) for the admin overview of
/// a CTA card.
class PrePostSurveyQuestionsView extends StatelessWidget {
  final List<PrePostSurveyQuestion> questions;

  /// Selected multiple choice option ID per question ID.
  final Map<String, String> selectedOptionIds;

  /// Selected agreement per statement ID, per question ID.
  final Map<String, Map<String, AgreeDisagreeAnswer>> selectedAgreements;

  final void Function(PrePostSurveyQuestion question, String optionId)?
      onOptionSelected;
  final void Function(
    PrePostSurveyQuestion question,
    PrePostSurveyItem statement,
    AgreeDisagreeAnswer answer,
  )? onAgreementSelected;

  const PrePostSurveyQuestionsView({
    Key? key,
    required this.questions,
    this.selectedOptionIds = const {},
    this.selectedAgreements = const {},
    this.onOptionSelected,
    this.onAgreementSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final question
            in questions.where((question) => question.hasData)) ...[
          if (question.type == PrePostSurveyQuestionType.multipleChoice)
            _buildMultipleChoiceQuestion(context, question)
          else if (question.type == PrePostSurveyQuestionType.agreeDisagree)
            _buildAgreeDisagreeQuestion(context, question)
          else
            _buildResidenceQuestion(context, question),
          SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildMultipleChoiceQuestion(
    BuildContext context,
    PrePostSurveyQuestion question,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeightConstrainedText(
          question.title,
          style: context.theme.textTheme.titleMedium,
        ),
        SizedBox(height: 4),
        for (final option in question.options
            .where((option) => option.text.trim().isNotEmpty))
          _buildRadioRow<String>(
            context: context,
            label: option.text,
            value: option.id,
            groupValue: selectedOptionIds[question.id],
            onChanged: onOptionSelected == null
                ? null
                : (_) => onOptionSelected!(question, option.id),
          ),
      ],
    );
  }

  Widget _buildAgreeDisagreeQuestion(
    BuildContext context,
    PrePostSurveyQuestion question,
  ) {
    final agreements = selectedAgreements[question.id] ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeightConstrainedText(
          kAgreeDisagreeSectionHeader,
          style: context.theme.textTheme.titleMedium,
        ),
        SizedBox(height: 10),
        for (final statement in question.statements
            .where((statement) => statement.text.trim().isNotEmpty)) ...[
          HeightConstrainedText(
            statement.text,
            style: context.theme.textTheme.bodyLarge,
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final answer in AgreeDisagreeAnswer.values)
                _buildRadioRow<AgreeDisagreeAnswer>(
                  context: context,
                  label: answer.text,
                  value: answer,
                  groupValue: agreements[statement.id],
                  compact: true,
                  onChanged: onAgreementSelected == null
                      ? null
                      : (_) =>
                          onAgreementSelected!(question, statement, answer),
                ),
            ],
          ),
          SizedBox(height: 14),
        ],
      ],
    );
  }

  Widget _buildResidenceQuestion(
    BuildContext context,
    PrePostSurveyQuestion question,
  ) {
    final onOptionSelectedLocal = onOptionSelected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HeightConstrainedText(
          kResidenceQuestionTitle,
          style: context.theme.textTheme.titleMedium,
        ),
        SizedBox(height: 4),
        HeightConstrainedText(
          kResidenceQuestionSubtitle,
          style: context.theme.textTheme.bodyMedium!.copyWith(
            color: context.theme.colorScheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: 10),
        // MergeSemantics + Semantics associate the question title with the
        // dropdown so screen readers announce what the control answers.
        MergeSemantics(
          child: Semantics(
            label: kResidenceQuestionTitle,
            child: Container(
              constraints: BoxConstraints(maxWidth: 340),
              decoration: BoxDecoration(
                border: Border.all(color: context.theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButton<String>(
                isExpanded: true,
                underline: SizedBox.shrink(),
                padding: EdgeInsets.symmetric(horizontal: 8),
                hint: Text(
                  'Select one',
                  style: context.theme.textTheme.bodyMedium,
                ),
                icon: Padding(
                  padding: EdgeInsets.only(right: 5),
                  child: Icon(Icons.keyboard_arrow_down, size: 24),
                ),
                value: selectedOptionIds[question.id],
                items: [
                  for (final option in ResidenceOptions.all)
                    DropdownMenuItem<String>(
                      value: option.id,
                      child: Text(
                        option.text,
                        style: context.theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
                onChanged: onOptionSelectedLocal == null
                    ? null
                    : (optionId) {
                        if (optionId != null) {
                          onOptionSelectedLocal(question, optionId);
                        }
                      },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRadioRow<T>({
    required BuildContext context,
    required String label,
    required T value,
    required T? groupValue,
    required ValueChanged<T>? onChanged,
    bool compact = false,
  }) {
    final radio = Radio<T>(
      activeColor: context.theme.colorScheme.primary,
      value: value,
      groupValue: groupValue,
      visualDensity: compact ? VisualDensity.compact : null,
      onChanged: onChanged == null
          ? null
          : (newValue) {
              if (newValue != null) onChanged(newValue);
            },
    );
    final labelText = HeightConstrainedText(
      label,
      style: context.theme.textTheme.bodyMedium,
    );

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged(value),
      child: compact
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [radio, labelText],
            )
          : Row(
              children: [radio, Expanded(child: labelText)],
            ),
    );
  }
}
