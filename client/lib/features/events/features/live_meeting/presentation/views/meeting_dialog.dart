import 'dart:async';

import 'package:beamer/beamer.dart';
import 'package:client/core/utils/toast_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:client/features/events/features/live_meeting/features/av_check/presentation/views/av_check.dart';
import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_tabs.dart';
import 'package:client/features/events/features/live_meeting/presentation/widgets/live_meeting_desktop.dart';
import 'package:client/features/events/features/live_meeting/presentation/views/live_meeting_mobile_page.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/providers/meeting_guide_card_store.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/conference_room.dart';
import 'package:client/features/events/features/live_meeting/data/providers/use_kick_proposal_listeners.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/presentation/widgets/meeting_agenda.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/data/providers/meeting_agenda_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/core/widgets/navbar/nav_bar_provider.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/utils/persistent_f_toast_utils.dart';
import 'package:client/core/utils/platform_utils.dart' as platform_utils;
import 'package:client/styles/app_asset.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:provider/provider.dart';

class MeetingDialog extends StatefulWidget {
  static const enterMeetingPromptButton = Key('enter-meeting-prompt');

  const MeetingDialog._();

  static Widget create({
    bool isInstant = false,
    BeamLocation? leaveLocation,
    Function()? onLeave,
    bool avCheckEnabled = false,
  }) {
    // Stateful gate: the AV check -> meeting swap must not depend on an
    // ambient rebuild. It used to ride on updateQueryParameterToJoinEvent
    // notifying Beamer, but that is a no-op when status=joined is already in
    // the URL (guard added to stop join remount crashes), which left Join
    // doing nothing until some unrelated stream rebuilt the page.
    return _AvCheckGate(
      isInstant: isInstant,
      leaveLocation: leaveLocation,
      onLeave: onLeave,
      avCheckEnabled: avCheckEnabled,
    );
  }

  static Widget _createMeeting({
    required bool isInstant,
    BeamLocation? leaveLocation,
    Function()? onLeave,
  }) {
    return ChangeNotifierProvider(
      create: (context) {
        // `create`'s context is the InheritedProviderScope itself, so
        // LiveMeetingProvider.read(context) cannot see this provider.
        // Capture the instance instead of looking it up later.
        LiveMeetingProvider? provider;
        provider = LiveMeetingProvider(
          communityProvider: CommunityProvider.read(context),
          eventProvider: EventProvider.read(context),
          navBarProvider: Provider.of<NavBarProvider>(context, listen: false),
          isInstant: isInstant,
          leaveLocation: leaveLocation,
          onLeave: onLeave,
          showToast: (String message, {bool? hideOnMobile}) {
            final hideToast = hideOnMobile == true &&
                responsiveLayoutService.isMobile(context);
            if (!hideToast) {
              final isWaitingRoomNotification = message
                      .toLowerCase()
                      .contains('waiting in the waiting room') ||
                  message.toLowerCase().contains('in a waiting room');

              if (isWaitingRoomNotification) {
                PersistentFToast.show(
                  context,
                  message,
                  backgroundColor: Colors.red,
                  textColor: Colors.white,
                  onDismiss: () {
                    provider?.markWaitingRoomNotificationDismissed();
                  },
                );
              } else {
                return showRegularToast(
                  context,
                  message,
                  toastType: ToastType.success,
                );
              }
            }
          },
        );
        return provider;
      },
      child: MeetingDialog._(),
    );
  }

  @override
  _MeetingDialogState createState() => _MeetingDialogState();
}

/// Shows the AV check until the user completes it, then swaps to the meeting
/// in the same element (no router round-trip required).
class _AvCheckGate extends StatefulWidget {
  const _AvCheckGate({
    required this.isInstant,
    required this.leaveLocation,
    required this.onLeave,
    required this.avCheckEnabled,
  });

  final bool isInstant;
  final BeamLocation? leaveLocation;
  final Function()? onLeave;
  final bool avCheckEnabled;

  @override
  State<_AvCheckGate> createState() => _AvCheckGateState();
}

