import 'dart:async';
import 'dart:math' as math;

import 'package:client/core/utils/toast_utils.dart';
import 'package:client/core/widgets/custom_loading_indicator.dart';
import 'package:flutter/foundation.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/recording_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_card.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/providers/meeting_guide_card_store.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_minimized_card.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_error.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/brady_bunch_view_widget.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/conference_room.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/need_help_dialog.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/participant_widget.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/data/providers/meeting_agenda_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart' as event;
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../../data/providers/agora_room.dart';
import 'networking_status.dart';

/// Show the twilio meeting on desktop
class VideoFlutterMeeting extends StatefulHookWidget {
  const VideoFlutterMeeting({
    Key? key,
  }) : super(key: key);

  @override
  _VideoFlutterMeetingState createState() => _VideoFlutterMeetingState();
}

class _VideoFlutterMeetingState extends State<VideoFlutterMeeting> {
  static const spacerSize = 5.0;

  /// Narrow rail for non-sharer cameras during screen share (marquee takes the rest).
  static const screenShareSidebarWidth = 220.0;

  /// Bottom strip height for two-person screen share (matches stage side panel).
  static const screenShareBottomBarHeight = 160.0;

  StreamSubscription? _onConferenceRoomException;
  late StreamSubscription _onUnloadSubscription;

  /// Used to ensure that if the same participants are on stage, they dont constantly reorder
  /// themselves as they switch dominant speaker.
  List<String> _currentStageOrdering = [];

  ConferenceRoom? get _conferenceRoom => ConferenceRoom.watchOrNull(context);

  LiveMeetingProvider get liveMeetingProvider =>
      Provider.of<LiveMeetingProvider>(context);
  AgendaProvider get agendaProvider => context.watch<AgendaProvider>();

  @override
  void initState() {
    super.initState();

    _onUnloadSubscription = html.window.onBeforeUnload.listen((event) {
      ConferenceRoom.read(context)?.room?.dispose();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ConferenceRoom is provided only after join info loads and can be
    // replaced on room switch; this State may survive both via GlobalKey.
    _checkConnectToRoom();
  }

  void _checkConnectToRoom() {
    if (ConferenceRoom.read(context)?.hasStartedConnecting == false) {
      _connectToRoom();
    }
  }

  Future<void> _connectToRoom() async {
    final conferenceRoom = ConferenceRoom.read(context);
    if (conferenceRoom == null || conferenceRoom.hasStartedConnecting) return;
    // Set before the first await so a same-frame rebuild cannot double-connect.
    conferenceRoom.hasStartedConnecting = true;
    await _onConferenceRoomException?.cancel();
    _onConferenceRoomException = conferenceRoom.onException.listen((err) async {
      loggingService.log('showing alert in listener');
      await showAlert(
        context,
        err is PlatformException ? err.details : err.toString(),
      );
    });
    await conferenceRoom.connect();
  }

  @override
  void dispose() {
    loggingService.log('disposing twilio flutter meeting');

    _onConferenceRoomException?.cancel();
    _onUnloadSubscription.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conferenceRoom = _conferenceRoom;
    if (conferenceRoom == null) {
      return const Center(child: CircularProgressIndicator());
    }
    // watchOrNull can start succeeding on rebuild without didChangeDependencies.
    _checkConnectToRoom();
    final error = conferenceRoom.connectError;
    if (error != null && error.trim().isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: AudioVideoErrorDisplay(error: error),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: GetHelpButton(),
          ),
        ],
      );
    }

