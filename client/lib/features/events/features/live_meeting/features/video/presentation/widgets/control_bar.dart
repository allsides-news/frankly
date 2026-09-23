import 'dart:async';

import 'package:client/core/utils/toast_utils.dart';
import 'package:client/features/community/utils/guard_utils.dart';
import 'package:flutter/material.dart';
import 'package:client/features/chat/data/providers/chat_model.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_permissions_provider.dart';
import 'package:client/features/events/features/event_page/presentation/event_tabs_model.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_error.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_settings.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/data/providers/meeting_guide_card_store.dart';
import 'package:client/features/events/features/live_meeting/features/video/data/providers/conference_room.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/talking_odometer.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_text_field.dart';
import 'package:client/features/user/data/providers/user_info_builder.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:client/core/data/services/logging_service.dart';
import 'package:client/services.dart';
import 'package:client/styles/app_asset.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/utils/extensions.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/utils/js_interop_bridge.dart';
import 'package:client/core/utils/platform_utils.dart';
import 'package:provider/provider.dart';

class ControlBar extends StatefulWidget {
  @override
  _ControlBarState createState() => _ControlBarState();
}

class _ControlBarState extends State<ControlBar> {
  /// True when this device/browser can start screen share (not just view it).
  late final bool _canvasCompositorScreenShareAvailable =
      jsCanInitiateScreenShare();

  LiveMeetingProvider get _liveMeetingProvider =>
      Provider.of<LiveMeetingProvider>(context);

  ConferenceRoom? get _conferenceRoomOrNull =>
      _liveMeetingProvider.conferenceRoom;

  ConferenceRoom? get _conferenceRoomReadOrNull =>
      LiveMeetingProvider.read(context).conferenceRoom;

  Future<void> _withConferenceRoom(
    Future<void> Function(ConferenceRoom room) action,
  ) async {
    final room = _conferenceRoomReadOrNull;
    if (room == null) return;
    await action(room);
  }

