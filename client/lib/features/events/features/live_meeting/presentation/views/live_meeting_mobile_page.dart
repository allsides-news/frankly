import 'package:data_models/chat/emotion.dart';
import 'dart:async';

import 'package:client/core/utils/toast_utils.dart';
import 'package:collection/collection.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/recording_indicator.dart';
import 'package:client/features/events/features/live_meeting/presentation/widgets/unread_dot.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:client/features/chat/data/providers/chat_model.dart';
import 'package:client/features/chat/presentation/widgets/chat_widget.dart';
import 'package:client/features/events/features/live_meeting/features/admin_panel/presentation/widgets/admin_panel.dart';
import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/event_tabs.dart';
import 'package:client/features/events/features/event_page/presentation/event_tabs_model.dart';
import 'package:client/features/events/features/live_meeting/presentation/widgets/live_meeting_desktop.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/talking_odometer.dart';
import 'package:client/features/events/features/live_meeting/presentation/views/live_meeting_mobile_contract.dart';
import 'package:client/features/events/features/live_meeting/data/models/live_meeting_mobile_model.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/views/meeting_guide_card.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/providers/meeting_guide_card_store.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/agora_room.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_error.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_settings.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/brady_bunch_view_widget.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/conference_room.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/control_bar.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/participant_widget.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/video_flutter_meeting.dart';
import 'package:client/features/events/features/live_meeting/features/live_stream/presentation/widgets/live_stream_widget.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/data/providers/meeting_agenda_provider.dart';
import 'package:client/features/events/features/live_meeting/presentation/widgets/event_countdown_timer.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/presentation/widgets/user_submitted_agenda.dart';
import 'package:client/features/events/features/event_page/presentation/widgets/waiting_room.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/app_clickable_widget.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/services.dart';
import 'package:client/styles/app_asset.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:provider/provider.dart';
import 'package:universal_html/html.dart' as html;

import '../live_meeting_mobile_presenter.dart';

enum LiveMeetingMobileBottomSheetState {
  fullyVisible,
  partiallyVisible,

  /// Retracted to just its drag handle, sitting above the bottom bar. This is
  /// the resting state whenever the event has an agenda: the panel is never
  /// fully dismissed, so the bottom bar never has to grow a button to bring
  /// it back.
  peek,

  /// Only for events with no agenda at all -- there is nothing to peek at, so
  /// no handle is shown.
  hidden,
}

/// The drag handle and the padding above and below it.
const double _kSheetHandleHeight = 5;
const double _kSheetHandlePadding = 12;
const double _kSheetHandleBlockHeight =
    _kSheetHandleHeight + _kSheetHandlePadding * 2;

/// The agenda item's title row, which the retracted panel shows beneath its
/// handle so a collapsed panel still says what the room is on.
const double _kSheetCollapsedTitleHeight = 52;

/// How much of the panel stays on screen when it is retracted.
const double _kSheetPeekHeight =
    _kSheetHandleBlockHeight + _kSheetCollapsedTitleHeight;

/// Height of the horizontal strip of participants above the stage, and the
/// gutter between its tiles.
///
/// A thinner gutter than the grid uses, and a slightly taller strip: at the
/// grid's margin these tiles were down to 82pt square, which is too small to
/// recognise anyone in.
const double _kParticipantStripHeight = 116;
const double _kParticipantStripGutter = 4;

/// Horizontal inset shared by the bottom bar and everything inside the sheet.
/// The panel's tabs each had their own -- 6 for admin, 14 for the agenda --
/// so their content never lined up with the bar directly beneath them.
const double kMeetingPanelInset = 20;

/// Share of the screen the panel takes when pulled to its middle stop.
const double _kSheetPartialFraction = 0.45;

/// The hang-up red, unchanged across themes.
const Color _kLeaveRed = Color(0xFFFF5A62);

/// Inset AppClickableWidget puts around its child by default.
const double _kIconTapInset = 8;

/// Horizontal padding of the top bar's row. Subtracts the tap inset so the
/// glyphs -- not their invisible tap boxes -- line up with the outer edge of
/// the video tiles below. Anything in the bar without that inset (the Leave
/// button) adds it back itself.
const double _kTopBarInset = kVideoTileMargin - _kIconTapInset;

class LiveMeetingMobilePage extends StatefulWidget {
  const LiveMeetingMobilePage({
    Key? key,
  }) : super(key: key);

  @override
  State<LiveMeetingMobilePage> createState() => _LiveMeetingMobilePageState();
}

