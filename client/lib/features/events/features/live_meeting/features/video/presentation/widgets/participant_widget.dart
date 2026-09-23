import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:client/core/utils/js_interop_bridge.dart';
import 'package:client/core/utils/platform_utils.dart';
import 'package:universal_html/html.dart' as html;
import 'package:client/core/data/services/logging_service.dart';
import 'package:client/core/widgets/custom_loading_indicator.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:flutter/cupertino.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/widgets/video_overlay_colors.dart';
import 'package:flutter/material.dart';
import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/providers/meeting_guide_card_store.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/conference_room.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_agenda/data/providers/meeting_agenda_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/features/user/presentation/views/profile_tab.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/features/user/data/providers/user_info_builder.dart';
import 'package:client/features/user/presentation/widgets/user_profile_chip.dart';
import 'package:client/services.dart';
import 'package:client/styles/app_asset.dart';
import 'package:client/core/utils/dialogs.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/utils/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../data/providers/agora_room.dart';

class GlobalKeyedSubtree extends StatelessWidget {
  static final Map<String, GlobalKey> _globalKeys = {};

  final String label;
  final Widget child;

  const GlobalKeyedSubtree({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _globalKeys[label] ??= GlobalKey(debugLabel: label),
      child: child,
    );
  }
}

/// Inset and radius shared by every video tile, so the gallery and the
/// featured views read as the same kind of object.
const double kVideoTileMargin = 9;
const double kVideoTileRadius = 12;

class ParticipantWidget extends StatefulWidget {
  static final aspectRatio = Size(16, 9).aspectRatio;

  final Key globalKey;
  final AgoraParticipant participant;
  final bool isScreenShare;
  final BorderRadius borderRadius;

  const ParticipantWidget({
    required this.globalKey,
    required this.participant,
    this.isScreenShare = false,
    this.borderRadius = BorderRadius.zero,
  }) : super(key: globalKey);

  @override
  _ParticipantWidgetState createState() => _ParticipantWidgetState();
}

class _ParticipantWidgetState extends State<ParticipantWidget> {
  /// Ring drawn around a tile while its participant is the dominant speaker,
  /// replacing the small badge that used to sit in the name row. A whole-tile
  /// outline is legible at a glance across a grid; a 20px badge was not.
  /// Foreground for the video-off placeholder. The tile behind it is a
  /// constant midtone in both themes, so a token that flips with the theme
  /// (this was colorScheme.secondary) goes dark-on-grey in light mode.
  static const _kVideoOffForeground = AppNeutralColors.neutral50;

  /// The muted-mic glyph sits on the tile's dark scrim, which likewise doesn't
  /// lighten under a dark theme. This is the dark scheme's error red, pinned:
  /// light mode's is #a0000b, near-invisible on that scrim.
  static const _kMutedMicColor = Color(0xFFFFB4AB);

  static const _kSpeakingRingColor = AppAccentColors.violet;
  static const _kSpeakingRingWidth = 4.0;
  static const _kSpeakingRingGap = 2.0;

  Timer? _startedTimer;
  Timer? _showParticipantTimer;

  ConferenceRoom get conferenceRoom => ConferenceRoom.watch(context);

  bool get isDominant =>
      conferenceRoom.dominantSpeakerSid == widget.participant.userId;

  bool get isRemote => widget.participant.agoraUid != 0;

  bool get videoEnabled {
    if (widget.isScreenShare) return true;
    return widget.participant.videoTrackEnabled;
  }

  bool get _isNewlyConnected {
    final timer = conferenceRoom
        .participantInitializationTimers[widget.participant.userId];
    return timer?.isActive ?? false;
  }

  bool get audioEnabled => isRemote
      ? _isRemoteAudioEnabled(widget.participant.userId)
      : conferenceRoom.audioEnabled;

  bool get isStarted => widget.participant.videoTrackEnabled;

  bool _isRemoteAudioEnabled(String participantId) {
    final hasMuteOverride = EventProvider.watch(context)
        .eventParticipants
        .any((d) => d.id == participantId && d.muteOverride);
    return !hasMuteOverride && (widget.participant.audioTrackEnabled);
  }

  bool _showName = false;

  @override
  void dispose() {
    loggingService.log('disposing ${widget.participant.userId}');
    _startedTimer?.cancel();
    _showParticipantTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (isStarted) {
      _startedTimer ??= Timer(Duration(seconds: 2), () => setState(() {}));
    }
  }