  Widget _buildScreenShareButton(ConferenceRoom room) {
    if (!room.isLocalSharingScreenActive && room.screenSharer != null) {
      return UserInfoBuilder(
        userId: room.screenSharerUserId,
        builder: (_, isLoading, snapshot) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 200),
          child: HeightConstrainedText(
            '${isLoading ? 'A participant' : snapshot.data?.displayName ?? 'A participant'} is screen sharing',
          ),
        ),
      );
    } else {
      return HeightConstrainedText(
        room.isLocalSharingScreenActive ? 'Stop Sharing' : 'Share Screen',
      );
    }
  }

  Widget _buildVideoToggle(ConferenceRoom room) {
    return _IconButton(
      onTap: () => AudioVideoErrorDialog.showOnError(
        context,
        () => _withConferenceRoom((r) => r.toggleVideoEnabled()),
      ),
      text: room.videoEnabled ? 'Stop Video' : 'Start Video',
      icon: room.videoEnabled
          ? Icons.videocam_outlined
          : Icons.videocam_off_outlined,
      iconColor: room.videoEnabled
          ? context.theme.colorScheme.onSurface
          : context.theme.colorScheme.errorContainer,
    );
  }

  Widget _buildMoreOptionsButton(ConferenceRoom room) {
    final enabled = !_liveMeetingProvider.audioTemporarilyDisabled;
    final canInitiateScreenShare =
        EventPermissionsProvider.read(context)?.canInitiateScreenShare ?? false;

    return CustomInkWell(
      child: PopupMenuButton<FutureOr<void> Function()>(
        itemBuilder: (context) {
          final current = _conferenceRoomReadOrNull ?? room;
          return [
            PopupMenuItem(
              value: () {
                final latest = _conferenceRoomReadOrNull;
                if (latest == null) return;
                AudioVideoSettingsDialog(conferenceRoom: latest).show();
              },
              child: HeightConstrainedText(
                'Audio/Video Settings',
              ),
            ),
            if (_canvasCompositorScreenShareAvailable &&
                context.read<EventProvider>().enableScreenshare &&
                canInitiateScreenShare)
              PopupMenuItem(
                enabled: enabled,
                value: enabled
                    ? () => alertOnError(
                          context,
                          () =>
                              _withConferenceRoom((r) => r.toggleScreenShare()),
                        )
                    : null,
                child: _buildScreenShareButton(current),
              ),
            // Moved off the video's top-right corner into here, where the
            // rest of the call's less-used controls already live.
            PopupMenuItem(
              value: () => LiveMeetingProvider.read(context).refreshMeeting(),
              child: HeightConstrainedText(context.l10n.refreshConnection),
            ),
          ];
        },
        onSelected: (itemAction) => itemAction(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: Icon(
            Icons.more_horiz,
            size: 32,
            // The control bar is primaryContainer, which stays dark in both
            // modes, so its foreground has to stay light in both. onPrimary
            // does not -- it is neutral800 under a dark theme.
            color: context.theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildScreenShareActiveButton() {
    return _IconButton(
      onTap: () => alertOnError(
        context,
        () => _withConferenceRoom(
          (r) => r.toggleScreenShare(setEnabled: false),
        ),
      ),
      text: 'Stop Sharing',
      icon: Icons.stop_screen_share_outlined,
      iconColor: context.theme.colorScheme.errorContainer,
    );
  }

  Widget _buildControlWidgets() {
    final conferenceRoom = _conferenceRoomOrNull;
    if (conferenceRoom == null) return const SizedBox.shrink();

    final enabled = !_liveMeetingProvider.audioTemporarilyDisabled;
    final isMobile = responsiveLayoutService.isMobile(context);
    final double spacerWidth = isMobile ? 6 : 12;
    // Also guard on conferenceRoom non-null: EventProvider rebuilds can trigger
    // _buildControlWidgets before the outer AnimatedBuilder null-guard re-evaluates,
    // causing TalkingOdometerPresenter to crash on conferenceRoom!.
    bool showTalkingTimer = !isMobile &&
        context.watch<EventProvider>().enableTalkingTimer &&
        _liveMeetingProvider.conferenceRoom != null;

    final enableScreenshare = context.watch<EventProvider>().enableScreenshare;
    final isScreenSharing = conferenceRoom.isLocalSharingScreenActive;

    // HtmlElementView video tiles sit in a separate overlay on Flutter web
    // and can steal taps from this bar.
    return CustomPointerInterceptor(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: spacerWidth),
          _buildVideoToggle(conferenceRoom),
          _IconButton(
            onTap: enabled
                ? () => AudioVideoErrorDialog.showOnError(
                      context,
                      () => _withConferenceRoom((r) => r.toggleAudioEnabled()),
                    )
                : () async {
                    showRegularToast(
                      context,
                      'All participants are muted during video!',
                      toastType: ToastType.success,
                    );
                  },
            text: conferenceRoom.audioEnabled ? 'Mute' : 'Unmute',
            icon: conferenceRoom.audioEnabled
                ? Icons.mic_outlined
                : Icons.mic_off_outlined,
            iconColor: conferenceRoom.audioEnabled
                ? context.theme.colorScheme.onSurface
                : context.theme.colorScheme.errorContainer,
          ),
          if (enableScreenshare &&
              isScreenSharing &&
              _canvasCompositorScreenShareAvailable)
            _buildScreenShareActiveButton(),
          _buildMoreOptionsButton(conferenceRoom),
          SizedBox(width: spacerWidth),
          if (showTalkingTimer) ...[
            TalkingOdometer(
              pillColor: context.theme.colorScheme.surfaceContainerHigh,
            ),
            SizedBox(width: spacerWidth),
          ],
        ],
      ),
    );
  }

  Widget _buildChatSectionWidgets() {
    return Flexible(child: ChatAndEmojisInput());
  }

  Widget _buildLeaveButton() {
    EdgeInsets padding = EdgeInsets.symmetric(horizontal: 26);

    return Container(
      alignment: Alignment.center,
      padding: padding,
      child: ActionButton(
        onPressed: () => LiveMeetingProvider.read(context).leaveMeeting(),
        text: 'Leave',
        color: context.theme.colorScheme.error,
        textColor: context.theme.colorScheme.onError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eventTabsControllerState =
        Provider.of<EventTabsControllerState>(context).widget;
    final isInLiveStreamLobby = EventProvider.watch(context).isLiveStream &&
        !LiveMeetingProvider.watch(context).isInBreakout;
    final isChatBarVisible = !isInLiveStreamLobby &&
        eventTabsControllerState.enableChat &&
        context.watch<EventProvider>().enableFloatingChat;
    return Container(
      // onPrimaryFixed is neutral900 in *both* schemes, so this bar was
      // black even in light mode and its contents had to be light --
      // which then went unreadable once dark mode made them flip.
      decoration: BoxDecoration(
        color: context.theme.colorScheme.surfaceContainerLowest,
        border: Border(
          top: BorderSide(color: AppNeutralColors.of(context).neutral300),
        ),
      ),
      height: 90,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Only the mic/camera cluster watches the room. The chat TextField
          // must not rebuild on join/leave/mute — Flutter web's selection
          // overlay null-checks if its EditableText is disposed mid-selection.
          AnimatedBuilder(
            animation: _liveMeetingProvider.conferenceRoomNotifier,
            builder: (context, __) {
              if (_liveMeetingProvider.conferenceRoom?.room == null) {
                return const SizedBox.shrink();
              }
              return _buildControlWidgets();
            },
          ),
          if (!responsiveLayoutService.isMobile(context) && isChatBarVisible)
            _buildChatSectionWidgets(),
          _buildLeaveButton(),
        ],
      ),
    );
  }
}

class ChatAndEmojisInput extends StatefulWidget {
  @override
  State<ChatAndEmojisInput> createState() => _ChatAndEmojisInputState();
}

class _ChatAndEmojisInputState extends State<ChatAndEmojisInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = responsiveLayoutService.isMobile(context);
    final spacer = SizedBox(width: isMobile ? 4 : 10);
    final isInLiveStreamLobby = EventProvider.watch(context).isLiveStream &&
        !LiveMeetingProvider.watch(context).isInBreakout;

    // Check if chat should be disabled for this user in hostless waiting room
    final eventPermissions = EventPermissionsProvider.watch(context);
    final shouldDisableChat =
        eventPermissions?.shouldDisableChatInHostlessWaitingRoom(context) ??
            false;

    // Hide entire chat input for restricted users in waiting room
    if (shouldDisableChat) {
      return SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          spacer,
          if (!isInLiveStreamLobby) ...[
            RaiseHandButton(),
            spacer,
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 500),
              child: CustomPointerInterceptor(
                child: ChatInput(
                  controller: _controller,
                  messageInputHint: 'Say something',
                  shouldGuardCommunityMember: false,
                ),
              ),
            ),
          ),
          spacer,
          if (!isInLiveStreamLobby &&
              (!isMobile || _controller.text.isEmpty)) ...[
            EmojiButton(emoji: EmotionType.laughWithTears),
            spacer,
            EmojiButton(emoji: EmotionType.thumbsUp),
            spacer,
            EmojiButton(emoji: EmotionType.heart),
            spacer,
          ],
        ],
      ),
    );
  }
}