class _LiveMeetingMobilePageState extends State<LiveMeetingMobilePage>
    implements LiveMeetingMobileView {
  final chatTextEditingController = TextEditingController();
  late final LiveMeetingMobileModel _model;
  late final LiveMeetingMobilePresenter _presenter;

  StreamSubscription? _onConferenceRoomException;
  StreamSubscription? _onUnloadSubscription;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final eventProvider = EventProvider.read(context);
      analytics.logPageView(
        'live_meeting',
        communityId: eventProvider.communityId,
        eventId: eventProvider.eventId,
      );
    });

    final LiveMeetingMobileBottomSheetState initialSheetState;

    final suppressGuide = ConferenceRoom.read(context) == null ||
        context.read<AgendaProvider>().agendaItems.isEmpty;

    // Deliberately optimistic: _agendaItems is still empty this early, since
    // it fills in once the event loads. Assuming "hidden" here left the panel
    // shut with nothing to reopen it, because no transition returns from
    // hidden on its own. _checkUpdateBottomSheet corrects it below if the
    // event really has no agenda.
    if (suppressGuide) {
      initialSheetState = LiveMeetingMobileBottomSheetState.peek;
    } else {
      initialSheetState = LiveMeetingMobileBottomSheetState.partiallyVisible;
    }
    _model = LiveMeetingMobileModel(
      bottomSheetState: initialSheetState,
    );
    _presenter = LiveMeetingMobilePresenter(context, this, _model);
  }

  @override
  void dispose() {
    super.dispose();

    _onConferenceRoomException?.cancel();
    _onUnloadSubscription?.cancel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _checkUpdateBottomSheet();

    _checkConnectToRoom();
  }

  @override
  void updateView() {
    setState(() {});
  }

  /// Last value of `isMeetingCardMinimized`, so the panel is collapsed when
  /// it flips rather than for as long as it stays set.
  bool _wasMeetingCardMinimized = false;

  /// Live height while a drag is in progress; null the rest of the time, when
  /// the height comes from [_model.bottomSheetState] instead.
  double? _dragSheetHeight;

  /// Which video layout to draw. This used to be inferred from how far the
  /// agenda panel was open, which meant dragging the panel silently changed
  /// what you were watching. It's the viewer's choice now, via the top bar.
  ///
  /// Doesn't apply at [LiveMeetingMobileBottomSheetState.fullyVisible], where
  /// the panel takes the screen and only the participant strip fits.
  bool _isGalleryView = true;

  /// Beyond this the panel takes the screen and we switch to the full layout.
  double _fullSheetHeight(double screenHeight) => screenHeight * 0.9;

  double _sheetHeightForState(
    LiveMeetingMobileBottomSheetState state,
    double screenHeight,
  ) {
    switch (state) {
      case LiveMeetingMobileBottomSheetState.fullyVisible:
        return _fullSheetHeight(screenHeight);
      case LiveMeetingMobileBottomSheetState.partiallyVisible:
        return screenHeight * _kSheetPartialFraction;
      case LiveMeetingMobileBottomSheetState.peek:
        return _kSheetPeekHeight;
      case LiveMeetingMobileBottomSheetState.hidden:
        return 0;
    }
  }

  void _onSheetDragStart() {
    final screenHeight = MediaQuery.of(context).size.height;
    setState(() {
      _dragSheetHeight =
          _sheetHeightForState(_model.bottomSheetState, screenHeight);
    });
  }

  void _onSheetDragUpdate(double deltaY, {required bool canRetract}) {
    final screenHeight = MediaQuery.of(context).size.height;
    final current = _dragSheetHeight ??
        _sheetHeightForState(_model.bottomSheetState, screenHeight);

    // Dragging down grows deltaY, which shrinks the panel.
    final lowerBound =
        canRetract ? _kSheetPeekHeight : screenHeight * _kSheetPartialFraction;

    setState(() {
      _dragSheetHeight =
          (current - deltaY).clamp(lowerBound, _fullSheetHeight(screenHeight));
    });
  }

  void _onSheetDragEnd(double velocityY) {
    final height = _dragSheetHeight;
    if (height == null) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final stops = <LiveMeetingMobileBottomSheetState, double>{
      LiveMeetingMobileBottomSheetState.peek: _kSheetPeekHeight,
      LiveMeetingMobileBottomSheetState.partiallyVisible:
          screenHeight * _kSheetPartialFraction,
      LiveMeetingMobileBottomSheetState.fullyVisible:
          _fullSheetHeight(screenHeight),
    };

    // A decisive flick commits in its own direction; otherwise settle on
    // whichever stop the panel was left closest to.
    const flickThreshold = 700.0;
    LiveMeetingMobileBottomSheetState target;
    if (velocityY.abs() > flickThreshold) {
      final ordered = stops.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final currentIndex = ordered.indexWhere((e) => e.value >= height - 1);
      final index = velocityY > 0 ? currentIndex - 1 : currentIndex + 1;
      target = ordered[index.clamp(0, ordered.length - 1)].key;
    } else {
      target = stops.entries
          .reduce(
            (a, b) =>
                (a.value - height).abs() <= (b.value - height).abs() ? a : b,
          )
          .key;
    }

    setState(() => _dragSheetHeight = null);
    _presenter.toggleBottomSheetState(target);
  }

  void _checkUpdateBottomSheet() {
    final keyboardIsOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    final eventTabsController =
        Provider.of<EventTabsControllerState>(context, listen: false);
    final selectedTabIndex =
        eventTabsController.selectedTabController.selectedIndex;
    final selectedTab = eventTabsController.tabs[selectedTabIndex];

    final isLargeAgendaItem = selectedTab == TabType.guide &&
        [AgendaItemType.wordCloud, AgendaItemType.userSuggestions].contains(
          MeetingGuideCardStore.read(context)?.meetingGuideCardAgendaItem?.type,
        );

    final isMeetingCardMinimized =
        LiveMeetingProvider.read(context).isMeetingCardMinimized;
    // Only the moment it becomes true counts. It's a persisted field, so
    // while it stayed true this method -- which runs on every
    // didChangeDependencies -- forced the panel shut again on the next
    // provider notification, and the agenda-complete state could never be
    // read: pull the panel up, and it collapsed a moment later.
    final justMinimized = isMeetingCardMinimized && !_wasMeetingCardMinimized;
    _wasMeetingCardMinimized = isMeetingCardMinimized;

    final hasAgenda = context.read<AgendaProvider>().agendaItems.isNotEmpty;

    if (!hasAgenda) {
      // The one case that still fully dismisses: there is nothing to peek at.
      _presenter
          .toggleBottomSheetState(LiveMeetingMobileBottomSheetState.hidden);
    } else if (keyboardIsOpen ||
        (justMinimized && selectedTab == TabType.guide)) {
      // Retract to the handle rather than dismissing. The panel is positioned
      // past the bottom edge while the keyboard is up, so the keyboard covers
      // it and the chat field sits clear above both.
      _presenter.toggleBottomSheetState(LiveMeetingMobileBottomSheetState.peek);
    } else if (_model.bottomSheetState ==
        LiveMeetingMobileBottomSheetState.hidden) {
      // The agenda has since loaded -- undo the initial guess.
      _presenter.toggleBottomSheetState(LiveMeetingMobileBottomSheetState.peek);
    } else if ((isLargeAgendaItem || selectedTab == TabType.suggestions) &&
        _model.bottomSheetState ==
            LiveMeetingMobileBottomSheetState.partiallyVisible) {
      _presenter.toggleBottomSheetState(
        LiveMeetingMobileBottomSheetState.fullyVisible,
      );
    }
  }

  void _checkConnectToRoom() {
    final conferenceRoom = ConferenceRoom.read(context);
    final inRoom = conferenceRoom != null;
    if (inRoom && conferenceRoom.hasStartedConnecting == false) {
      _connectToRoom();

      _onUnloadSubscription = html.window.onBeforeUnload.listen((event) {
        final conferenceRoom = ConferenceRoom.read(context);
        conferenceRoom?.room?.dispose();
      });
    }
  }

  Future<void> _connectToRoom() async {
    final conferenceRoom = ConferenceRoom.read(context);
    _onConferenceRoomException =
        conferenceRoom?.onException.listen((err) async {
      loggingService.log('showing alert in listener');
      await showAlert(
        context,
        err is PlatformException ? err.details : err.toString(),
      );
    });
    await conferenceRoom?.connect();
  }

  @override
  Widget build(BuildContext context) {
    MeetingGuideCardStore.watch(context);

    final showAppBar = ![
      MeetingUiState.leftMeeting,
      MeetingUiState.enterMeetingPrescreen,
    ].contains(LiveMeetingProvider.watch(context).activeUiState);
    final showBottomBar = ConferenceRoom.read(context) != null;
    return Scaffold(
      // Not colorScheme.surface: under the dark theme that resolves to the
      // same neutral800 the agenda panel uses, leaving the video ground and
      // the panel indistinguishable. This is a step darker there, and stays
      // distinct from the panel in light mode too.
      backgroundColor: context.theme.colorScheme.surfaceContainerLowest,
      appBar: showAppBar ? _buildAppBar(hasBottomBar: showBottomBar) : null,
      body: _buildBody(),
      bottomNavigationBar: showBottomBar
          ? _ConferenceRoomRebuild(builder: (_) => _buildBottomNavBar())
          : null,
    );
  }

  /// The Admin and Refresh connection items, shared by the bottom bar's
  /// overflow menu and the top bar's stand-in, so the two can't drift apart.
  ///
  /// Both are built inside an itemBuilder, which runs outside the widget
  /// tree's build phase -- every Provider lookup in here must be listen:false.
  PopupMenuItem<FutureOr<void> Function()> _adminMenuItem(
    EventTabsControllerState tabs,
  ) {
    return PopupMenuItem(
      value: () {
        tabs.openTab(TabType.admin);
        _presenter.toggleBottomSheetState(
          LiveMeetingMobileBottomSheetState.fullyVisible,
        );
      },
      child: HeightConstrainedText('Admin'),
    );
  }

  PopupMenuItem<FutureOr<void> Function()> _refreshMenuItem(
    BuildContext context,
  ) {
    return PopupMenuItem(
      value: () => LiveMeetingProvider.read(context).refreshMeeting(),
      child: HeightConstrainedText(context.l10n.refreshConnection),
    );
  }

  PreferredSize _buildAppBar({required bool hasBottomBar}) {
    final eventTabsController = Provider.of<EventTabsControllerState>(context);
    final eventProvider = EventProvider.watch(context);

    final showTalkingTimer = eventProvider.enableTalkingTimer;

    // Nothing to toggle between until we're in a room, and at full height the
    // panel covers the video entirely.
    final showViewToggle = ConferenceRoom.read(context) != null &&
        _model.bottomSheetState !=
            LiveMeetingMobileBottomSheetState.fullyVisible;

    return PreferredSize(
      preferredSize: Size.fromHeight(60),
      child: Container(
        // Matches the page behind the video tiles, so the bar reads as part of
        // the same surface rather than a separate strip.
        color: context.theme.colorScheme.surfaceContainerLowest,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: _kTopBarInset,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (showTalkingTimer)
                      Center(
                        child: SizedBox(
                          width: 70,
                          height: 70,
                          child: Transform.scale(
                            scale: 1.0,
                            child: Theme(
                              data: context.theme.copyWith(
                                colorScheme: context.theme.colorScheme.copyWith(
                                  onPrimary:
                                      context.theme.colorScheme.onSurface,
                                ),
                              ),
                              child: TalkingOdometer(
                                pillColor:
                                    context.theme.colorScheme.surfaceContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (eventTabsController.widget.enableUserSubmittedAgenda)
                      AppClickableWidget(
                        child: Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 30,
                        ),
                        onTap: () {
                          final eventTabsController =
                              Provider.of<EventTabsControllerState>(
                            context,
                            listen: false,
                          );
                          eventTabsController.openTab(TabType.suggestions);
                          _presenter.toggleBottomSheetState(
                            LiveMeetingMobileBottomSheetState.fullyVisible,
                          );
                        },
                      ),
                    AppClickableWidget(
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 30,
                      ),
                      onTap: () => GetHelpButton.getHelp(context),
                    ),
                    // Chat lives in the bottom bar, which doesn't exist
                    // until you're in a room -- so in the waiting room you
                    // could watch messages arrive with no way to open the
                    // panel or reply. A button of its own rather than a menu
                    // item, to match where it sits once you're in.
                    if (!hasBottomBar && eventTabsController.widget.enableChat)
                      AppClickableWidget(
                        tooltipMessage: 'Chat',
                        child: Icon(
                          Icons.forum_outlined,
                          size: 30,
                        ),
                        onTap: () {
                          eventTabsController.openTab(TabType.chat);
                          _presenter.toggleBottomSheetState(
                            LiveMeetingMobileBottomSheetState.fullyVisible,
                          );
                        },
                      ),
                    // Without the bottom bar there is no overflow menu, and
                    // in the waiting room that left an admin with no way back
                    // out. Carries only what applies with no room joined.
                    if (!hasBottomBar)
                      Padding(
                        padding: const EdgeInsets.all(_kIconTapInset),
                        child: PopupMenuButton<FutureOr<void> Function()>(
                          tooltip: 'More options',
                          itemBuilder: (context) {
                            final tabs = Provider.of<EventTabsControllerState>(
                              context,
                              listen: false,
                            );
                            return [
                              if (tabs.widget.enableAdminPanel)
                                _adminMenuItem(tabs),
                              _refreshMenuItem(context),
                            ];
                          },
                          onSelected: (itemAction) => itemAction(),
                          child: Icon(
                            Icons.more_vert,
                            size: 30,
                            color: context.theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    if (showViewToggle)
                      Semantics(
                        button: true,
                        label: _isGalleryView
                            ? 'Switch to speaker view'
                            : 'Switch to gallery view',
                        child: AppClickableWidget(
                          // Shows the view you'd get, not the one you're in.
                          child: Icon(
                            _isGalleryView
                                ? Icons.person_outline_rounded
                                : Icons.grid_view_outlined,
                            size: 30,
                          ),
                          onTap: () =>
                              setState(() => _isGalleryView = !_isGalleryView),
                        ),
                      ),
                    Spacer(),
                    // A rounded rectangle rather than the round hang-up
                    // asset, and larger: this is the one irreversible control
                    // in the bar, so it shouldn't be the same weight as its
                    // neighbours. The glyph is a Material icon so it takes a
                    // colour; the PNG's was baked in.
                    Semantics(
                      button: true,
                      label: 'Leave meeting',
                      child: AppClickableWidget(
                        isIcon: false,
                        tooltipMessage: 'Leave meeting',
                        // Its own inset, since the bar's padding is short by
                        // exactly this much for the icons' sake.
                        padding: const EdgeInsets.only(right: _kIconTapInset),
                        borderRadius: 10,
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // The original hang-up colours, kept constant in
                            // both themes: this reads as "danger" regardless
                            // of the surrounding scheme.
                            color: _kLeaveRed,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.call_end,
                            size: 26,
                            color: AppNeutralColors.neutral50,
                          ),
                        ),
                        onTap: () async => await alertOnError(
                          context,
                          () => _presenter.leaveMeeting(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final liveMeetingProvider = LiveMeetingProvider.watch(context);

    Widget? child;
    switch (liveMeetingProvider.activeUiState) {
      case MeetingUiState.leftMeeting:
        child = Container(color: Colors.black45);
        break;
      case MeetingUiState.enterMeetingPrescreen:
        child = EnterMeetingScreen();
        break;
      case MeetingUiState.breakoutRoom:
        child = RefreshKeyWidget(
          // Offered in the overflow menu instead of over someone's video.
          showRefreshButton: false,
          child: BreakoutRoomLoader(
            key: Key(
              'breakout-room-${liveMeetingProvider.currentBreakoutRoomId}',
            ),
            liveMeetingBuilder: (_) {
              if (liveMeetingProvider.currentBreakoutRoomId ==
                  breakoutsWaitingRoomId) {
                return _buildNonMeeting(child: _buildWaitingRoom());
              }

              return _buildMeetingLoading();
            },
          ),
        );
        break;
      case MeetingUiState.waitingRoom:
        child = _buildNonMeeting(child: WaitingRoom());
        break;
      case MeetingUiState.liveStream:
        child = _buildNonMeeting(child: LiveStreamWidget());
        break;
      case MeetingUiState.inMeeting:
        child = RefreshKeyWidget(
          // Offered in the overflow menu instead of over someone's video.
          showRefreshButton: false,
          child: _buildMeetingLoading(),
        );
        break;
    }

    return GlobalKeyedSubtree(label: context.l10n.primaryContent, child: child);
  }

  Widget _buildWaitingRoom() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: context.theme.colorScheme.surfaceContainerLowest,
      ),
      margin: const EdgeInsets.all(16),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 20),
              constraints: BoxConstraints(maxWidth: 200, maxHeight: 200),
              child: ProxiedImage(
                Provider.of<CommunityProvider>(context)
                    .community
                    .profileImageUrl,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildWaitingRoomTextWidget(),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingRoomTextWidget() {
    return HeightConstrainedText(
      'You are in the waiting room.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
    );
  }

  Widget _buildNonMeeting({required Widget child}) {
    final eventTabsController = Provider.of<EventTabsControllerState>(context);
    final eventProvider = EventProvider.watch(context);

    // Check if chat should be disabled for this user in hostless waiting room
    final eventPermissions = EventPermissionsProvider.watch(context);
    final shouldDisableChat =
        eventPermissions?.shouldDisableChatInHostlessWaitingRoom(context) ??
            false;

    final isFloatingChatEnabled = eventTabsController.widget.enableChat &&
        eventProvider.enableFloatingChat &&
        !shouldDisableChat;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(child: child),
                      BreakoutStatusInformation(),
                    ],
                  ),
                  if (isFloatingChatEnabled)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FloatingChatDisplay(),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (_model.bottomSheetState ==
            LiveMeetingMobileBottomSheetState.fullyVisible)
          Column(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _presenter.dismissFullBottomSheet(),
                child: SizedBox(height: 100),
              ),
              Expanded(
                child: LiveMeetingBottomSheet(
                  bottomSheetState: _model.bottomSheetState,
                  onChange: (state) => _presenter.toggleBottomSheetState(state),
                  onClose: () => _presenter.dismissFullBottomSheet(),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildMeetingLoading() {
    final liveMeetingProvider = LiveMeetingProvider.watch(context);

    // Guard: when breakout rooms end, leaveBreakoutRoom() clears the room
    // state before this widget is replaced. If BreakoutRoomLoader's
    // breakoutRoomLiveMeetingStream fires one last time in that window,
    // getCurrentMeetingJoinInfo() returns null and the ! crashes with
    // AgoraRtcException(-1,null) + 'Null check operator used on a null value'
    // on iOS. Return a loading indicator and let the parent rebuild.
    final joinInfoFuture = liveMeetingProvider.getCurrentMeetingJoinInfo();
    if (joinInfoFuture == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomStreamBuilder<GetMeetingJoinInfoResponse>(
      key: ObjectKey(joinInfoFuture),
      entryFrom: '_buildConferenceRoomWrapper.build',
      stream: joinInfoFuture.asStream(),
      loadingMessage: 'Loading room. Please wait...',
      builder: (_, response) {
        // ConferenceRoom may not be in scope during breakout-room transitions
        // (e.g. when switching to the waiting room), causing a
        // ProviderNotFoundException. Fall back to a loading indicator until
        // the provider is re-established.
        //
        // Read, don't watch: a watch here rebuilds ChatWidget on every
        // join/leave/mute and trips Flutter web's text-selection overlay.
        // connectError is observed below without rebuilding the meeting.
        final conferenceRoom = ConferenceRoom.read(context);
        if (conferenceRoom == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return ListenableBuilder(
          listenable: conferenceRoom,
          child: CustomStreamBuilder(
            entryFrom: 'LiveMeetingMobilePage._buildMeetingLoading',
            stream: Stream.fromFuture(conferenceRoom.connectionFuture),
            errorMessage: 'Something went wrong loading room. Please refresh!',
            loadingMessage: 'Connecting to room...',
            textStyle: TextStyle(color: context.theme.colorScheme.onSurface),
            builder: (_, __) {
              final event = EventProvider.watch(context).eventOrNull;
              return Stack(
                children: [
                  _buildMeeting(),
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: event == null
                          ? const SizedBox.shrink()
                          : EventCountdownTimer(
                              event: event,
                              minutesBeforeEnd: 5,
                            ),
                    ),
                  ),
                  if (event?.eventSettings?.alwaysRecord == true)
                    Container(
                      alignment: Alignment.topRight,
                      child: const RecordingIndicator(),
                    ),
                ],
              );
            },
          ),
          builder: (context, child) {
            final error = conferenceRoom.connectError;
            if (error != null && error.trim().isNotEmpty) {
              return Center(
                child: AudioVideoErrorDisplay(error: error),
              );
            }
            return child!;
          },
        );
      },
    );
  }

  Widget _buildMeeting() {
    // Do not watch ConferenceRoom here. ChatWidget's TextField lives in
    // LiveMeetingBottomSheet; rebuilding it on join/leave/mute trips Flutter
    // web's text-selection overlay. Video widgets watch the room below.
    final eventTabsController = Provider.of<EventTabsControllerState>(context);
    final eventProvider = EventProvider.watch(context);

    final isFloatingChatEnabled = eventTabsController.widget.enableChat &&
        eventProvider.enableFloatingChat;

    switch (_model.bottomSheetState) {
      case LiveMeetingMobileBottomSheetState.fullyVisible:
        return Column(
          children: [
            _buildWatchedParticipantStrip(),
            BreakoutStatusInformation(),
            Expanded(
              child: LiveMeetingBottomSheet(
                bottomSheetState: _model.bottomSheetState,
                onChange: (state) => _presenter.toggleBottomSheetState(state),
                onClose: _presenter.isDismissableTabOpen
                    ? () => _presenter.openGuide()
                    : null,
              ),
            ),
          ],
        );
      case LiveMeetingMobileBottomSheetState.partiallyVisible:
      case LiveMeetingMobileBottomSheetState.peek:
      case LiveMeetingMobileBottomSheetState.hidden:
        final sheetState = _model.bottomSheetState;
        final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
        final screenHeight = MediaQuery.of(context).size.height;

        final sheetHeight =
            _dragSheetHeight ?? _sheetHeightForState(sheetState, screenHeight);
        final isDragging = _dragSheetHeight != null;

        return Stack(
          // The panel is anchored past the bottom while the keyboard is up, so
          // the keyboard covers it rather than pushing it into view.
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.only(
                bottom: sheetState == LiveMeetingMobileBottomSheetState.hidden
                    ? 0
                    : _kSheetPeekHeight,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        _buildWatchedVideoStage(),
                        if (isFloatingChatEnabled)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FloatingChatDisplay(),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 10),
                ],
              ),
            ),
            if (sheetState != LiveMeetingMobileBottomSheetState.hidden)
              AnimatedPositioned(
                duration: isDragging
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                bottom: -keyboardInset,
                height: sheetHeight,
                child: LiveMeetingBottomSheet(
                  bottomSheetState: sheetState,
                  onChange: (state) => _presenter.toggleBottomSheetState(state),
                  onDragStart: _onSheetDragStart,
                  onDragUpdate: _onSheetDragUpdate,
                  onDragEnd: _onSheetDragEnd,
                ),
              ),
          ],
        );
    }
  }

  List<AgoraParticipant> _sidebarParticipants() {
    final participants = _presenter.getParticipants();
    final screenSharer = _presenter.getScreenSharer();
    if (screenSharer == null) return participants;
    return participants.where((p) {
      if (p.userId != screenSharer.userId) return true;
      // Dual-engine: camera publishes on a separate UID. Canvas compositor
      // (no screenAgoraUid) embeds the face in the composed stream.
      return p.screenAgoraUid != null;
    }).toList();
  }

  Widget _buildWatchedParticipantStrip() {
    return _ConferenceRoomRebuild(
      builder: (context) {
        final sidebarParticipants = _sidebarParticipants();
        if (sidebarParticipants.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: _kParticipantStripHeight,
          child: ParticipantsWidget(
            participants: sidebarParticipants,
          ),
        );
      },
    );
  }

  Widget _buildWatchedVideoStage() {
    return _ConferenceRoomRebuild(
      builder: (context) {
        final participants = _presenter.getParticipants();
        final screenSharer = _presenter.getScreenSharer();
        final sidebarParticipants = _sidebarParticipants();
        final dominantSpeaker = participants.firstOrNull;
        final stageStripParticipants =
            sidebarParticipants.where((p) => p != dominantSpeaker).toList();

        if (_isGalleryView) {
          return Column(
            children: [
              Expanded(
                child: screenSharer != null
                    ? _buildFeaturedScreenShare(screenSharer)
                    : const BradyBunchViewWidget(),
              ),
              if (screenSharer != null && sidebarParticipants.isNotEmpty)
                SizedBox(
                  height: _kParticipantStripHeight,
                  child: ParticipantsWidget(
                    participants: sidebarParticipants,
                  ),
                ),
              BreakoutStatusInformation(),
              SizedBox(height: 10),
            ],
          );
        }

        return Column(
          children: [
            if (screenSharer != null) ...[
              if (sidebarParticipants.isNotEmpty)
                SizedBox(
                  height: _kParticipantStripHeight,
                  child: ParticipantsWidget(
                    participants: sidebarParticipants,
                  ),
                ),
              BreakoutStatusInformation(),
              Expanded(
                child: _buildFeaturedScreenShare(screenSharer),
              ),
            ] else ...[
              // Everyone except whoever is on the stage. Agora attaches a
              // video track to one view at a time, so a participant rendered
              // in both places comes out black in the second -- which reads as
              // a broken tile rather than as the duplicate it is.
              //
              // Was `sidebarParticipants.length > 1`, which reads as "only if
              // somebody besides the staged person" but still passed that
              // person through.
              if (stageStripParticipants.isNotEmpty)
                SizedBox(
                  height: _kParticipantStripHeight,
                  child: ParticipantsWidget(
                    participants: stageStripParticipants,
                  ),
                ),
              BreakoutStatusInformation(),
              if (dominantSpeaker != null)
                Expanded(
                  child: _buildFeaturedParticipant(dominantSpeaker),
                ),
            ],
            SizedBox(height: 10),
          ],
        );
      },
    );
  }

  Widget _buildFeaturedScreenShare(AgoraParticipant participant) {
    return Padding(
      padding: const EdgeInsets.all(kVideoTileMargin),
      child: ParticipantWidget(
        globalKey: ValueKey('${participant.userId}-screen-share'),
        participant: participant,
        isScreenShare: true,
        borderRadius: BorderRadius.circular(kVideoTileRadius),
      ),
    );
  }

  Widget _buildFeaturedParticipant(AgoraParticipant participant) {
    return Padding(
      padding: const EdgeInsets.all(kVideoTileMargin),
      child: ParticipantWidget(
        globalKey: ValueKey(participant.userId),
        participant: participant,
        borderRadius: BorderRadius.circular(kVideoTileRadius),
      ),
    );
  }

  /// The three reactions, behind one button.
  ///
  /// The menu is built by the Navigator's overlay, which is a different
  /// subtree from this bar, so EmojiButton's `context.read<ChatModel>()`
  /// would not find the provider. It is captured here, where it is in scope,
  /// and handed to the menu explicitly.
  /// Only call where chat is enabled. EventTabsWrapper provides ChatModel
  /// conditionally, so this throws rather than degrading when it is off.
  /// Height of the reaction sheet, so it can be placed clear of the button
  /// rather than over it -- while it covered the button, tapping there hit a
  /// reaction instead of dismissing.
  ///
  /// Three [EmojiButton]s (a 32px glyph with 8px above and below), two 8px
  /// gaps, and 6px of padding top and bottom.
  static const double _kReactionSheetHeight = 3 * 48 + 2 * 8 + 2 * 6;

  final MenuController _reactionMenuController = MenuController();

  Widget _buildEmojiButton(
    BuildContext context,
    double iconSize,
    double touchTarget,
  ) {
    final chatModel = context.read<ChatModel>();

    return MenuAnchor(
      controller: _reactionMenuController,
      // So a tap on the button while the sheet is open only closes it; left
      // to fall through, it would close and immediately reopen.
      consumeOutsideTap: true,
      // Above the button, clear of it by 8.
      alignmentOffset: Offset(0, -(touchTarget + 8 + _kReactionSheetHeight)),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(
          context.theme.colorScheme.surfaceContainerLowest,
        ),
        // Rounded like a sheet rather than a menu -- it is a little palette,
        // not a list of commands.
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
      ),
      menuChildren: [
        // The sheet renders in an Overlay, outside this subtree, so the model
        // has to be handed across rather than looked up.
        ChangeNotifierProvider<ChatModel>.value(
          value: chatModel,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              EmojiButton(emoji: EmotionType.thumbsUp),
              SizedBox(height: 8),
              EmojiButton(emoji: EmotionType.heart),
              SizedBox(height: 8),
              EmojiButton(emoji: EmotionType.laughWithTears),
            ],
          ),
        ),
      ],
      builder: (context, controller, _) => AppClickableWidget(
        tooltipMessage:
            controller.isOpen ? 'Close reactions' : 'Send a reaction',
        padding: EdgeInsets.zero,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        // Sized to the same square as chat and the hand beside it; the icon
        // itself stays put.
        child: SizedBox(
          width: touchTarget,
          height: touchTarget,
          child: Icon(
            Icons.add_reaction_outlined,
            size: iconSize,
            color: context.theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  void _openChat(EventTabsControllerState tabsController) {
    tabsController.openTab(TabType.chat);
    _presenter.toggleBottomSheetState(
      LiveMeetingMobileBottomSheetState.fullyVisible,
    );
  }

  Widget _buildBottomNavBar() {
    context.watch<LiveMeetingProvider>();

    // Still guarded, but the store itself is no longer read here.
    if (MeetingGuideCardStore.watch(context) == null) {
      return const SizedBox.shrink();
    }
    final tabsController = context.watch<EventTabsControllerState>();

    const kIconSize = 24.0;
    // Chat, hand and reactions are the three controls people reach for mid
    // call, and at icon size plus the default inset they were a ~40px target.
    // Many of our participants are older; 45 is the smallest square that's
    // comfortable to hit without looking.
    const kTouchTarget = 45.0;
    final isVideoOn = _presenter.isVideoOn();
    final isMicOn = _presenter.isMicOn();
    final isAudioTemporarilyDisabled = _presenter.isAudioTemporarilyDisabled();
    final isRaisedHandVisible = _presenter.isRaisedHandVisible(context);
    final isCardPending = _presenter.isCardPending();
    final isChatOpen = tabsController.isTabOpen(TabType.chat) &&
        _model.bottomSheetState ==
            LiveMeetingMobileBottomSheetState.fullyVisible;

    // No participant-details stream any more: the readiness tally moved into
    // the agenda panel, and nothing left in this bar depends on it.
    return Container(
      // Matches the desktop control bar: follows the theme rather than
      // being fixed near-black in both modes.
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: AppNeutralColors.of(context).neutral300),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 20,
            ),
            child: Row(
              children: [
                // HtmlElementView video tiles can steal taps on Flutter web.
                PointerInterceptor(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppClickableWidget(
                        // Tooltip doubles as the accessible name (WCAG):
                        // these are icon-only controls.
                        tooltipMessage:
                            isVideoOn ? 'Turn camera off' : 'Turn camera on',
                        child: Icon(
                          isVideoOn
                              ? Icons.videocam_outlined
                              : Icons.videocam_off_outlined,
                          color: isVideoOn
                              ? context.theme.colorScheme.onSurface
                              : context.theme.colorScheme.errorContainer,
                          size: kIconSize,
                        ),
                        // Same handler as the mic button: alertOnError showed
                        // raw exception text (e.g. TimeoutException) for
                        // camera failures instead of the mapped AV copy.
                        onTap: () async =>
                            await AudioVideoErrorDialog.showOnError(
                          context,
                          () => _presenter.toggleVideo(),
                        ),
                      ),
                      SizedBox(width: 10),
                      AppClickableWidget(
                        tooltipMessage:
                            isMicOn ? 'Mute microphone' : 'Unmute microphone',
                        onTap: isAudioTemporarilyDisabled
                            ? () => showRegularToast(
                                  context,
                                  'All participants are muted during video!',
                                  toastType: ToastType.success,
                                )
                            : () => AudioVideoErrorDialog.showOnError(
                                  context,
                                  () => _presenter.toggleAudio(),
                                ),
                        child: Icon(
                          isMicOn ? Icons.mic_outlined : Icons.mic_off_outlined,
                          size: kIconSize,
                          color: isMicOn
                              ? context.theme.colorScheme.onSurface
                              : context.theme.colorScheme.errorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                PopupMenuButton<FutureOr<void> Function()>(
                  itemBuilder: (menuContext) {
                    // These moved out of the top bar, which had grown to
                    // seven unlabelled icons. As text items they're also
                    // self-describing, which the icons weren't.
                    //
                    // Derived here rather than reused from _buildAppBar:
                    // that's a separate method, and the popup's
                    // itemBuilder runs with its own context when opened.
                    final tabs = Provider.of<EventTabsControllerState>(
                      context,
                      listen: false,
                    );
                    // listen: false throughout -- itemBuilder runs
                    // outside the widget tree's build phase, and a
                    // listening Provider lookup here throws, which is why
                    // the menu silently failed to open.
                    final showShareButton = _presenter.isScreenShareEnabled();
                    final isScreenSharing = ConferenceRoom.read(
                          context,
                        )?.isLocalSharingScreenActive ??
                        false;
                    final suppressGuide =
                        ConferenceRoom.read(context) == null ||
                            Provider.of<AgendaProvider>(
                              context,
                              listen: false,
                            ).agendaItems.isEmpty;
                    final conferenceRoom = ConferenceRoom.read(context);
                    return [
                      if (tabs.widget.enableGuide && !suppressGuide)
                        PopupMenuItem(
                          value: () {
                            tabs.openTab(TabType.guide);
                            _presenter.toggleBottomSheetState(
                              LiveMeetingMobileBottomSheetState.fullyVisible,
                            );
                          },
                          child: HeightConstrainedText('Agenda'),
                        ),
                      if (showShareButton)
                        PopupMenuItem(
                          value: () => alertOnError(
                            context,
                            () => _presenter.toggleScreenShare(),
                          ),
                          child: HeightConstrainedText(
                            isScreenSharing
                                ? 'Stop sharing screen'
                                : 'Share screen',
                          ),
                        ),
                      if (tabs.widget.enableAdminPanel) _adminMenuItem(tabs),
                      PopupMenuItem(
                        value: () async {
                          if (conferenceRoom == null) return;
                          await AudioVideoSettingsDialog(
                            conferenceRoom: conferenceRoom,
                          ).show();
                        },
                        child: HeightConstrainedText(
                          'Audio/Video Settings',
                        ),
                      ),
                      _refreshMenuItem(context),
                    ];
                  },
                  onSelected: (itemAction) => itemAction(),
                  child: Icon(
                    Icons.more_vert,
                    size: kIconSize,
                    color: context.theme.colorScheme.onSurface,
                  ),
                ),
                Spacer(),
                if (isCardPending) ...[
                  CountdownWidget(),
                  SizedBox(width: 10),
                ],
                // Chat, hand and emoji, right-aligned as a group. The
                // advance control that used to sit here has moved into
                // the agenda panel -- testers read the two as duplicates.
                // Hand, then chat, then reactions. The hand is the one
                // that's time-critical -- it's a request to speak now -- so
                // it sits at the near edge of the group.
                if (isRaisedHandVisible)
                  AppClickableWidget(
                    tooltipMessage:
                        _presenter.isHandRaised() ? 'Lower hand' : 'Raise hand',
                    padding: EdgeInsets.zero,
                    child: SizedBox(
                      width: kTouchTarget,
                      height: kTouchTarget,
                      child: Center(
                        child: ProxiedImage(
                          null,
                          asset: AppAsset.raisedHand(),
                          width: kIconSize,
                          height: kIconSize,
                        ),
                      ),
                    ),
                    onTap: () => _presenter.toggleHandRaise(),
                  ),
                // A reaction is a chat message, so it needs the same gate the
                // chat button has: with chat off there is no ChatModel to send
                // through, and reading one that isn't provided throws.
                if (tabsController.widget.enableChat) ...[
                  if (isRaisedHandVisible) SizedBox(width: 4),
                  Builder(
                    builder: (context) {
                      // ChatModel is only provided when chat is enabled, so
                      // this stays inside the same guard the button does.
                      final unread =
                          context.watch<ChatModel>().numUnreadMessages;
                      return AppClickableWidget(
                        // The dot is the visual half of this; the tooltip is
                        // the control's accessible name, so it carries both
                        // what a tap will do and what the dot is saying.
                        tooltipMessage: isChatOpen
                            ? 'Close chat'
                            : unread == 0
                                ? 'Chat'
                                : unread == 1
                                    ? 'Chat, 1 unread message'
                                    : 'Chat, $unread unread messages',
                        padding: EdgeInsets.zero,
                        child: UnreadDot(
                          show: unread > 0,
                          background:
                              context.theme.colorScheme.surfaceContainerLowest,
                          child: SizedBox(
                            width: kTouchTarget,
                            height: kTouchTarget,
                            child: Icon(
                              Icons.forum_outlined,
                              size: kIconSize,
                              color: context.theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        // Toggles, like the hand beside it. Closing goes back
                        // to the agenda rather than just dropping the panel,
                        // which is what the panel's own X does.
                        onTap: () => isChatOpen
                            ? _presenter.openGuide()
                            : _openChat(tabsController),
                      );
                    },
                  ),
                  SizedBox(width: 4),
                  _buildEmojiButton(context, kIconSize, kTouchTarget),
                ],
                // No reopen button: the panel always leaves its handle
                // on screen, so there is nothing to restore.
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LiveMeetingBottomSheet extends StatefulWidget {
  final LiveMeetingMobileBottomSheetState bottomSheetState;
  final void Function(LiveMeetingMobileBottomSheetState) onChange;
  final void Function()? onClose;

  /// Drag is reported to the parent because the parent positions this panel
  /// and therefore owns its height.
  ///
  /// Optional: where this panel is laid out with Expanded the parent has no
  /// height to give it, so it falls back to detecting a swipe and changing
  /// state on release.
  final void Function()? onDragStart;
  final void Function(double deltaY, {required bool canRetract})? onDragUpdate;

  /// [velocityY] is positive downward; a fast flick commits in that direction
  /// rather than snapping to whatever stop happens to be nearest.
  final void Function(double velocityY)? onDragEnd;

  const LiveMeetingBottomSheet({
    Key? key,
    required this.bottomSheetState,
    required this.onChange,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onClose,
  }) : super(key: key);

  @override
  State<LiveMeetingBottomSheet> createState() => _LiveMeetingBottomSheetState();
}

class _LiveMeetingBottomSheetState extends State<LiveMeetingBottomSheet> {
  /// Whether this panel may be pulled shut at all. Some tabs pin it open --
  /// a word cloud is unusable at a peek, and a dismissable tab has its own
  /// close affordance.
  bool _canRetract() {
    final eventTabsController =
        Provider.of<EventTabsControllerState>(context, listen: false);
    final selectedTabIndex =
        eventTabsController.selectedTabController.selectedIndex;
    final selectedTab = eventTabsController.tabs[selectedTabIndex];
    final isWordCloud = selectedTab == TabType.guide &&
        MeetingGuideCardStore.read(context)?.meetingGuideCardAgendaItem?.type ==
            AgendaItemType.wordCloud;

    return widget.onClose == null && !isWordCloud;
  }

  /// Start of the gesture, for the swipe fallback only.
  Offset? _swipeStart;
  Offset? _swipeCurrent;

  void _onSwipeEnd() {
    final start = _swipeStart?.dy;
    final end = _swipeCurrent?.dy;
    if (start == null || end == null) return;

    if (_canRetract() && start < end) {
      widget.onChange(
        widget.bottomSheetState ==
                LiveMeetingMobileBottomSheetState.fullyVisible
            ? LiveMeetingMobileBottomSheetState.partiallyVisible
            : LiveMeetingMobileBottomSheetState.peek,
      );
    } else if (start > end) {
      widget.onChange(
        widget.bottomSheetState == LiveMeetingMobileBottomSheetState.peek
            ? LiveMeetingMobileBottomSheetState.partiallyVisible
            : LiveMeetingMobileBottomSheetState.fullyVisible,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final onDragUpdate = widget.onDragUpdate;
    final onDragEnd = widget.onDragEnd;
    // Where the parent owns the height, the panel tracks the finger. Where it
    // doesn't, fall back to detecting the swipe's direction on release.
    final canTrackFinger = onDragUpdate != null && onDragEnd != null;

    return GestureDetector(
      onVerticalDragStart: (details) {
        if (canTrackFinger) {
          widget.onDragStart?.call();
        } else {
          _swipeStart = details.globalPosition;
        }
      },
      onVerticalDragUpdate: (details) {
        if (canTrackFinger) {
          onDragUpdate(details.delta.dy, canRetract: _canRetract());
        } else {
          _swipeCurrent = details.globalPosition;
        }
      },
      onVerticalDragEnd: (details) {
        if (canTrackFinger) {
          onDragEnd(details.velocity.pixelsPerSecond.dy);
        } else {
          _onSwipeEnd();
        }
      },
      onVerticalDragCancel: () {
        if (canTrackFinger) onDragEnd(0);
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pillWidth = size.width / 3.5;

    final localOnClose = widget.onClose;

    return PointerInterceptor(
      child: Container(
        decoration: BoxDecoration(
          color: context.theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          boxShadow: [
            // Cast upward: this panel rises over the content behind it, so
            // a rightward shadow read as though it were a side drawer.
            BoxShadow(
              blurRadius: 8,
              offset: Offset(0, -2),
              color: Colors.black.withOpacity(0.25),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (localOnClose == null)
              _buildHandle(context, pillWidth: pillWidth)
            else
              Align(
                alignment: Alignment.centerRight,
                child: CustomInkWell(
                  onTap: () => localOnClose(),
                  boxShape: BoxShape.circle,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(
                      Icons.close,
                      // It sits on the sheet's surface, so it takes that
                      // surface's foreground. onPrimary is white and
                      // onPrimaryContainer near-white in light mode -- both
                      // were nearly invisible on the grey panel.
                      color: context.theme.colorScheme.onSurface,
                      size: 20,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _buildSelectedContent(context),
            ),
          ],
        ),
      ),
    );
  }

  /// The grab affordance at the top of the panel.
  ///
  /// At full height the panel is laid out with Expanded rather than a height
  /// the parent controls, so it can't be dragged -- it collapses on a tap.
  /// A chevron says that; the drag pill would be a lie.
  Widget _buildHandle(BuildContext context, {required double pillWidth}) {
    final isFullyVisible = widget.bottomSheetState ==
        LiveMeetingMobileBottomSheetState.fullyVisible;
    final color = context.theme.colorScheme.onPrimaryContainer;

    if (!isFullyVisible) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: _kSheetHandlePadding),
          Center(
            child: Container(
              width: pillWidth,
              height: _kSheetHandleHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: color,
              ),
            ),
          ),
          SizedBox(height: _kSheetHandlePadding),
        ],
      );
    }

    return Semantics(
      button: true,
      label: 'Collapse agenda',
      child: CustomInkWell(
        onTap: _canRetract()
            ? () => widget.onChange(
                  LiveMeetingMobileBottomSheetState.partiallyVisible,
                )
            : null,
        // Occupies exactly the pill block's height, so the content below
        // doesn't shift as the panel crosses into its full state.
        child: SizedBox(
          height: _kSheetHandleBlockHeight,
          child: Center(
            child: Icon(Icons.keyboard_arrow_down, color: color, size: 26),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedContent(BuildContext context) {
    final eventTabsController = Provider.of<EventTabsControllerState>(context);

    final selectedTabIndex =
        eventTabsController.selectedTabController.selectedIndex;
    final selectedTab = eventTabsController.tabs[selectedTabIndex];

    if (selectedTab == TabType.chat) {
      return ChatWidget(
        parentPath: context.watch<ChatModel>().parentPath,
        messageInputHint: 'Say something',
        allowBroadcast:
            context.watch<EventPermissionsProvider>().canBroadcastChat,
      );
    } else if (selectedTab == TabType.suggestions) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: UserSubmittedAgenda(),
      );
    } else if (selectedTab == TabType.admin) {
      return AdminPanel(
        padding: EdgeInsets.symmetric(horizontal: kMeetingPanelInset),
      );
    } else {
      return MeetingGuideCardContent(
        // Retracted, the panel has room for the title row and nothing else --
        // the body and the advance bar would overflow the peek height.
        isCollapsed:
            widget.bottomSheetState == LiveMeetingMobileBottomSheetState.peek,
        onMinimizeCard: () => widget.onChange(
          LiveMeetingMobileBottomSheetState.hidden,
        ),
      );
    }
  }
}

/// Rebuilds [builder] on ConferenceRoom notifies without dirtying ancestors.
/// Chat TextFields must live outside this widget.
class _ConferenceRoomRebuild extends StatelessWidget {
  final WidgetBuilder builder;

  const _ConferenceRoomRebuild({required this.builder});

  @override
  Widget build(BuildContext context) {
    ConferenceRoom.watchOrNull(context);
    return builder(context);
  }
}

class ParticipantsWidget extends StatelessWidget {
  final List<AgoraParticipant> participants;

  const ParticipantsWidget({
    Key? key,
    required this.participants,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        return AspectRatio(
          aspectRatio: 1.0,
          child: Padding(
            // Thinner than the grid's gutter: this strip is short, so the
            // margin costs a larger share of each tile.
            padding: const EdgeInsets.all(_kParticipantStripGutter),
            child: ParticipantWidget(
              globalKey: ValueKey(participant.userId),
              participant: participant,
              borderRadius: BorderRadius.circular(kVideoTileRadius),
            ),
          ),
        );
      },
    );
  }
}

class BreakoutRoomLoader extends StatelessWidget {
  final WidgetBuilder liveMeetingBuilder;

  const BreakoutRoomLoader({
    Key? key,
    required this.liveMeetingBuilder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomStreamBuilder(
      entryFrom: '_RefreshableBreakoutRoomState.build',
      stream: Provider.of<LiveMeetingProvider>(context)
          .breakoutRoomLiveMeetingStream,
      loadingMessage: 'Loading breakout room. Please wait...',
      builder: (context, __) {
        return liveMeetingBuilder(context);
      },
    );
  }
}