  Widget _buildVideoElement() {
    Widget videoWidget;
    if (widget.participant is FakeParticipant) {
      videoWidget = Container(color: Colors.orange);
    } else if (isRemote) {
      final rtcEngine = conferenceRoom.room?.engineIfReady;
      if (rtcEngine == null) {
        videoWidget = const ColoredBox(color: Color(0xFF1A1A1A));
      } else {
        // Dual-engine: dedicated screen UID. Canvas compositor: composite on camera UID.
        // Native single-engine: screen-source slot only (see LiveMeeting.screenSharePath).
        final screenUid = widget.participant.screenAgoraUid;
        final renderUid = (widget.isScreenShare && screenUid != null)
            ? screenUid
            : widget.participant.agoraUid;
        final sourceType = (widget.isScreenShare &&
                screenUid == null &&
                !kIsWeb &&
                conferenceRoom.screenSharePath ==
                    LiveMeeting.screenSharePathSingle)
            ? VideoSourceType.videoSourceScreen
            : null;
        videoWidget = AgoraVideoView(
          // Keyed on the reconnect generation: after a web reconnect iris can
          // fail to re-attach the remote track to the old platform view
          // (black tile with frames still arriving); a fresh view re-attaches.
          key: ValueKey(
            'remote-video-$renderUid-'
            'g${conferenceRoom.room?.remoteVideoViewGeneration ?? 0}',
          ),
          controller: VideoViewController.remote(
            rtcEngine: rtcEngine,
            canvas: VideoCanvas(uid: renderUid, sourceType: sourceType),
            connection: RtcConnection(channelId: conferenceRoom.roomName),
          ),
        );
      }
    } else if (widget.isScreenShare) {
      // Local screen share tile.
      final screenEng = widget.participant.screenEngine;
      if (screenEng != null) {
        // Native dual-engine: render via the dedicated screen engine.
        videoWidget = AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: screenEng,
            canvas: const VideoCanvas(uid: 0),
          ),
          onAgoraVideoViewCreated: (viewId) {
            if (!mounted) return;
            if (!widget.participant.isScreenSharing) return;
            final eng = widget.participant.screenEngine;
            if (eng == null) return;
            unawaited(() async {
              if (!mounted) return;
              try {
                await eng.startPreview(
                  sourceType: VideoSourceType.videoSourceScreen,
                );
              } catch (e, st) {
                loggingService.log(
                  'Screen share local preview: startPreview failed: $e\n$st',
                  logType: LogType.error,
                );
              }
            }());
          },
        );
      } else if (kIsWeb) {
        // Canvas compositor path — local user's big screen-share tile.
        //
        // IMPORTANT: Do NOT create an AgoraVideoView(uid: 0) here.  The sidebar
        // already contains one AgoraVideoView(uid: 0) for the local camera tile.
        // Two simultaneous views on the same UID cause iris-web to repeatedly
        // call setupLocalVideo + startPreview, which internally calls
        // sender.replaceTrack(cameraTrack), overwriting the canvas compositor
        // track and making the compositor stop within seconds.
        //
        // Instead, show a live canvas preview so the user can immediately
        // confirm which window/tab they're sharing.  No AgoraVideoView is
        // created here, preventing the double-setupLocalVideo conflict.
        final previewSlot =
            widget.participant.webCanvasCompositorPreviewViewType;
        videoWidget = previewSlot == null
            ? Container(color: const Color(0xFF1A1A1A))
            : _CanvasCompositorPreviewTile(
                platformViewType: previewSlot,
                shareLabel: jsGetCanvasShareLabel(),
              );
      } else {
        final rtcEngine = conferenceRoom.room?.engineIfReady;
        if (rtcEngine == null) {
          videoWidget = const ColoredBox(color: Color(0xFF1A1A1A));
        } else {
          // Native single-engine fallback for legacy deployments.
          videoWidget = AgoraVideoView(
            controller: VideoViewController(
              rtcEngine: rtcEngine,
              canvas: VideoCanvas(
                uid: 0,
                sourceType: VideoSourceType.videoSourceScreen,
              ),
            ),
            onAgoraVideoViewCreated: (viewId) {
              if (!mounted) return;
              if (!widget.participant.isScreenSharing) return;
              final eng = ConferenceRoom.read(context)?.room?.engineIfReady;
              if (eng == null) return;
              unawaited(() async {
                if (!mounted) return;
                try {
                  await eng.startPreview(
                    sourceType: VideoSourceType.videoSourceScreen,
                  );
                } catch (e, st) {
                  loggingService.log(
                    'Screen share local preview (single-engine): startPreview failed: $e\n$st',
                    logType: LogType.error,
                  );
                }
              }());
            },
          );
        }
      }
    } else {
      final rtcEngine = conferenceRoom.room?.engineIfReady;
      if (rtcEngine == null) {
        videoWidget = const ColoredBox(color: Color(0xFF1A1A1A));
      } else {
        videoWidget = AgoraVideoView(
          controller: VideoViewController(
            rtcEngine: rtcEngine,
            canvas: const VideoCanvas(uid: 0),
          ),
          onAgoraVideoViewCreated: (viewId) {
            // Web: after breakout ↔ main swaps (or any rebuild that disposes this
            // subtree), a new platform view is created while Agora may still think
            // preview is "started". Re-run startPreview so capture binds to the
            // new div (enableVideo skips startPreview when videoLocalPreviewStarted).
            if (!mounted) return;
            if (!kIsWeb || isRemote || !widget.participant.videoTrackEnabled) {
              return;
            }
            // Avoid startPreview while enableVideo(off) reset preview state but
            // videoTrackEnabled is not yet false (teardown can still be in flight).
            if (!widget.participant.videoLocalPreviewStarted) {
              return;
            }
            // Canvas compositor only: startPreview would replaceTrack(cameraTrack)
            // and kill the compositor. Dual-engine screen share still needs preview
            // rebound on this uid:0 tile after layout rebuilds.
            if (kIsWeb &&
                widget.participant.webCanvasCompositorPreviewViewType != null) {
              return;
            }
            final engine = ConferenceRoom.read(context)?.room?.engineIfReady;
            if (engine == null) return;
            unawaited(() async {
              if (!mounted) return;
              try {
                await engine.startPreview();
              } catch (e, st) {
                loggingService.log(
                  'Local AgoraVideoView: startPreview after view create failed: $e\n$st',
                  logType: LogType.error,
                );
              }
            }());
          },
        );
      }
    }

    return videoWidget;
  }

  Widget _buildVideo() {
    if (widget.isScreenShare) {
      final screenUid = widget.participant.screenAgoraUid;
      final renderUid =
          (screenUid != null) ? screenUid : widget.participant.agoraUid;

      var aspect = 16 / 9;
      var fromAgora = conferenceRoom.room?.videoFrameSize(renderUid);
      if (fromAgora == null &&
          !isRemote &&
          widget.isScreenShare &&
          userService.currentUserId != null) {
        fromAgora = conferenceRoom.room
            ?.videoFrameSize(uidToInt(userService.currentUserId!));
      }
      // Native screen-engine preview uses VideoCanvas(uid: 0); sizes land under 0.
      if (fromAgora == null && !isRemote && widget.isScreenShare) {
        fromAgora = conferenceRoom.room?.videoFrameSize(0);
      }
      if (fromAgora != null && fromAgora.width > 0 && fromAgora.height > 0) {
        aspect = fromAgora.width / fromAgora.height;
      } else if (kIsWeb && !isRemote && widget.participant.isScreenSharing) {
        final px = jsGetCanvasCompositorPixelSize();
        if (px != null && px.length >= 2 && px[0] > 0 && px[1] > 0) {
          aspect = px[0] / px[1];
        }
      }

      return RepaintBoundary(
        child: AspectRatio(
          aspectRatio: aspect,
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: 480 * aspect,
                height: 480,
                child: _buildVideoElement(),
              ),
            ),
          ),
        ),
      );
    }

    final dimensions = Size(854.0, 480.0);

    var fit = BoxFit.contain;
    // If the aspect ratio is close to 16:9 or 4:3 or somewhere in between
    // cover the whole area. Otherwise, fit it within the bounds
    if (dimensions.aspectRatio <= Size(17, 9).aspectRatio &&
        dimensions.aspectRatio >= Size(3.5, 3).aspectRatio &&
        !widget.isScreenShare) {
      fit = BoxFit.cover;
    }

    return RepaintBoundary(
      child: FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          height: dimensions.height,
          width: dimensions.width,
          child: _buildVideoElement(),
        ),
      ),
    );
  }

  Widget _buildMutedOverlayEntry() {
    return Icon(
      Icons.mic_off_outlined,
      color: _kMutedMicColor,
      size: 17,
    );
  }

  Widget _buildOverlay() {
    final store = MeetingGuideCardStore.watch(context);
    final conferenceRoom = ConferenceRoom.watchOrNull(context);
    if (store == null || conferenceRoom == null) {
      return const SizedBox.shrink();
    }
    final isMobile = responsiveLayoutService.isMobile(context);

    return Align(
      alignment: Alignment.bottomLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isMobile && !audioEnabled && !_showName) ...[
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: VideoOverlayColors.plate,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(5),
                ),
              ),
              child: _buildMutedOverlayEntry(),
            ),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: isMobile
                  ? _buildParticipantDetailsMobile()
                  : _buildParticipantDetails(),
            ),
          ),
          SizedBox(width: 3),
        ],
      ),
    );
  }

  /// A raised hand, in the tile's top-right corner.
  ///
  /// It used to sit beside the name plate along the bottom edge. On mobile a
  /// pulled-up agenda panel covers the bottom of the tiles, so a hand going up
  /// was invisible to anyone reading the agenda -- which is most of the room,
  /// most of the time. Nothing else uses this corner.
  Widget _buildRaisedHandBadge() {
    final store = MeetingGuideCardStore.watch(context);
    final conferenceRoom = ConferenceRoom.watchOrNull(context);
    if (store == null || conferenceRoom == null) {
      return const SizedBox.shrink();
    }
    if (!store.getHandIsRaised(widget.participant.identity)) {
      return const SizedBox.shrink();
    }

    // Whoever raised first gets the distinct badge; everyone else gets a hand.
    final isUpNext =
        conferenceRoom.handRaisedParticipants.indexOf(widget.participant) == 0;
    final isMobile = responsiveLayoutService.isMobile(context);
    final size = isMobile ? 28.0 : 52.0;
    final margin = isMobile ? 4.0 : 8.0;

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.only(right: margin, top: margin),
        child: ProxiedImage(
          null,
          asset: isUpNext ? AppAsset.kUpNext : AppAsset.kHandRaise,
          width: size,
          height: size,
        ),
      ),
    );
  }

  Widget _buildParticipantDetailsMobile() {
    return _showName ? _buildParticipantDetails() : SizedBox.shrink();
  }

  Widget _buildParticipantDetails() {
    final showPin =
        context.watch<EventPermissionsProvider>().canPinItemInParticipantWidget;
    final showMute = context
        .watch<EventPermissionsProvider>()
        .canMuteParticipantInParticipantWidget(widget.participant.identity);
    final showKick = context
        .watch<EventPermissionsProvider>()
        .canKickParticipantInParticipantWidget(widget.participant.identity);

    return IntrinsicWidth(
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: VideoOverlayColors.plate,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: UserInfoBuilder(
                userId: widget.participant.identity,
                builder: (_, isLoading, snapshot) => HeightConstrainedText(
                  isLoading
                      ? 'Loading...'
                      : snapshot.data?.displayName ?? 'Participant',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.body.copyWith(
                    color: VideoOverlayColors.onPlate,
                  ),
                ),
              ),
            ),
            if (!audioEnabled) ...[
              SizedBox(width: 5),
              _buildMutedOverlayEntry(),
            ],
            SizedBox(width: 2),
            _ParticipantOptionsMenu(
              userId: widget.participant.identity,
              showPin: showPin,
              showMute: showMute,
              showKick: showKick,
              isVisible:
                  _showName || !responsiveLayoutService.isMobile(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showParticipantName() async {
    if (mounted) setState(() => _showName = true);
    _showParticipantTimer?.cancel();
    _showParticipantTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showName = false);
    });
  }

  /// Picks the high- or low-quality remote stream based on how large this
  /// tile is actually rendered (dual-stream mode; see
  /// AgoraRoom._applyBandwidthOptimizations). Small grid/strip tiles use the
  /// low stream, which cuts downlink bandwidth dramatically in large rooms.
  void _updateRemoteStreamPreference(BoxConstraints constraints) {
    if (!isRemote || widget.participant is FakeParticipant) return;
    final room = ConferenceRoom.read(context)?.room;
    if (room == null) return;

    final int uid;
    final VideoStreamType streamType;
    if (widget.isScreenShare) {
      // Screen content must stay readable — always take the high stream.
      uid = widget.participant.screenAgoraUid ?? widget.participant.agoraUid;
      streamType = VideoStreamType.videoStreamHigh;
    } else if (widget.participant.isScreenSharing &&
        widget.participant.screenAgoraUid == null) {
      // Web canvas compositor: the screen is composited onto the camera UID,
      // so the big screen tile and this camera tile share one UID. Keep it on
      // high so the two tiles don't fight over the stream type.
      uid = widget.participant.agoraUid;
      streamType = VideoStreamType.videoStreamHigh;
    } else {
      uid = widget.participant.agoraUid;
      final width =
          constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity;
      streamType = width >= kHighStreamMinTileWidth
          ? VideoStreamType.videoStreamHigh
          : VideoStreamType.videoStreamLow;
    }
    unawaited(room.setPreferredRemoteVideoStreamType(uid, streamType));
  }

  Widget _buildVideoDisabled({bool switchedOff = false}) {
    final isConnecting =
        _isNewlyConnected || (_startedTimer?.isActive ?? false);
    final isMobile = responsiveLayoutService.isMobile(context);

    return Container(
      // A constant midtone rather than a themed surface: the overlay controls
      // on this tile are constant white, so the tile behind them can't be
      // allowed to go near-white in light mode. 4.74:1 against white.
      color: AppNeutralColors.neutral500,
      child: Container(
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: IntrinsicHeight(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: isMobile ? 16 : 30),
              Flexible(
                child: Container(
                  constraints: BoxConstraints(maxHeight: 200, maxWidth: 200),
                  child: UserProfileChip(
                    userId: widget.participant.identity,
                    showName: false,
                    enableOnTap: false,
                    imageHeight: 200,
                    alignment: Alignment.center,
                  ),
                ),
              ),
              if (!isMobile) SizedBox(height: 10),
              if (isConnecting)
                HeightConstrainedText(
                  'Connecting...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kVideoOffForeground,
                    fontSize: isMobile ? 12 : 16,
                  ),
                )
              else if (switchedOff && (_startedTimer?.isActive ?? false))
                Container(
                  height: 20,
                  alignment: Alignment.center,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CustomLoadingIndicator(),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HeightConstrainedText(
                      'Video Off',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _kVideoOffForeground,
                        fontSize: isMobile ? 12 : 16,
                      ),
                    ),
                    if (switchedOff) ...[
                      SizedBox(width: 6),
                      Icon(
                        Icons.wifi_off,
                        color: _kVideoOffForeground,
                        size: isMobile ? 12 : 16,
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAspectRatioClipped(Widget child) {
    // No GlobalKeyedSubtree here — with ValueKey on the outer ParticipantWidget,
    // elements are preserved within the same parent on reorder without needing
    // cross-element GlobalKey moves. Using a static-label GlobalKey here caused
    // collisions when two VideoFlutterMeeting instances briefly coexisted.

    if (widget.isScreenShare) return child;

    if (widget.borderRadius != BorderRadius.zero) {
      // ignore: parameter_assignments
      child = ClipRRect(
        borderRadius: widget.borderRadius,
        child: child,
      );
    }

    // The ring's footprint is reserved whether or not it's showing, so tiles
    // don't jump size as the dominant speaker changes.
    final ringRadius = widget.borderRadius == BorderRadius.zero
        ? BorderRadius.zero
        : BorderRadius.circular(
            widget.borderRadius.topLeft.x + _kSpeakingRingGap +
                _kSpeakingRingWidth,
          );

    return AspectRatio(
      aspectRatio: ParticipantWidget.aspectRatio,
      child: Container(
        padding: const EdgeInsets.all(_kSpeakingRingGap),
        decoration: BoxDecoration(
          borderRadius: ringRadius,
          border: Border.all(
            color: isDominant ? _kSpeakingRingColor : Colors.transparent,
            width: _kSpeakingRingWidth,
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (ConferenceRoom.watchOrNull(context) == null) {
      return const SizedBox.shrink();
    }
    final isMobile = responsiveLayoutService.isMobile(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        _updateRemoteStreamPreference(constraints);
        return _buildTile(isMobile);
      },
    );
  }

  Widget _buildTile(bool isMobile) {
    return Listener(
      onPointerDown: isMobile ? (_) => _showParticipantName() : null,
      child: RepaintBoundary(
        child: _buildAspectRatioClipped(
          Container(
            // A constant dark backdrop for the video, not a role colour:
            // primaryColor happened to be neutral800 in both modes, so
            // mapping it to colorScheme.primary would turn this light.
            color: AppNeutralColors.neutral800,
            child: Container(
              color: context.theme.colorScheme.scrim.withScrimOpacity,
              child: AnimatedBuilder(
                animation: widget.participant,
                builder: (_, __) => Stack(
                  children: [
                    Container(),
                    if (videoEnabled)
                      Positioned.fill(
                        child: _buildVideo(),
                      ),
                    if (!videoEnabled)
                      Positioned.fill(
                        child: _buildVideoDisabled(),
                      ),
                    _buildOverlay(),
                    _buildRaisedHandBadge(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantOptionsMenu extends StatefulWidget {
  final String userId;
  final bool showPin;
  final bool showMute;
  final bool showKick;
  final bool isVisible;

  const _ParticipantOptionsMenu({
    required this.userId,
    required this.showPin,
    required this.showMute,
    required this.showKick,
    required this.isVisible,
  });

  @override
  State<_ParticipantOptionsMenu> createState() =>
      _ParticipantOptionsMenuState();
}

class _ParticipantOptionsMenuState extends State<_ParticipantOptionsMenu> {
  bool _isLoading = false;

  bool? _isPinnedLocal;
  bool _isHovered = false;

  final _menuKey = GlobalKey();

  List<PopupMenuEntry<Function()>> _getMenuItems({
    required BuildContext context,
  }) {
    final liveMeetingProvider = LiveMeetingProvider.read(context);
    final userId = widget.userId;
    final isPinned = _isPinnedLocal ??
        liveMeetingProvider.liveMeeting?.pinnedUserIds
            .any((id) => id == widget.userId) ??
        false;

    final liveMeeting = AgendaProvider.read(context).currentLiveMeeting;
    if (liveMeeting == null) return [];

    final isCurrentUser = userId == userService.currentUserId;

    return [
      if (widget.showPin)
        PopupMenuItem<Function()>(
          value: _isLoading
              ? null
              : () => alertOnError(context, () async {
                    final pinned = liveMeeting.pinnedUserIds.toSet();
                    if (isPinned) {
                      pinned.remove(userId);
                    } else {
                      pinned.add(userId);
                    }
                    setState(() => _isLoading = true);
                    try {
                      await firestoreLiveMeetingService.update(
                        liveMeetingPath:
                            AgendaProvider.read(context).liveMeetingPath,
                        liveMeeting: liveMeeting.copyWith(
                          pinnedUserIds: pinned.toList(),
                        ),
                        keys: [LiveMeeting.kFieldPinnedUserIds],
                      );
                    } finally {
                      setState(() {
                        _isLoading = false;
                      });
                    }
                    setState(() => _isPinnedLocal = !isPinned);
                  }),
          child: HeightConstrainedText(
            isPinned ? 'Unpin' : 'Pin',
            style: AppTextStyle.bodyMedium
                .copyWith(color: context.theme.colorScheme.primary),
          ),
        ),
      if (widget.showMute)
        PopupMenuItem<Function()>(
          value: () => alertOnError(
            context,
            () => liveMeetingProvider.mute(userId: userId),
          ),
          child: HeightConstrainedText(
            'Mute',
            style: AppTextStyle.bodyMedium
                .copyWith(color: context.theme.colorScheme.primary),
          ),
        ),
      if (widget.showKick)
        PopupMenuItem<Function()>(
          value: () => alertOnError(
            context,
            () => liveMeetingProvider.confirmProposeKick(userId),
          ),
          child: HeightConstrainedText(
            'Propose to remove user',
            style: AppTextStyle.bodyMedium
                .copyWith(color: context.theme.colorScheme.error),
          ),
        ),
      PopupMenuItem<Function()>(
        value: () => alertOnError(
          context,
          () => Dialogs.showAppDrawer(
            context,
            AppDrawerSide.right,
            ProfileTab(
              communityId: liveMeetingProvider.communityProvider.communityId,
              showTitle: true,
              allowEdit: isCurrentUser,
              currentUserId: userId,
            ),
          ),
        ),
        child: HeightConstrainedText(
          isCurrentUser ? 'Edit Profile' : 'View Profile',
          style: AppTextStyle.bodyMedium
              .copyWith(color: context.theme.colorScheme.primary),
        ),
      ),
    ];
  }

  Future<void> _showMoreMenu(List<PopupMenuEntry<Function()>> items) async {
    if (items.isEmpty) return;
    final button = _menuKey.currentContext?.findRenderObject();
    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    final resultFunction = await showMenu<Function()>(
      context: context,
      position: position,
      items: items,
    );

    if (resultFunction != null) {
      resultFunction();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPinned = _isPinnedLocal ??
        LiveMeetingProvider.read(context)
            .liveMeeting
            ?.pinnedUserIds
            .any((id) => id == widget.userId) ??
        false;
    return Semantics(
      label: context.l10n.participantActionsForUserWithId(widget.userId),
      child: CustomInkWell(
        onTap: widget.isVisible
            ? () => _showMoreMenu(_getMenuItems(context: context))
            : null,
        onHover: widget.isVisible
            ? (isHovered) => setState(() => _isHovered = isHovered)
            : null,
        child: Container(
          key: _menuKey,
          padding: const EdgeInsets.all(5),
          child: Icon(
            isPinned ? Icons.push_pin : CupertinoIcons.ellipsis,
            size: 16,
            // onSurfaceVariant is neutral700 in light mode -- dark grey on a
            // dark plate, which is what made these dots so hard to pick out.
            color: _isHovered
                ? VideoOverlayColors.onPlate
                : VideoOverlayColors.onPlateSubdued,
          ),
        ),
      ),
    );
  }
}

// ─── Canvas compositor preview tile ──────────────────────────────────────────

/// Shown in the local user's big screen-share tile while the canvas compositor
/// is active on web.  Embeds the live preview canvas via HtmlElementView.
///
/// A text badge with the surface type (and title when the browser exposes it)
/// is shown below the preview.
class _CanvasCompositorPreviewTile extends StatefulWidget {
  /// Per screen-share session — forces a new platform-view slot when Flutter
  /// reuses the previous slot after stop removed the canvas from the DOM.
  final String platformViewType;
  final String? shareLabel;
  const _CanvasCompositorPreviewTile({
    required this.platformViewType,
    this.shareLabel,
  });

  @override
  State<_CanvasCompositorPreviewTile> createState() =>
      _CanvasCompositorPreviewTileState();
}

class _CanvasCompositorPreviewTileState
    extends State<_CanvasCompositorPreviewTile> {
  static final Set<String> _registeredViewTypes = {};

  void _ensureFactoryRegistered() {
    if (!kIsWeb) return;
    final vt = widget.platformViewType;
    if (_registeredViewTypes.contains(vt)) return;
    _registeredViewTypes.add(vt);
    registerWebViewFactory(vt, (dynamic viewId) {
      final el = html.document.getElementById('canvas-compositor-preview');
      if (el != null) {
        // Canvas starts visibility:hidden in JS to avoid a full-page flash
        // before HtmlElementView moves it into this slot.
        if (el is html.HtmlElement) el.style.visibility = 'visible';
        return el;
      }
      return html.DivElement()
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = '#1A1A1A';
    });
  }

  @override
  void initState() {
    super.initState();
    _ensureFactoryRegistered();
  }

  @override
  void dispose() {
    _registeredViewTypes.remove(widget.platformViewType);
    super.dispose();
  }

  @override
  void didUpdateWidget(_CanvasCompositorPreviewTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.platformViewType != widget.platformViewType) {
      _ensureFactoryRegistered();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.shareLabel;
    return Container(
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: [
          // Live preview — fills available space, 16:9 aspect ratio preserved.
          Expanded(
            child: kIsWeb
                ? Semantics(
                    label: label != null && label.isNotEmpty
                        ? 'Live preview of shared screen: $label'
                        : 'Live preview of shared screen',
                    excludeSemantics: true,
                    child: HtmlElementView(viewType: widget.platformViewType),
                  )
                : const SizedBox.shrink(),
          ),
          // Bottom bar: icon + label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF111111),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.screen_share_outlined,
                    color: Colors.white54,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 6),
                HeightConstrainedText(
                  label != null && label.isNotEmpty
                      ? 'Sharing · $label'
                      : 'Sharing screen',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