/// Raise or lower your hand.
///
/// Sits with chat and the reactions rather than with the mic and camera: it's
/// a signal to the room, the same kind of thing as a reaction, not one of the
/// call's primary controls. Built to match [EmojiButton] for that reason.
///
/// The glyph is the same artwork the mobile bar uses. A Material icon would
/// render differently either side of the app for no reason.
class RaiseHandButton extends StatelessWidget {
  const RaiseHandButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final store = MeetingGuideCardStore.watch(context);
    // Nothing to read the raised state from or write it to.
    if (store == null) return const SizedBox.shrink();

    final isRaised = store.isMyHandRaised;
    final isMobile = responsiveLayoutService.isMobile(context);
    final borderRadius = BorderRadius.circular(isMobile ? 25 : 50);

    return Semantics(
      button: true,
      // The state is in the name, not only in the fill behind the glyph.
      label: isRaised ? 'Lower your hand' : 'Raise your hand',
      child: Tooltip(
        message: isRaised ? 'Lower hand' : 'Raise hand',
        child: CustomInkWell(
          onTap: () => store.toggleHandRaise(),
          borderRadius: borderRadius,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 20,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: isRaised
                  ? context.theme.colorScheme.primaryContainer
                  : context.theme.colorScheme.surfaceContainerHigh,
              borderRadius: borderRadius,
              // A shape change as well as a fill change, so the raised state
              // doesn't rest on colour alone.
              border: isRaised
                  ? Border.all(
                      color: context.theme.colorScheme.primary,
                      width: 2,
                    )
                  : null,
            ),
            child: ProxiedImage(
              null,
              asset: AppAsset.raisedHand(),
              loadingColor: Colors.transparent,
              height: isMobile ? 24 : 20,
              width: isMobile ? 24 : 20,
            ),
          ),
        ),
      ),
    );
  }
}

class EmojiButton extends StatefulWidget {
  final EmotionType emoji;

  const EmojiButton({required this.emoji});

  @override
  _EmojiButtonState createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<EmojiButton> {
  Future<void>? _currentNetworkCall;

  @override
  Widget build(BuildContext context) {
    final isMobile = responsiveLayoutService.isMobile(context);
    final borderRadius = BorderRadius.circular(isMobile ? 25 : 50);
    // Named here rather than at each call site: this button is an image with
    // no text wherever it is used, and the desktop chat row was unnamed too.
    return Semantics(
      button: true,
      label: widget.emoji.accessibilityLabel,
      child: CustomInkWell(
        onTap: () async {
          if (_currentNetworkCall != null) return;

          setState(() {
            _currentNetworkCall = alertOnError(
              context,
              () => context.read<ChatModel>().createChatMessage(
                    emotionType: widget.emoji,
                  ),
            );
          });

          await _currentNetworkCall;
          setState(() {
            _currentNetworkCall = null;
          });
        },
        borderRadius: borderRadius,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 20,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: context.theme.colorScheme.surfaceContainerHigh,
            borderRadius: borderRadius,
          ),
          child: ProxiedImage(
            null,
            asset: widget.emoji.imageAssetPath,
            loadingColor: Colors.transparent,
            // Bigger on mobile, where these sit alone in the reaction sheet
            // and are the whole content of the button. On desktop they sit in
            // a row of controls and the larger size crowded it.
            width: isMobile ? 32 : 24,
            height: isMobile ? 32 : 24,
          ),
        ),
      ),
    );
  }
}

