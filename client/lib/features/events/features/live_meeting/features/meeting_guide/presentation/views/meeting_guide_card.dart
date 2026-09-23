import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/live_meeting/presentation/views/leave_regular_dialog.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/meeting_guide_card_item_image.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_card_item_poll.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/meeting_guide_card_item_text.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_card_item_user_suggestions.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_card_item_video.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_card_item_word_cloud.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_card_contract.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/models/meeting_guide_card_model.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/meeting_guide_card_presenter.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/meeting_guide_card_tutorial.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/providers/meeting_guide_card_store.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/participant_avatar_stack.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/ready_to_advance_bar.dart';
import 'package:client/features/events/features/live_meeting/presentation/views/live_meeting_mobile_page.dart'
    show kMeetingPanelInset;
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/data/providers/meeting_agenda_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/fade_scroll_view.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/features/user/data/providers/user_info_builder.dart';
import 'package:client/app.dart';
import 'package:client/features/user/data/services/user_data_service.dart';
import 'package:client/services.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/core/utils/extensions.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/features/events/presentation/widgets/periodic_builder.dart';
import 'package:data_models/events/live_meetings/meeting_guide.dart';
import 'package:pedantic/pedantic.dart';
import 'package:provider/provider.dart';
import 'package:skeleton_text/skeleton_text.dart';

class MeetingGuideCard extends StatefulWidget {
  final void Function() onMinimizeCard;

  const MeetingGuideCard({
    Key? key,
    required this.onMinimizeCard,
  }) : super(key: key);

  @override
  _MeetingGuideCardState createState() => _MeetingGuideCardState();
}

class _MeetingGuideCardState extends State<MeetingGuideCard> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Only show tutorial is it was not shown before and if meeting is not hosted (only in hostLess).
      final canShowTutorial = !responsiveLayoutService.isMobile(context) &&
          !sharedPreferencesService.wasMeetingTutorialShown() &&
          !EventProvider.read(context).event.isHosted &&
          Provider.of<AgendaProvider>(context, listen: false).isInBreakouts &&
          !useBotControls;

      if (canShowTutorial) {
        unawaited(sharedPreferencesService.setMeetingTutorialShown(true));

        await showCustomDialog(
          context: context,
          builder: (context) => MeetingGuideTutorial(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AgendaProvider>();
    context.watch<MeetingGuideCardStore>();

    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: context.theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(ReadyToAdvanceBar.cardRadius),
          // One edge around the item and its advance rail together, so the
          // two read as a single card rather than two panels that happen to
          // touch.
          border: Border.all(
            color: AppNeutralColors.of(context).neutral300,
            width: 1,
          ),
        ),
        // Clipped so the rail's square left edge can't paint outside the
        // card's rounded corners.
        clipBehavior: Clip.antiAlias,
        child: MeetingGuideCardContent(onMinimizeCard: widget.onMinimizeCard),
      ),
    );
  }
}

class MeetingGuideCardContent extends StatefulWidget {
  final void Function() onMinimizeCard;

  /// Render only the agenda item's title row.
  ///
  /// The mobile panel retracts to a peek that has room for the handle and one
  /// line about the current item -- enough to know what the room is on without
  /// opening it. The body and the advance bar don't fit in that height and
  /// would overflow it.
  final bool isCollapsed;

  const MeetingGuideCardContent({
    Key? key,
    required this.onMinimizeCard,
    this.isCollapsed = false,
  }) : super(key: key);

  @override
  _MeetingGuideCardContentState createState() =>
      _MeetingGuideCardContentState();
}

