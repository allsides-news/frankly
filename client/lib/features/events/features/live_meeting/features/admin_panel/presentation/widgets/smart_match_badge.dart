import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:collection/collection.dart';
import 'package:data_models/events/event.dart';
import 'package:flutter/material.dart';

/// One color per answer-group index. Supports up to 6 distinct groups;
/// any group beyond index 5 falls back to grey.
const _dotPalette = [
  Color(0xFF4A90D9), // 0 — blue
  Color(0xFFE8854A), // 1 — orange
  Color(0xFF5AAB5A), // 2 — green
  Color(0xFF9B59B6), // 3 — purple
  Color(0xFFE74C3C), // 4 — red
  Color(0xFF1ABC9C), // 5 — teal
];

// Top-level, so no BuildContext to resolve a brightness-aware shade against.
// It sits alongside the fixed _dotPalette above, which doesn't flip either.
Color _dotColorForGroupIndex(int index) => index < _dotPalette.length
    ? _dotPalette[index]
    : AppNeutralColors.neutral400;

/// Returns the selected answer-group index (0-based) for each question.
/// Unlike the binary answer mask used by the matching algorithm, this
/// preserves the full group index so multi-option questions get distinct colors.
List<int> _computeAnswerGroupIndices(List<BreakoutQuestion> questions) {
  return questions.map((q) {
    final index = q.answers.indexWhere(
      (answer) => answer.options.any((opt) => opt.id == q.answerOptionId),
    );
    return index < 0 ? 0 : index;
  }).toList();
}

/// Displays a compact Smart Match classification badge showing a participant's
/// survey-response pattern as colored dots.
///
/// Each dot represents one survey question. The dot color corresponds to the
/// answer group the participant selected: blue = group 0, orange = group 1,
/// green = group 2, purple = group 3, etc. Questions with more than 2 answer
/// groups get distinct dot colors for each group.
///
/// Hover/long-press the badge to see the full human-readable survey answers.
class SmartMatchBadge extends StatelessWidget {
  final List<BreakoutQuestion> questions;

  const SmartMatchBadge({Key? key, required this.questions}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) return const SizedBox.shrink();

    final groupIndices = _computeAnswerGroupIndices(questions);

    final tooltipLines = [
      'Smart Match Survey:',
      for (final q in questions)
        () {
          final selected = q.answers
              .expand((a) => a.options)
              .firstWhereOrNull((opt) => opt.id == q.answerOptionId);
          return '• ${q.title}: ${selected?.title ?? '?'}';
        }(),
    ];

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppNeutralColors.of(context).neutral400.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Smart Match',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: AppNeutralColors.of(context).neutral500,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 4),
            ...groupIndices.map(
              (groupIndex) => Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _dotColorForGroupIndex(groupIndex),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fetches a participant's survey data from Firestore and renders a
/// [SmartMatchBadge]. Use this when you only have a userId (e.g. in the
/// breakout room details view).
///
/// Automatically hides itself when the event is not using Smart Match.
class SmartMatchBadgeForUser extends StatelessWidget {
  final String userId;

  const SmartMatchBadgeForUser({Key? key, required this.userId})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final event = EventProvider.watch(context).event;

    if (event.breakoutRoomDefinition?.assignmentMethod !=
        BreakoutAssignmentMethod.smartMatch) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<Participant>(
      stream: firestoreEventService.eventParticipantStream(
        communityId: event.communityId,
        templateId: event.templateId,
        eventId: event.id,
        userId: userId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final participant = snapshot.data;
        if (participant == null) return const SizedBox.shrink();
        return SmartMatchBadge(
          questions: participant.breakoutRoomSurveyQuestions,
        );
      },
    );
  }
}