class ChatInput extends StatefulWidget {
  final String messageInputHint;
  final bool shouldGuardCommunityMember;
  final TextEditingController controller;

  const ChatInput({
    required this.messageInputHint,
    required this.shouldGuardCommunityMember,
    required this.controller,
  });

  @override
  ChatInputState createState() => ChatInputState();
}

class ChatInputState extends State<ChatInput> {
  final _sendController = SubmitNotifier();

  bool get canSubmit => !isNullOrEmpty(widget.controller.text.trim());

  Future<void> _sendMessageWithAlert() => alertOnError(context, () async {
        final text = widget.controller.text;
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.controller.clear());
        await context.read<ChatModel>().createChatMessage(text: text);
      });

  Future<void> _sendMessage() => widget.shouldGuardCommunityMember
      ? guardCommunityMember(
          context,
          Provider.of<CommunityProvider>(context, listen: false).community,
          _sendMessageWithAlert,
        )
      : _sendMessageWithAlert();

  @override
  Widget build(BuildContext context) {
    final isMobile = responsiveLayoutService.isMobile(context);

    return Container(
      padding: isMobile
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: CustomTextField(
              borderType: BorderType.none,
              showFocusedBorder: false,
              backgroundColor:
                  context.theme.colorScheme.surfaceContainerHighest,
              padding: isMobile ? EdgeInsets.only(bottom: 6) : EdgeInsets.zero,
              contentPadding: EdgeInsets.symmetric(horizontal: 10),
              onEditingComplete:
                  canSubmit ? _sendController.submit : widget.controller.clear,
              controller: widget.controller,
              maxLines: 2,
              minLines: 1,
              hintText: widget.messageInputHint,
              unfocusOnSubmit: false,
              maxLength: 2000,
              hideCounter: true,
            ),
          ),
          if (!isMobile || widget.controller.text.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(
                left: 10,
                bottom: isMobile ? 4 : 0,
              ),
              child: Semantics(
                label: context.l10n.submitChatButton,
                button: true,
                child: ActionButton(
                  minWidth: 20,
                  color: context.theme.colorScheme.surfaceContainerHigh,
                  // No disabledColor override: primaryFixedDim is light under
                  // a dark theme, which left the light icon invisible while
                  // the field was empty. Flutter's own disabled treatment
                  // dims the surface pair correctly in both modes.
                  textColor: context.theme.colorScheme.onSurface,
                  controller: _sendController,
                  onPressed: canSubmit ? _sendMessage : null,
                  height: isMobile ? 50 : 55,
                  // Inherits the button's foreground, so it dims with the
                  // button instead of staying at full strength when disabled.
                  child: Icon(Icons.send),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.onTap,
    required this.text,
    required this.icon,
    this.iconColor,
  });

  final Future<void> Function() onTap;
  final String text;
  final IconData icon;
  final Color? iconColor;

  @override
  _IconButtonState createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    return CustomInkWell(
      hoverColor: context.theme.colorScheme.surface.withScrimOpacity,
      onTap: () async {
        if (_isSending) return;
        setState(() => _isSending = true);
        try {
          await widget.onTap();
          // Prevent someone from tapping it twice in quick succession
          await Future.delayed(Duration(milliseconds: 200), () {});
        } catch (e, stacktrace) {
          loggingService.log(
            'Error in icon button',
            logType: LogType.error,
            error: e,
            stackTrace: stacktrace,
          );
        }

        if (mounted) setState(() => _isSending = false);
      },
      child: Container(
        padding: const EdgeInsets.all(2),
        constraints: BoxConstraints(
          minWidth: 80,
          maxWidth:
              responsiveLayoutService.isMobile(context) ? 86 : double.infinity,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 40,
              child: Icon(
                widget.icon,
                size: 34,
                color: _isSending
                    ? context.theme.colorScheme.onSurfaceVariant
                    : widget.iconColor ?? context.theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 2),
            HeightConstrainedText(
              widget.text,
              textAlign: TextAlign.center,
              style: context.theme.textTheme.bodyMedium!.copyWith(
                color: _isSending
                    ? context.theme.colorScheme.onSurfaceVariant
                    : context.theme.colorScheme.onSurface,
                fontWeight: FontWeight.w400,
                height: 1.05,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