class _MeetingGuideCardContentState extends State<MeetingGuideCardContent>
    implements MeetingGuideCardView {
  late final MeetingGuideCardModel _model;
  late final MeetingGuideCardPresenter _presenter;

  @override
  void initState() {
    super.initState();

    _model = MeetingGuideCardModel();
    _presenter = MeetingGuideCardPresenter(context, this, _model);
  }

  @override
  Widget build(BuildContext context) {
    final agendaProvider = context.watch<AgendaProvider>();
    context.watch<MeetingGuideCardStore>();

    final currentItem = _presenter.getCurrentAgendaItem();
    final isMeetingStarted = _presenter.isMeetingStarted();
    final isCardPending = _presenter.isCardPending();
    final isInBreakout = agendaProvider.isInBreakouts;
    final breakoutsActive = LiveMeetingProvider.watch(context).breakoutsActive;

    final meetingFinished = currentItem == null &&
        isMeetingStarted &&
        !isCardPending &&
        !isInBreakout &&
        !breakoutsActive;
    final canUserControlMeeting = _presenter.canUserControlMeeting;
    final isHosted = agendaProvider.event?.isHosted ?? false;

    if (meetingFinished) {
      return _buildEndCardContent();
    } else if (currentItem == null && !isInBreakout && canUserControlMeeting) {
      return _buildStartCardContent(isInControl: true);
    } else if (currentItem == null && !isInBreakout && isHosted) {
      return _buildStartCardContent(isInControl: false);
    } else {
      final agendaItem = currentItem ?? agendaProvider.getHostlessStartCard();
      return _buildAgendaItemContent(agendaItem);
    }
  }

  Widget _buildAgendaItemContent(AgendaItem? currentItem) {
    if (currentItem == null) {
      return SizedBox.shrink();
    }

    final isMobile = _presenter.isMobile(context);

    final body = Padding(
      padding: EdgeInsets.symmetric(horizontal: kMeetingPanelInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 10),
          _buildTopSection(currentItem),
          SizedBox(height: 10),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 200),
              child: _buildCardBody(currentItem),
            ),
          ),
        ],
      ),
    );

    // The advance control is a rail beside the item on desktop and a strip
    // beneath it on mobile. Both are full-bleed -- they draw their own edge
    // against the card, so they sit outside the body's horizontal padding.
    if (isMobile) {
      if (widget.isCollapsed) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: kMeetingPanelInset),
          child: _buildTopSection(currentItem),
        );
      }

      // max, not min: the panel is taller than the item on a short agenda,
      // and shrink-wrapping left the advance bar floating mid-panel instead
      // of sitting against the bottom bar.
      return Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: body),
          _buildBottomSection(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: body),
        _buildBottomSection(),
      ],
    );
  }

  Widget _buildTopSection(AgendaItem agendaItem) {
    context.watch<MeetingGuideCardStore>();

    final agendaItems = _presenter.getAgendaItems();
    final position = _presenter.getTemplateIndex(agendaItems, agendaItem);
    final title =
        '$position/${agendaItems.length} ${_presenter.getTitle(agendaItem)}';
    final isMobile = _presenter.isMobile(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMobile)
          Row(
            children: [
              Spacer(),
              ActionButton(
                type: ActionButtonType.filled,
                tooltipText: context.l10n.hideAgendaItem,
                onPressed: widget.onMinimizeCard,
                color: context.theme.colorScheme.surfaceContainerLowest,
                padding: EdgeInsets.zero,
                // Was media/minimize.png, whose colour is baked in.
                child: Icon(
                  Icons.close_fullscreen,
                  size: 20,
                  color: context.theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: HeightConstrainedText(
                title,
                style: AppTextStyle.headline4
                    .copyWith(color: context.theme.colorScheme.secondary),
              ),
            ),
            if (agendaItem.timeInSeconds != null)
              Container(
                width: 60,
                alignment: Alignment.centerRight,
                child: PeriodicBuilder(
                  period: const Duration(seconds: 1),
                  builder: (context) {
                    final timeRemaining = _presenter.getTimeRemainingInCard();
                    final bool negativeTimeRemaining;
                    final String formattedTime;
                    if (timeRemaining == null) {
                      negativeTimeRemaining = false;
                      formattedTime = context.l10n.start;
                    } else {
                      negativeTimeRemaining = timeRemaining.isNegative;
                      formattedTime =
                          timeRemaining.getFormattedTime(showHours: false);
                    }
                    return HeightConstrainedText(
                      formattedTime,
                      style: AppTextStyle.body.copyWith(
                        color: negativeTimeRemaining
                            ? context.theme.colorScheme.error
                            : context.theme.colorScheme.onSurface,
                      ),
                    );
                  },
                ),
              ),
            SizedBox(width: 10),
            // A Material icon rather than media/clock.png: a baked asset
            // can't take a colour, so it sat at low contrast on the card.
            Icon(
              Icons.schedule,
              size: 20,
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(width: 10),
          ],
        ),
      ],
    );
  }

  /// Very first card in the live meeting.
  Widget _buildStartCardContent({required bool isInControl}) {
    // Very specific flex. Less than 9 will make `Start Event` button to overflow,
    // since it won't be enough space for its rendering.
    const symmetricFlex = 9;

    context.watch<LiveMeetingProvider>();
    context.watch<AgendaProvider>();
    context.watch<UserService>();

    final userId = _presenter.getUserId();
    final isMobile = _presenter.isMobile(context);

    final minCardHeight =
        responsiveLayoutService.isMobile(context) ? 280.0 : 400.0;
    return IntrinsicHeight(
      child: Container(
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(minHeight: minCardHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Spacer(),
            Row(
              children: [
                Spacer(),
                Expanded(
                  flex: symmetricFlex,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      UserInfoBuilder(
                        userId: userId,
                        builder: (_, isLoading, info) {
                          if (isLoading) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: 0.5,
                                child: SkeletonAnimation(
                                  child: Container(
                                    color: context
                                        .theme.colorScheme.onPrimaryContainer,
                                    height: 24,
                                  ),
                                ),
                              ),
                            );
                          } else {
                            return HeightConstrainedText(
                              isNullOrEmpty(info.data?.displayName)
                                  ? context.l10n.welcome
                                  : context.l10n.welcomeName(
                                      info.data?.displayName ?? '',
                                    ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.headline3.copyWith(
                                fontSize: isMobile ? 18 : 24,
                                color: context.theme.colorScheme.primary,
                              ),
                            );
                          }
                        },
                      ),
                      SizedBox(height: 20),
                      if (isInControl) ...[
                        HeightConstrainedText(
                          context.l10n.agendaPromptReady,
                          style: AppTextStyle.subhead.copyWith(
                            fontSize: isMobile ? 15 : 18,
                            color: context.theme.colorScheme.primary,
                          ),
                        ),
                        SizedBox(height: 20),
                        ActionButton(
                          type: ActionButtonType.filled,
                          // Was surfaceContainer, which is exactly what the
                          // mobile sheet paints behind it -- the fill cancelled
                          // out and the button read as bare text.
                          color: context.theme.colorScheme.primary,
                          textColor: context.theme.colorScheme.onPrimary,
                          onPressed: () => alertOnError(context, () async {
                            final currentAgendaItemId =
                                _presenter.getCurrentAgendaItemId();
                            await _presenter.moveForward(currentAgendaItemId!);
                          }),
                          text: context.l10n.startEvent,
                        ),
                      ] else
                        HeightConstrainedText(
                          context.l10n.agendaPromptWaiting,
                          style: AppTextStyle.subhead.copyWith(
                            fontSize: isMobile ? 15 : 18,
                            color: context.theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!isMobile) ...[
                  Spacer(),
                  Expanded(
                    flex: symmetricFlex,
                    child: Icon(
                      Icons.meeting_room_rounded,
                      size: 100,
                      color: context.theme.colorScheme.secondary,
                    ),
                  ),
                ],
                Spacer(),
              ],
            ),
            Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildEndCardContent() {
    context.watch<CommunityProvider>();
    context.watch<UserDataService>();
    context.watch<LiveMeetingProvider>();

    final community = _presenter.getCommunity();
    final isMember = _presenter.isMember(community.id);

    return Column(
      children: [
        Expanded(
          child: LeaveRegularDialog(
            community: community,
            isMember: isMember,
            onMinimizeCard: widget.onMinimizeCard,
          ),
        ),
        if (_presenter.canUserControlMeeting)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: kMeetingPanelInset),
            child: _buildBottomSection(),
          ),
      ],
    );
  }

  Widget _buildCardBody(AgendaItem item) {
    final itemType = item.type;

    switch (itemType) {
      case AgendaItemType.text:
        return FadeScrollView(
          child: MeetingGuideCardItemText(agendaItem: item),
        );
      case AgendaItemType.video:
        return MeetingGuideCardItemVideo();
      case AgendaItemType.image:
        return FadeScrollView(
          maxFadeExtent: 0,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: MeetingGuideCardItemImage(agendaItem: item),
          ),
        );
      case AgendaItemType.poll:
        return FadeScrollView(
          child: MeetingGuideCardItemPoll(),
        );
      case AgendaItemType.wordCloud:
        return MeetingGuideCardItemWordCloud();
      case AgendaItemType.userSuggestions:
        return MeetingGuideCardItemUserSuggestions();
    }
  }

  Widget _buildBottomSection() {
    context.watch<AgendaProvider>();
    context.watch<MeetingGuideCardStore>();

    // Kept inside the rail/strip: returning a bare widget here collapsed the
    // desktop rail to nothing, so re-entering an event that had gone back to
    // pending lost the advance control entirely.
    final isCardPending = _presenter.isCardPending();
    if (isCardPending) {
      return ReadyToAdvanceBar.shell(
        isMobile: _presenter.isMobile(context),
        child: CountdownWidget(),
      );
    }

    context.watch<LiveMeetingProvider>();
    context.watch<UserService>();
    context.watch<CommunityProvider>();
    context.watch<UserDataService>();
    context.watch<MeetingGuideCardStore>();

    final participantAgendaItemDetailsStream =
        _presenter.getParticipantAgendaItemDetailsStream();

    return CustomStreamBuilder<List<ParticipantAgendaItemDetails>>(
      entryFrom: '_MeetingGuideCard._buildBottomSection',
      stream: participantAgendaItemDetailsStream,
      height: 100,
      builder: (context, participantAgendaItemDetailsList) {
        final readyToAdvance =
            _presenter.isReadyToAdvance(participantAgendaItemDetailsList);
        final canUserControlMeeting = _presenter.canUserControlMeeting;
        final currentAgendaItemId = _presenter.getCurrentAgendaItemId();
        final currentItem = _presenter.getCurrentAgendaItem();
        final presentParticipantIds =
            _presenter.getPresentParticipantIds().toSet();
        final isMeetingStarted = _presenter.isMeetingStarted();
        final isCardPending = _presenter.isCardPending();
        final watchedAgendaProvider = context.watch<AgendaProvider>();
        final isInBreakout = watchedAgendaProvider.isInBreakouts;
        final breakoutsActive =
            LiveMeetingProvider.watch(context).breakoutsActive;
        final meetingFinished = currentItem == null &&
            isMeetingStarted &&
            !isCardPending &&
            !isInBreakout &&
            !breakoutsActive;
        final isHosted = _presenter.isHosted();

        final isMobile = _presenter.isMobile(context);

        if (isHosted) {
          if (!canUserControlMeeting) return SizedBox.shrink();
          if (meetingFinished) return const SizedBox.shrink();

          // No tally: a host advances the room rather than waiting on a
          // vote, so the count would be information they can't act on.
          return ReadyToAdvanceBar(
            participants: const [],
            hasVoted: false,
            isHost: true,
            showBackButton: _presenter.isBackButtonShown(),
            isMobile: isMobile,
            onBack: () => _presenter.goToPreviousAgendaItem(),
            onNext: () => alertOnError(context, () async {
              await AgendaProvider.read(context).moveForward(
                currentAgendaItemId: currentAgendaItemId ?? '',
              );
            }),
          );
        } else {
          // Once the breakout meeting has a finishMeeting event the
          // server-side CheckAdvanceMeetingGuide returns early without
          // writing readyToAdvance, so the button can never dismiss itself.
          //
          // Say so rather than showing nothing. A hostless event is always in
          // a breakout, so the `meetingFinished` branch above is never true
          // for one and the end card never runs -- finishing the last item
          // just removed the control and left no sign anything had happened.
          if (watchedAgendaProvider.isMeetingFinished) {
            return ReadyToAdvanceBar.shell(
              isMobile: isMobile,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 16,
                    color: context.theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: HeightConstrainedText(
                      'Agenda complete',
                      style: context.theme.textTheme.bodyMedium?.copyWith(
                        color: context.theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Ready first, then stable by id, so a vote arriving doesn't
          // reshuffle the faces.
          final readyIds = (participantAgendaItemDetailsList ?? [])
              .where((p) => p.readyToAdvance ?? false)
              .map((p) => p.userId)
              .toSet();
          final participants = presentParticipantIds
              .map(
                (id) => ParticipantReadiness(
                  userId: id,
                  isReady: readyIds.contains(id),
                ),
              )
              .toList()
            ..sort((a, b) {
              if (a.isReady != b.isReady) return a.isReady ? -1 : 1;
              return a.userId.compareTo(b.userId);
            });

          return ReadyToAdvanceBar(
            participants: participants,
            hasVoted: readyToAdvance,
            isHost: false,
            showBackButton: false,
            isMobile: isMobile,
            onBack: null,
            onNext: () => alertOnError(context, () async {
              await AgendaProvider.read(context).moveForward(
                currentAgendaItemId: currentAgendaItemId ?? '',
              );
            }),
          );
        }
      },
    );
  }

  @override
  void updateView() {
    setState(() {});
  }
}

class CountdownWidget extends StatelessWidget {
  const CountdownWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return PeriodicBuilder(
      period: Duration(seconds: 1),
      builder: (context) {
        final countdownSeconds = 3 -
            Provider.of<MeetingGuideCardStore>(context)
                .pendingMeetingGuideAgendaItemElapsed
                .elapsed
                .inSeconds;
        final isMobile = responsiveLayoutService.isMobile(context);
        return Row(
          children: [
            if (!isMobile) ...[
              Expanded(
                child: HeightConstrainedText(
                  'Moving to the next agenda item...',
                  style: AppTextStyle.subhead.copyWith(
                    color: context.theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              SizedBox(width: 10),
            ],
            HeightConstrainedText(
              math.max(1, countdownSeconds).toString(),
              style: TextStyle(
                fontSize: isMobile ? 24 : 38,
                color: context.theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        );
      },
    );
  }
}


/// The "Ready to move on?" control replacing the old "Next" button. Before
/// voting it's a clickable pill; after voting it becomes plain, non-tappable
/// "Ready" text -- per the redesign, it has no cursor interaction once
/// checked. (No undo here -- once you vote there's no way back, same
/// limitation as the button it replaces.)
