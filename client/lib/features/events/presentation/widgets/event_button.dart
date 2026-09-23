import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_picture.dart';
import 'package:client/features/community/presentation/widgets/carousel/time_indicator.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/features/events/presentation/widgets/participants_list.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/event.dart';

class EventButton extends HookWidget {
  final Event event;

  const EventButton({
    Key? key,
    required this.event,
  }) : super(key: key);

  bool get _isLiveStream => event.isLiveStream;

  Widget _buildTime(BuildContext context) {
    final scheduledTime = event.scheduledTime ?? clockService.now();

    // Fixed width so the date box takes the same space on every card,
    // regardless of how long the formatted time string happens to be
    // (e.g. "10:00a CDT" vs "8:00a CDT") -- otherwise the title next to
    // it gets a different amount of room per card. Scaled by the system
    // text scale factor so enlarged text doesn't get clipped.
    return SizedBox(
      width: MediaQuery.textScalerOf(context).scale(100),
      child: VerticalTimeAndDateIndicator(
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
        shadow: false,
        time: DateTime.fromMillisecondsSinceEpoch(
          (scheduledTime.millisecondsSinceEpoch),
        ),
      ),
    );
  }

  Widget _buildEventIcon(double size, Event localEvent) => Container(
        width: size,
        height: size,
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
        child: EventOrTemplatePicture(
          height: size,
          event: localEvent,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final localEvent = event;
    final isMobile = responsiveLayoutService.isMobile(context);

    return Card.outlined(
      margin: EdgeInsets.zero,
      color: context.theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => routerDelegate.beamTo(
          CommunityPageRoutes(
            communityDisplayId:
                CommunityProvider.readOrNull(context)?.displayId ??
                    localEvent.communityId,
          ).eventPage(
            templateId: localEvent.templateId,
            eventId: localEvent.id,
            eventTitle: localEvent.title,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              _buildTime(context),
              // On mobile the icon moves below the title (next to the
              // participants row) so the title gets the card's full width.
              if (!isMobile) ...[
                _buildEventIcon(90, localEvent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HeightConstrainedText(
                        event.title ?? 'Scheduled event',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: bumpFontSize(
                          context.theme.textTheme.titleMedium,
                          2,
                          defaultFontSize: 16,
                        ),
                      ),
                      SizedBox(height: isMobile ? 8.0 : 10.0),
                      if (_isLiveStream)
                        HeightConstrainedText(
                          'Livestream',
                          style: context.theme.textTheme.bodySmall!.copyWith(
                            color: context.theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      SizedBox(height: 10),
                      // On mobile, pair the icon with the participants row
                      // separated by a divider, so the icon doesn't get
                      // mistaken for one of the avatars sitting next to it.
                      if (isMobile)
                        Row(
                          children: [
                            _buildEventIcon(36, localEvent),
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              height: 36,
                              color: AppNeutralColors.of(context).neutral300,
                            ),
                            const SizedBox(width: 8),
                            Flexible(child: _ParticipantsList(event: event)),
                          ],
                        )
                      else
                        _ParticipantsList(event: event),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantsList extends HookWidget {
  final Event event;

  const _ParticipantsList({required this.event});

  Future<List<Participant>> _getParticipantsList() async {
    // Always fetch actual participants, even for hostless/livestream events
    // so we can show the real count to users with permission
    final participants =
        await firestoreEventService.getEventParticipants(event: event);
    final activeParticipants = participants
        .where((p) => p.status == ParticipantStatus.active)
        .toList();

    return activeParticipants;
  }

  @override
  Widget build(BuildContext context) {
    // Check if user can view participant counts
    // Hosts, facilitators, moderators, admins, and owners can all see participant counts
    final currentUserId = userService.currentUserId;

    // If user is not logged in, don't show participant counts
    if (currentUserId == null) {
      return SizedBox.shrink();
    }

    final isHost = event.creatorId == currentUserId;
    final isFacilitator =
        userDataService.getMembership(event.communityId).isFacilitator;
    final canViewCounts = isHost || isFacilitator;

    // If user doesn't have permission to view counts, don't load participant data
    if (!canViewCounts) {
      return SizedBox.shrink();
    }

    return CustomStreamBuilder<List<Participant>>(
      entryFrom: '_ParticipantsList.build',
      stream: useMemoized(() => _getParticipantsList()).asStream(),
      showLoading: false,
      builder: (_, snapshot) {
        if (snapshot == null) return SizedBox.shrink();

        // Use the actual participant count from the snapshot
        final participantCount = snapshot.length;

        final maxNumberOfParticipantsToShow =
            responsiveLayoutService.isMobile(context) ? 4 : 6;
        final numberOfParticipantsToShow =
            min(maxNumberOfParticipantsToShow, participantCount);

        // Check if current user is a participant
        final isCurrentUserParticipant =
            snapshot.any((p) => p.id == currentUserId);

        return ParticipantsList(
          key: Key('${snapshot.length}'),
          event: event,
          iconSize: 30,
          participantIds: snapshot.map((e) => e.id).toList(),
          numberOfIconsToShow: numberOfParticipantsToShow,
          showParticipantCount: canViewCounts,
          participantCount: participantCount,
          isCurrentUserParticipant: isCurrentUserParticipant,
        );
      },
    );
  }
}