class _AvCheckGateState extends State<_AvCheckGate> {
  @override
  Widget build(BuildContext context) {
    if (widget.avCheckEnabled &&
        !sharedPreferencesService.getAvCheckComplete()) {
      return AvCheckPage(
        onLeave: widget.onLeave,
        leaveLocation: widget.leaveLocation,
        // joinNowPressed persists the AV choices; this re-runs the check
        // above, which now passes.
        onComplete: () {
          if (mounted) setState(() {});
        },
      );
    }
    return MeetingDialog._createMeeting(
      isInstant: widget.isInstant,
      leaveLocation: widget.leaveLocation,
      onLeave: widget.onLeave,
    );
  }
}

class _MeetingDialogState extends State<MeetingDialog> {
  LiveMeetingProvider get liveMeetingProvider =>
      Provider.of<LiveMeetingProvider>(context);

  EventProvider get eventProvider => Provider.of<EventProvider>(context);

  @override
  void initState() {
    super.initState();
    dialogProvider.isOnIframePage = true;
    final liveMeetingProvider = context.read<LiveMeetingProvider>();
    liveMeetingProvider.initialize();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      liveMeetingProvider.setBreakoutRoomHelpNotificationContext(context);
      _checkBrowserCompatibility();
    });
  }

  void _checkBrowserCompatibility() async {
    final result = platform_utils.checkBrowserCompatibility();
    if (!result.isCompatible && result.message != null) {
      // Delay to avoid overlapping with camera/mic permission dialogs
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return;
      final fToast = FToast().init(context);
      fToast.showToast(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.0),
            color: Colors.amber.shade800,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SvgPicture.asset(
                AppAsset.kExclamationSvg.path,
                color: Colors.white,
                width: 20,
                height: 20,
              ),
              SizedBox(width: 10),
              Flexible(
                child: Text(
                  result.message!,
                  style: AppTextStyle.subhead.copyWith(color: Colors.white),
                ),
              ),
              SizedBox(width: 10),
              IconButton(
                onPressed: () => fToast.removeCustomToast(),
                tooltip: 'Dismiss browser compatibility warning',
                icon: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        toastDuration: Duration(seconds: 10),
        positionedToastBuilder: (context, child) {
          return Positioned(
            top: 16.0,
            left: 24.0,
            right: 24.0,
            child: child,
          );
        },
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
    dialogProvider.isOnIframePage = false;
  }

  Widget _buildVideoLayout() {
    final liveMeetingKey = ObjectKey(ConferenceRoom.read(context));
    if (responsiveLayoutService.isMobile(context)) {
      return LiveMeetingMobilePage(key: liveMeetingKey);
    }
    return LiveMeetingDesktopLayout(key: liveMeetingKey);
  }

  Widget _buildConferenceRoomWrapper({
    required Widget child,
  }) {
    return HookBuilder(
      builder: (context) {
        useKickProposalListeners(context);

        // Load meeting if necessary, otherwise return child
        final liveMeetingProvider = LiveMeetingProvider.watch(context);

        if (liveMeetingProvider.leftMeeting) {
          return child;
        }

        // Look up correct future
        Future<GetMeetingJoinInfoResponse>? loadingFuture =
            liveMeetingProvider.getCurrentMeetingJoinInfo();
        if (loadingFuture == null) {
          return child;
        }

        return CustomStreamBuilder<GetMeetingJoinInfoResponse>(
          entryFrom: '_buildConferenceRoomWrapper.build',
          key: ObjectKey(loadingFuture),
          stream: loadingFuture.asStream(),
          errorBuilder: (context) => Container(
            padding: const EdgeInsets.all(12),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                HeightConstrainedText(
                  'There was an error connecting to the room.',
                ),
                SizedBox(height: 24),
                ActionButton(
                  text: 'Reload',
                  onPressed: () => liveMeetingProvider.refreshMeeting(),
                ),
              ],
            ),
          ),
          loadingMessage: 'Loading room. Please wait...',
          buildWhileLoading: true,
          builder: (_, response) {
            if (response == null) {
              return child;
            }

            // We need to call getCurrentJoinInfo above for the waiting room so that the users
            // presence will be updated to the waiting room. Without this, the user will not show
            // up in the list of people in the waiting room. We don't want to load a conference room
            // for them however.
            if (liveMeetingProvider.currentBreakoutRoomId ==
                breakoutsWaitingRoomId) {
              return child;
            }

            return ChangeNotifierProvider(
              create: (context) => ConferenceRoom(
                liveMeetingProvider: liveMeetingProvider,
                agendaProvider: AgendaProvider.read(context),
                communityProvider: CommunityProvider.read(context),
                meetingGuideCardModel: MeetingGuideCardStore.read(context)!,
                roomName: response.meetingId,
                token: response.meetingToken,
                screenShareToken: response.screenShareToken,
              )..initialize(context),
              builder: (_, __) => child,
            );
          },
        );
      },
    );
  }

  Widget _buildAgendaWrapper(BuildContext context) {
    final eventProvider = Provider.of<EventProvider>(context);
    final event = eventProvider.eventOrNull;
    if (event == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final permissions = Provider.of<EventPermissionsProvider>(context);

    return MeetingAgendaWrapper(
      communityId: eventProvider.communityId,
      event: event,
      labelColor: Colors.white60,
      child: Builder(
        builder: (context) {
          final liveMeetingProvider = LiveMeetingProvider.watch(context);

          final agendaProvider = Provider.of<AgendaProvider>(context);
          final communityProvider = CommunityProvider.watch(context);

          final bool enableGuide = (eventProvider.agendaPreview ||
              context
                  .watch<EventPermissionsProvider>()
                  .isAgendaVisibleOverride ||
              liveMeetingProvider.isInBreakout);

          return ChangeNotifierProvider(
            key: Key(agendaProvider.liveMeetingPath),
            create: (context) => MeetingGuideCardStore(
              communityProvider: communityProvider,
              liveMeetingProvider: liveMeetingProvider,
              agendaProvider: agendaProvider,
              showToast: (String message) => showRegularToast(
                context,
                message,
                toastType: ToastType.success,
              ),
            )..initialize(),
            child: EventTabsWrapper(
              meetingAgendaBuilder: (context) => MeetingAgenda(
                canUserEditAgenda:
                    context.watch<EventPermissionsProvider>().canEditEvent,
                displayLocation: MeetingAgendaDisplayLocation.meetingPage,
              ),
              enableGuide: enableGuide,
              enableUserSubmittedAgenda:
                  event.eventType == EventType.livestream &&
                      !liveMeetingProvider.isInBreakout,
              enableChat: (permissions.canChat && eventProvider.enableChat),
              enableAdminPanel: permissions.canAccessAdminTabInEvent,
              child: _buildConferenceRoomWrapper(
                child: _buildVideoLayout(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoading() {
    final liveMeetingStream =
        Provider.of<LiveMeetingProvider>(context).liveMeetingStream;
    if (liveMeetingStream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: CustomStreamBuilder(
        entryFrom: '_MeetingDialogState._buildLoading1',
        stream: eventProvider.eventStream,
        errorMessage: 'There was an error loading event details.',
        builder: (_, __) => CustomStreamBuilder(
          entryFrom: '_MeetingDialogState._buildLoading2',
          stream: eventProvider.selfParticipantStream,
          errorMessage: 'There was an error loading event details.',
          builder: (_, __) => CustomStreamBuilder(
            entryFrom: '_MeetingDialogState._buildLoading3',
            stream: eventProvider.eventParticipantsStream,
            errorMessage: 'There was an error loading event details.',
            builder: (_, __) => CustomStreamBuilder(
              entryFrom: '_MeetingDialogState._buildLoading4',
              stream: liveMeetingStream,
              errorMessage: 'There was an error loading event details.',
              builder: (context, __) => _buildAgendaWrapper(context),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () {
        Provider.of<LiveMeetingProvider>(context, listen: false).leaveMeeting();
        return Future.value(false);
      },
      child: Material(
        color: context.theme.colorScheme.primary,
        child: SizedBox.expand(
          child: _buildLoading(),
        ),
      ),
    );
  }
}
