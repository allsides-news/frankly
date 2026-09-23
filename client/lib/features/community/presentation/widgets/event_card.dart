import 'package:client/features/templates/presentation/widgets/prerequisite_badge.dart';
import 'package:flutter/material.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_picture.dart';
import 'package:client/features/community/presentation/widgets/carousel/time_indicator.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/features/events/presentation/widgets/event_participants_list.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/core/routing/locations.dart';
import 'package:client/features/user/data/services/user_data_service.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/event.dart';
import 'package:provider/provider.dart';

/// This is the card for the upcoming events shown on the Home page.
///
/// Tapping on it navigates to the event page.
class EventCard extends StatelessWidget {
  final Event event;

  const EventCard(
    this.event, {
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ChangeNotifierProvider(
        create: (context) => EventProvider(
          communityProvider: context.read<CommunityProvider>(),
          templateId: event.templateId,
          eventId: event.id,
        )..initialize(),
        child: Builder(
          builder: (context) {
            final eventProvider = EventProvider.watch(context);
            return CustomStreamBuilder<bool>(
              entryFrom: 'event_card.build_event',
              stream: eventProvider.hasParticipantAttendedPrerequisiteFuture
                  .asStream(),
              builder: (_, __) {
                return CustomStreamBuilder<Event>(
                  entryFrom: 'event_card.build_event',
                  stream: eventProvider.eventStream,
                  builder: (context, _) {
                    final isAdmin = Provider.of<UserDataService>(context)
                        .getMembership(
                          Provider.of<CommunityProvider>(context).communityId,
                        )
                        .isAdmin;

                    final hasPrerequisiteTemplate =
                        eventProvider.event.prerequisiteTemplateId != null;

                    final isDisabled = hasPrerequisiteTemplate &&
                        !eventProvider.hasAttendedPrerequisite &&
                        !isAdmin;
                    return MergeSemantics(
                      child: _EventCardInkWell(
                        isDisabled: isDisabled,
                        onTap: isDisabled
                            ? null
                            : () => routerDelegate.beamTo(
                                  CommunityPageRoutes(
                                    communityDisplayId:
                                        CommunityProvider.readOrNull(context)
                                                ?.displayId ??
                                            event.communityId,
                                  ).eventPage(
                                    templateId: event.templateId,
                                    eventId: event.id,
                                    eventTitle: event.title,
                                  ),
                                ),
                        child: Stack(
                          children: [
                            _buildCardContent(
                              context: context,
                              isDisabled: isDisabled,
                            ),
                            if (eventProvider.isParticipant)
                              Positioned(
                                top: 0,
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 6,
                                  color: AppNeutralColors.of(context).neutral800,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEventIcon({required double size, required bool isDisabled}) =>
      Stack(
        children: [
          Container(
            width: size,
            height: size,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              // Matches the image's own radius so the two don't disagree.
              borderRadius:
                  BorderRadius.circular(size * AppSize.kEventImageRadiusRatio),
            ),
            child: EventOrTemplatePicture(
              key: Key(event.id),
              event: event,
              height: size,
            ),
          ),
          if (isDisabled) SizedBox(width: size, height: size),
        ],
      );

  /// On mobile, pairs the event icon with [child] (e.g. the participants
  /// row) separated by a divider, so the icon doesn't get mistaken for one
  /// of the participant avatars sitting right next to it.
  Widget _buildMobileIconRow(
    BuildContext context, {
    required bool isDisabled,
    required Widget child,
  }) =>
      Row(
        children: [
          _buildEventIcon(size: 36, isDisabled: isDisabled),
          const SizedBox(width: 8),
          Container(
            width: 1,
            height: 36,
            color: AppNeutralColors.of(context).neutral300,
          ),
          const SizedBox(width: 8),
          Flexible(child: child),
        ],
      );

  Widget _buildParticipantsRow(BuildContext context) {
    final isMod = Provider.of<UserDataService>(context)
        .getMembership(
          Provider.of<CommunityProvider>(context).communityId,
        )
        .isMod;
    final canViewCounts = isMod ||
        Provider.of<CommunityProvider>(context)
            .settings
            .showAttendeeCountToNonAdmins;
    return EventPageParticipantsList(
      event,
      iconSize: 30,
      showFullParticipantCount: true,
      showParticipantCount: canViewCounts,
    );
  }

  Widget _buildCardContent({
    required BuildContext context,
    required bool isDisabled,
  }) {
    final isMobile = responsiveLayoutService.isMobile(context);

    final title = HeightConstrainedText(
      event.title ?? 'Scheduled event',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: bumpFontSize(
        context.theme.textTheme.titleMedium,
        2,
        defaultFontSize: 16,
      )!.copyWith(
        color: isDisabled
            ? context.theme.colorScheme.onSurface.withOpacity(0.75)
            : context.theme.colorScheme.onSurface,
      ),
    );

    return Container(
      padding: EdgeInsets.all(8.0),
      child: Row(
        children: [
          // Fixed width so the date box takes the same space on every card,
          // regardless of how long the formatted time string happens to be
          // (e.g. "10:00a CDT" vs "8:00a CDT") -- otherwise the title next
          // to it gets a different amount of room per card. Scaled by the
          // system text scale factor so enlarged text doesn't get clipped.
          SizedBox(
            width: MediaQuery.textScalerOf(context).scale(100),
            child: event.scheduledTime != null
                ? VerticalTimeAndDateIndicator(
                    shadow: false,
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                    isDisabled: isDisabled,
                    time: DateTime.fromMillisecondsSinceEpoch(
                      (event.scheduledTime?.millisecondsSinceEpoch ?? 0),
                    ),
                  )
                : null,
          ),
          // On mobile the icon moves below the title (next to the
          // participants row) so the title gets the card's full width.
          if (!isMobile) ...[
            _buildEventIcon(size: 90, isDisabled: isDisabled),
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
                  title,
                  SizedBox(height: isMobile ? 10.0 : 20.0),
                  if (isDisabled)
                    isMobile
                        ? _buildMobileIconRow(
                            context,
                            isDisabled: true,
                            child: PrerequisiteBadge(
                              textStyle: context.theme.textTheme.labelMedium,
                            ),
                          )
                        : PrerequisiteBadge(
                            textStyle: context.theme.textTheme.labelMedium,
                          )
                  else ...[
                    if (event.isLiveStream)
                      HeightConstrainedText(
                        'Livestream',
                        style: context.theme.textTheme.bodySmall!.copyWith(
                          color: context.theme.colorScheme.onSurface
                              .withOpacity(0.75),
                        ),
                      ),
                    if (isMobile)
                      _buildMobileIconRow(
                        context,
                        isDisabled: false,
                        child: _buildParticipantsRow(context),
                      )
                    else
                      _buildParticipantsRow(context),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps the event card in an ink well whose hover state is painted as the
/// card's own background (behind [child]), not as a layer on top of it.
class _EventCardInkWell extends StatefulWidget {
  final VoidCallback? onTap;
  final bool isDisabled;
  final Widget child;

  const _EventCardInkWell({
    required this.onTap,
    required this.isDisabled,
    required this.child,
  });

  @override
  State<_EventCardInkWell> createState() => _EventCardInkWellState();
}

class _EventCardInkWellState extends State<_EventCardInkWell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return CustomInkWell(
      borderRadius: BorderRadius.circular(10),
      // Hover feedback is painted as the Card's own background below
      // instead, so suppress CustomInkWell's own default overlay (which
      // would otherwise paint on top of the card content).
      hoverColor: Colors.transparent,
      onHover: (hovering) => setState(() => _isHovered = hovering),
      onTap: widget.onTap,
      child: Card.outlined(
        margin: EdgeInsets.zero,
        color: _isHovered
            ? AppNeutralColors.of(context).neutral200
            : widget.isDisabled
                ? context.theme.colorScheme.surfaceContainer
                : context.theme.colorScheme.surfaceContainerLowest,
        clipBehavior: Clip.hardEdge,
        child: widget.child,
      ),
    );
  }
}
