import 'dart:math';

import 'package:flutter/material.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/features/events/presentation/widgets/participants_list.dart';
import 'package:client/services.dart';
import 'package:data_models/events/event.dart';

/// This is a list of participants for a event card that relies on the event provider
class EventPageParticipantsList extends StatelessWidget {
  final Event event;
  final double? iconSize;
  final bool showFullParticipantCount;
  final bool showParticipantCount;
  final bool showGoingText;
  final bool currentUserFirst;
  final bool excludeAvatarSemantics;
  final bool allowParticipantsToViewCount;

  const EventPageParticipantsList(
    this.event, {
    Key? key,
    this.iconSize,
    this.showFullParticipantCount = true,
    this.showParticipantCount = true,
    this.showGoingText = false,
    this.currentUserFirst = true,
    this.excludeAvatarSemantics = false,
    this.allowParticipantsToViewCount = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final eventProvider = EventProvider.watch(context);

    // For users without permission to view counts, don't access the participant stream
    // to avoid permission errors. Don't show the participant list at all.
    final canShowParticipantCount = showParticipantCount ||
        (allowParticipantsToViewCount && eventProvider.isParticipant);

    if (!canShowParticipantCount) {
      return SizedBox.shrink();
    }

    // For users with permission, access the actual participant data
    // Use actualParticipantCount to get the real count from the stream
    // even for hostless/livestream events that normally use estimates
    final participantCount = eventProvider.actualParticipantCount;
    final isCurrentUserParticipant = eventProvider.isParticipant;
    final maxNumberOfParticipantsToShow =
        responsiveLayoutService.isMobile(context) ? 4 : 6;
    final numberOfParticipantsToShow =
        min(maxNumberOfParticipantsToShow, participantCount);

    return CustomStreamBuilder<List<Participant>>(
      entryFrom: 'event_participants_list.build_participants',
      stream: eventProvider.eventParticipantsStream,
      showLoading: false,
      // Users without permission to read the participant list (e.g. viewing a
      // private event before registering) get a firestore permission-denied
      // error. Show the card without the list instead of an error message.
      errorBuilder: (_) => SizedBox.shrink(),
      builder: (context, participants) {
        final activeParticipants = (participants ?? [])
            .where((e) => e.status == ParticipantStatus.active);
        return ParticipantsList(
          key: Key('${activeParticipants.length}'),
          event: event,
          participantIds: activeParticipants.map((e) => e.id).toList(),
          numberOfIconsToShow: numberOfParticipantsToShow,
          showParticipantCount: canShowParticipantCount,
          showGoingText: showGoingText,
          currentUserFirst: currentUserFirst,
          excludeAvatarSemantics: excludeAvatarSemantics,
          participantCount: participantCount,
          isCurrentUserParticipant: isCurrentUserParticipant,
        );
      },
    );
  }
}