    return CustomStreamBuilder(
      entryFrom: '_VideoFlutterMeetingState.build',
      stream: Stream.fromFuture(conferenceRoom.connectionFuture),
      errorMessage: 'Something went wrong loading room. Please refresh!',
      loadingMessage: 'Connecting to room...',
      textStyle: TextStyle(color: context.theme.colorScheme.onSurface),
      builder: (_, __) => _buildLayout(),
    );
  }

  Widget _buildLayout() {
    return NetworkingStatus(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: _buildVideoLayout()),
        ],
      ),
    );
  }

  Widget _buildVideoLayout() {
    return Stack(
      children: [
        Selector<LiveMeetingProvider, String?>(
          selector: (_, lmp) => lmp.liveMeeting?.screenSharingUserId,
          builder: (context, _, __) {
            final conferenceRoom = _conferenceRoom;
            if (conferenceRoom == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _buildMainVideoContent(context, conferenceRoom);
          },
        ),
        if (EventProvider.watch(context)
                .eventOrNull
                ?.eventSettings
                ?.alwaysRecord ==
            true)
          Container(
            alignment: Alignment.topRight,
            child: const RecordingIndicator(),
          ),
      ],
    );
  }

  Widget? _screenShareLayoutOrNull(ConferenceRoom conferenceRoom) {
    final screenSharer = conferenceRoom.screenSharer;
    if (screenSharer == null) return null;
    return _buildScreenShareLayout(conferenceRoom, screenSharer);
  }

  Widget _buildMainVideoContent(
    BuildContext context,
    ConferenceRoom conferenceRoom,
  ) {
    final screenShareLayout = _screenShareLayoutOrNull(conferenceRoom);
    if (screenShareLayout != null) return screenShareLayout;
    return _buildHostlessLayout();
  }

  /// Marquee screen share; non-sharers in a bottom strip (2 people) or right rail (3+).
  Widget _buildScreenShareLayout(
    ConferenceRoom conferenceRoom,
    AgoraParticipant screenSharer,
  ) {
    final sidebarParticipants = conferenceRoom.participants.where((p) {
      if (p.userId != screenSharer.userId) return true;
      return p.screenAgoraUid != null;
    }).toList();

    final marquee = Padding(
      padding: const EdgeInsets.all(spacerSize),
      child: ParticipantWidget(
        globalKey: ValueKey('${screenSharer.userId}-screen-share'),
        participant: screenSharer,
        isScreenShare: true,
      ),
    );

    // Bottom rail when at most one non-sharer tile (dual-engine includes sharer's
    // camera in sidebar; canvas excludes sharer — same threshold either way).
    final nonSharerSidebarCount = sidebarParticipants
        .where((p) => p.userId != screenSharer.userId)
        .length;
    final useBottomBar = nonSharerSidebarCount <= 1;
    if (useBottomBar) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: marquee),
          SizedBox(
            height: screenShareBottomBarHeight,
            child: _SidePanelParticipants(
              remainingParticipants: sidebarParticipants,
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: marquee),
        if (sidebarParticipants.isNotEmpty)
          SizedBox(
            width: screenShareSidebarWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                spacerSize,
                spacerSize,
                spacerSize,
              ),
              child: _ScreenShareSidebar(participants: sidebarParticipants),
            ),
          ),
      ],
    );
  }

  Widget _buildMeetingGuideCard() {
    return GlobalKeyedSubtree(
      label: 'meeting-guide-card',
      child: MeetingGuideCard(
        onMinimizeCard: () => alertOnError(
          context,
          () => LiveMeetingProvider.read(context)
              .updateGuideCardIsMinimized(isMinimized: true),
        ),
      ),
    );
  }

  Widget _buildLayoutViewButtons() {
    final additionalButtonsOffset =
        EventProvider.watch(context).event.eventSettings?.alwaysRecord ?? false
            ? EdgeInsets.only(right: 120)
            : EdgeInsets.zero;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 40) + additionalButtonsOffset,
      alignment: Alignment.topRight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (liveMeetingProvider.isMeetingCardMinimized &&
              liveMeetingProvider.showGuideCard)
            MeetingGuideMinimizedCard(
              onExpandCard: () => alertOnError(
                context,
                () => LiveMeetingProvider.read(context)
                    .updateGuideCardIsMinimized(isMinimized: false),
              ),
            ),
          SizedBox(width: 10),
          CustomInkWell(
            onTap: () {
              final liveMeetingProvider = LiveMeetingProvider.read(context);
              final newType = liveMeetingProvider.liveMeetingViewType ==
                      LiveMeetingViewType.bradyBunch
                  ? LiveMeetingViewType.stage
                  : LiveMeetingViewType.bradyBunch;

              liveMeetingProvider.updateLiveMeetingViewType(newType);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: context.theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildViewIconButton(
                    'Gallery View',
                    Icons.grid_view_sharp,
                    LiveMeetingViewType.bradyBunch,
                  ),
                  _buildViewIconButton(
                    'Stage View',
                    Icons.view_list,
                    LiveMeetingViewType.stage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewIconButton(
    String message,
    IconData iconData,
    LiveMeetingViewType type,
  ) {
    return Tooltip(
      message: message,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Icon(
          iconData,
          size: 25,
          color: liveMeetingProvider.liveMeetingViewType == type
              ? context.theme.colorScheme.onSurface
              : context.theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildHostlessDesktop() {
    final conferenceRoom = _conferenceRoom;
    if (conferenceRoom == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final screenShareLayout = _screenShareLayoutOrNull(conferenceRoom);
    if (screenShareLayout != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLayoutViewButtons(),
          Expanded(child: screenShareLayout),
          Align(
            alignment: Alignment.centerRight,
            child: GetHelpButton(),
          ),
        ],
      );
    }

    final participants = conferenceRoom.participants;

    final showGuideCard = liveMeetingProvider.showGuideCard;

    final guideCardTakeover =
        MeetingGuideCardStore.watch(context)?.guideCardTakeover == true &&
            !liveMeetingProvider.isMeetingCardMinimized;

    return LayoutBuilder(
      builder: (_, constraints) {
        var maxHighlighted = conferenceRoom.maxHighlightedParticipants;

        if (guideCardTakeover) {
          maxHighlighted = 0;
        }

        var highlightedParticipants =
            participants.take(maxHighlighted).toList().reversed.toList();

        // If the participants are the same as last build, then keep them in the same spot on stage
        // Note: hacky solution that assumes max two people on stage
        if (highlightedParticipants.length > 1 &&
            _currentStageOrdering.length > 1 &&
            highlightedParticipants[0].userId == _currentStageOrdering[1]) {
          highlightedParticipants = highlightedParticipants.reversed.toList();
        }
        _currentStageOrdering =
            highlightedParticipants.map((p) => p.userId).toList();

        final remainingParticipants =
            participants.skip(maxHighlighted).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLayoutViewButtons(),
            Expanded(
              child: Container(
                alignment: Alignment.center,
                padding: EdgeInsets.only(
                  left: 12,
                  top: 12,
                  right: 12,
                  bottom: liveMeetingProvider.isInBreakout ? 0 : 12,
                ),
                child: Builder(
                  builder: (_) {
                    final participantWidgets = [
                      for (final p in highlightedParticipants)
                        ParticipantWidget(
                          borderRadius: BorderRadius.circular(20),
                          globalKey: ValueKey('${p.userId}-stage'),
                          participant: p,
                        ),
                    ];

                    var widgets = [
                      ...participantWidgets,
                      if (showGuideCard &&
                          !liveMeetingProvider.isMeetingCardMinimized)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: math.max(600, constraints.maxWidth / 2),
                          ),
                          child: _buildMeetingGuideCard(),
                        ),
                    ];

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < widgets.length; i++) ...[
                          if (i > 0) SizedBox(height: 10, width: 10),
                          Flexible(child: widgets[i]),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: GetHelpButton(),
            ),
            if (remainingParticipants.isNotEmpty)
              SizedBox(
                height: 160,
                child: _SidePanelParticipants(
                  remainingParticipants: remainingParticipants,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHostlessLayout() {
    final conferenceRoom = _conferenceRoom;
    if (conferenceRoom == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final screenShareLayout = _screenShareLayoutOrNull(conferenceRoom);
    if (screenShareLayout != null) return screenShareLayout;
    return liveMeetingProvider.liveMeetingViewType == LiveMeetingViewType.stage
        ? _buildHostlessDesktop()
        : _buildBradyBunchViewWidget();
  }

  Widget _buildBradyBunchViewWidget() {
    final conferenceRoom = _conferenceRoom;
    if (conferenceRoom == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final screenShareLayout = _screenShareLayoutOrNull(conferenceRoom);
    if (screenShareLayout != null) {
      return Stack(
        children: [
          screenShareLayout,
          Align(
            alignment: Alignment.centerRight,
            child: Column(
              children: [
                _buildLayoutViewButtons(),
                Spacer(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: GetHelpButton(),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final showGuideCard = liveMeetingProvider.showGuideCard;
    final showGuideCardLayout =
        showGuideCard && !liveMeetingProvider.isMeetingCardMinimized;

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: BradyBunchViewWidget(),
              ),
            ),
            if (showGuideCardLayout)
              Expanded(
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 45, horizontal: 10),
                  alignment: Alignment.center,
                  child: _buildMeetingGuideCard(),
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            children: [
              _buildLayoutViewButtons(),
              Spacer(),
              Align(
                alignment: Alignment.bottomRight,
                child: GetHelpButton(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class GetHelpButton extends StatefulWidget {
  const GetHelpButton();

  static Future<void> getHelp(BuildContext context) async {
    final liveMeetingProvider = LiveMeetingProvider.read(context);
    final eventProvider = EventProvider.read(context);

    analytics.logEvent(
      AnalyticsPressEventHelpEvent(
        communityId: eventProvider.communityId,
        eventId: eventProvider.eventId,
        asHost: liveMeetingProvider.isHost,
        templateId: eventProvider.templateId,
      ),
      eventTitle: eventProvider.event.title,
    );

    final isHostless =
        eventProvider.event.eventType == event.EventType.hostless;
    final isInLiveStreamBreakouts = isHostless ||
        (liveMeetingProvider.isInBreakout && eventProvider.isLiveStream);
    final showContactAdmin = isInLiveStreamBreakouts;
    final needHelp =
        await NeedHelpDialog(showContactAdmin: showContactAdmin).show();

    if (!needHelp) return;

    await alertOnError(
      context,
      () => cloudFunctionsLiveMeetingService.updateBreakoutRoomFlagStatus(
        request: UpdateBreakoutRoomFlagStatusRequest(
          eventPath: liveMeetingProvider.eventPath,
          breakoutSessionId: liveMeetingProvider
              .liveMeeting!.currentBreakoutSession!.breakoutRoomSessionId,
          roomId: liveMeetingProvider.breakoutRoomOverride ??
              liveMeetingProvider.assignedBreakoutRoomId!,
          flagStatus: BreakoutRoomFlagStatus.needsHelp,
        ),
      ),
    );

    showRegularToast(
      context,
      'We’ve notified an administrator - please be patient, help is on the way!',
      toastType: ToastType.success,
    );
  }

  @override
  _GetHelpButtonState createState() => _GetHelpButtonState();
}

class _GetHelpButtonState extends State<GetHelpButton> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_sending) ...[
            SizedBox(
              height: 20,
              width: 20,
              child: CustomLoadingIndicator(),
            ),
            SizedBox(width: 6),
          ],
          CustomInkWell(
            onTap: () async {
              if (_sending) return;

              setState(() => _sending = true);
              await GetHelpButton.getHelp(context);
              setState(() => _sending = false);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              child: HeightConstrainedText(
                'Need Help?',
                style: TextStyle(
                  fontWeight: FontWeight.w300,
                  color: context.theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical camera rail shown to the right of the marquee during screen share.
class _ScreenShareSidebar extends StatelessWidget {
  final List<AgoraParticipant> participants;

  const _ScreenShareSidebar({required this.participants});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final p in participants) ...[
          AspectRatio(
            aspectRatio: ParticipantWidget.aspectRatio,
            child: ParticipantWidget(
              globalKey: ValueKey(p.userId),
              participant: p,
            ),
          ),
          const SizedBox(height: _VideoFlutterMeetingState.spacerSize),
        ],
      ],
    );
  }
}

class _SidePanelParticipants extends StatefulWidget {
  final List<AgoraParticipant> remainingParticipants;

  const _SidePanelParticipants({required this.remainingParticipants});

  @override
  _SidePanelParticipantsState createState() => _SidePanelParticipantsState();
}

class _SidePanelParticipantsState extends State<_SidePanelParticipants> {
  final _controller = ScrollController();

  final _scrollDuration = Duration(milliseconds: 500);

  bool _controllerAttached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkUpdateControllerAttached());
  }

  void _checkUpdateControllerAttached() {
    if (_controller.hasClients != _controllerAttached) {
      setState(() => _controllerAttached = _controller.hasClients);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            ListView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              itemExtent: constraints.maxHeight * ParticipantWidget.aspectRatio,
              children: [
                for (final p in widget.remainingParticipants)
                  ParticipantWidget(
                    globalKey: ValueKey(p.userId),
                    participant: p,
                  ),
              ],
            ),
            if (_controllerAttached && _controller.position.maxScrollExtent > 0)
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_controller.position.atEdge &&
                      _controller.position.pixels == 0)
                    SizedBox.shrink()
                  else
                    CustomInkWell(
                      onTap: () => _controller.animateTo(
                        math.max(
                          -25,
                          _controller.offset - constraints.maxWidth * 0.75,
                        ),
                        duration: _scrollDuration,
                        curve: Curves.easeInOut,
                      ),
                      child: Container(
                        width: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              context.theme.colorScheme.primaryContainer,
                              Colors.transparent,
                            ],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.chevron_left),
                      ),
                    ),
                  if (_controller.position.atEdge &&
                      _controller.position.pixels != 0)
                    SizedBox.shrink()
                  else
                    CustomInkWell(
                      onTap: () => _controller.animateTo(
                        _controller.offset + constraints.maxWidth * 0.75,
                        duration: _scrollDuration,
                        curve: Curves.easeInOut,
                      ),
                      child: Container(
                        width: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.transparent,
                              context.theme.colorScheme.primaryContainer,
                            ],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.chevron_right),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
