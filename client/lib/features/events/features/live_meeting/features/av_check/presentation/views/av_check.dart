import 'dart:math';

import 'package:beamer/beamer.dart';
import 'package:client/core/utils/extensions.dart';
import 'package:client/core/utils/image_utils.dart';
import 'package:collection/src/iterable_extensions.dart';
import 'package:flutter/material.dart';
import 'package:client/features/events/features/live_meeting/features/av_check/data/providers/av_check_provider.dart';
import 'package:client/features/events/features/live_meeting/features/av_check/presentation/widgets/data_privacy_notice.dart';
import 'package:client/features/events/features/live_meeting/features/video/presentation/views/audio_video_error.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/features/events/features/live_meeting/presentation/widgets/troubleshoot_av.dart';
import 'package:client/features/user/data/providers/user_info_builder.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:provider/provider.dart';

class AvCheckPage extends StatelessWidget {
  final Function()? onLeave;
  final BeamLocation? leaveLocation;

  /// Called after Join persists the AV choices. The parent swaps this page
  /// for the meeting; the router-param update alone is a no-op when
  /// status=joined is already in the URL.
  final void Function()? onComplete;

  const AvCheckPage({
    Key? key,
    this.onLeave,
    this.leaveLocation,
    this.onComplete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AvCheckProvider>(
      create: (_) => AvCheckProvider(context: context)..initialize(),
      child: _AvCheckPage(
        onLeave: onLeave,
        leaveLocation: leaveLocation,
        onComplete: onComplete,
      ),
    );
  }
}

class _PleaseAcceptPermissionsPage extends StatelessWidget {
  const _PleaseAcceptPermissionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 30),
          TroubleshootIssuesButton(),
        ],
      ),
    );
  }
}

class _AvCheckPage extends StatefulWidget {
  final Function()? onLeave;
  final BeamLocation? leaveLocation;
  final void Function()? onComplete;

  const _AvCheckPage({
    Key? key,
    this.onLeave,
    this.leaveLocation,
    this.onComplete,
  }) : super(key: key);

  @override
  State<_AvCheckPage> createState() => _AvCheckPageState();
}

class _AvCheckPageState extends State<_AvCheckPage> {
  /// Shared by Join Now and Leave so the two always match.
  static const double _actionButtonHeight = 56;

  bool _showMobilePrivacyNotice = true;

  AvCheckProvider get provider => context.watch<AvCheckProvider>();

  static const _roundtablesLogoUrl =
      'https://res.cloudinary.com/dhqdlbq26/image/upload/v1785254899/rt-logotype_iimiyr.png';

  void _handleJoin() {
    context.read<AvCheckProvider>().joinNowPressed();
    widget.onComplete?.call();
  }

  void _handleLeave() {
    final leaveLocation = widget.leaveLocation;
    if (leaveLocation != null) {
      Beamer.of(context).beamToReplacement(leaveLocation);
      return;
    }

    final onLeave = widget.onLeave;
    if (onLeave != null) {
      onLeave();
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop();
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = context.watch<AvCheckProvider>().errorText;
    if (error != null) {
      return Center(
        child: AudioVideoErrorDisplay(
          error: error,
          textColor: context.theme.colorScheme.secondary,
          onJoinWithoutDevices: provider.continueWithoutDevices,
        ),
      );
    }

    final devicesList = provider.devicesList;
    if (devicesList == null) {
      return _PleaseAcceptPermissionsPage();
    }

    final isMobile = responsiveLayoutService.isMobile(context);

    return Container(
      alignment: Alignment.center,
      // surface/onSurface, not primary/onPrimary: this is a page, and the
      // primary pair inverts with the theme -- which rendered a light panel
      // under a dark theme.
      color: context.theme.colorScheme.surface,
      child: SafeArea(
        child: isMobile && _showMobilePrivacyNotice
            ? _buildMobilePrivacyNotice(context)
            : UserInfoBuilder(
                userId: userService.currentUserId,
                builder: (context, loading, user) {
                  final data = user.data;
                  if (loading || data == null) {
                    return CircularProgressIndicator();
                  }

                  final name = data.displayName;
                  final userImage = data.imageUrl ??
                      generateRandomImageUrl(seed: data.hashCode);

                  if (isMobile) {
                    return _buildMobileAvCheck(
                      context: context,
                      name: name,
                      userImage: userImage,
                    );
                  }

                  return _buildDesktopAvCheck(
                    context: context,
                    name: name,
                    userImage: userImage,
                  );
                },
              ),
      ),
    );
  }

  Widget _buildDesktopAvCheck({
    required BuildContext context,
    required String? name,
    required String userImage,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxNoticeHeight = constraints.maxHeight.isFinite
            ? max(420.0, constraints.maxHeight - 64)
            : 720.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 380,
                    child: _buildAvCheckControls(
                      context: context,
                      name: name,
                      userImage: userImage,
                    ),
                  ),
                  SizedBox(width: 72),
                  Flexible(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 420,
                        maxHeight: maxNoticeHeight,
                      ),
                      child: SingleChildScrollView(
                        child: DataPrivacyNotice(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileStepIndicator(
    BuildContext context, {
    required int currentStep,
  }) {
    return Row(
      children: [
        for (var index = 0; index < 2; index++) ...[
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: index <= currentStep
                    ? context.theme.colorScheme.onSurface
                    : context.theme.colorScheme.onSurface
                        .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (index == 0) SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildRoundtablesLogo(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Image.network(
        _roundtablesLogoUrl,
        height: 24,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => HeightConstrainedText(
          'AllSides Roundtables',
          style: AppTextStyle.body.copyWith(
            color: context.theme.colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBottomOverlay(
    BuildContext context, {
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            context.theme.colorScheme.primary.withValues(alpha: 0),
            context.theme.colorScheme.primary.withValues(alpha: 0.92),
            context.theme.colorScheme.primary,
          ],
        ),
      ),
      child: Row(children: children),
    );
  }

  Widget _buildMobilePrivacyNotice(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(constraints.maxWidth, 390.0);
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height;

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 132),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMobileStepIndicator(context, currentStep: 0),
                        SizedBox(height: 24),
                        _buildRoundtablesLogo(context),
                        SizedBox(height: 24),
                        DataPrivacyNotice(compact: true),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildMobileBottomOverlay(
                    context,
                    children: [
                      Expanded(child: _buildLeaveButton(context)),
                      SizedBox(width: 12),
                      Expanded(
                        child: ActionButton(
                          text: 'Next',
                          height: 56,
                          expand: true,
                          color:
                              context.theme.colorScheme.surfaceContainerLowest,
                          textColor: context.theme.colorScheme.primary,
                          onPressed: () {
                            setState(() {
                              _showMobilePrivacyNotice = false;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileAvCheck({
    required BuildContext context,
    required String? name,
    required String userImage,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = min(constraints.maxWidth, 390.0);

        return Center(
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMobileStepIndicator(context, currentStep: 1),
                  SizedBox(height: 32),
                  _buildAvCheckControls(
                    context: context,
                    name: name,
                    userImage: userImage,
                    useMobileActions: true,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvCheckControls({
    required BuildContext context,
    required String? name,
    required String userImage,
    bool useMobileActions = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: useMobileActions
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        HeightConstrainedText(
          'Hi${name != null ? ' $name' : ''}, ready to join?',
          style: AppTextStyle.headline3.copyWith(
            color: context.theme.colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
        ),
        if (provider.deviceNotice != null) ...[
          SizedBox(height: 12),
          HeightConstrainedText(
            provider.deviceNotice!,
            style: AppTextStyle.body.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        SizedBox(height: 20),
        _buildVideoContainer(userImage),
        SizedBox(height: 16),
        _buildSelectMic(),
        SizedBox(height: 16),
        _buildSelectVideo(),
        SizedBox(height: 36),
        if (useMobileActions)
          _buildMobileActionButtons(context)
        else
          SizedBox(
            width: 335,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildJoinNowButton(context),
                SizedBox(height: 12),
                _buildLeaveButton(context),
              ],
            ),
          ),
        SizedBox(height: 20),
        if (!useMobileActions) ...[
          _buildDiagnoseIssuesButton(),
          SizedBox(height: 20),
        ],
      ],
    );
  }

  Widget _buildMobileActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ActionButton(
            text: 'Back',
            type: ActionButtonType.outline,
            height: 56,
            expand: true,
            color: context.theme.colorScheme.primary,
            textColor: context.theme.colorScheme.onSurface,
            borderSide: BorderSide(color: context.theme.colorScheme.onSurface),
            onPressed: () {
              setState(() {
                _showMobilePrivacyNotice = true;
              });
            },
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: ActionButton(
            text: 'Join',
            height: 56,
            expand: true,
            color: context.theme.colorScheme.primary,
            textColor: context.theme.colorScheme.onPrimary,
            onPressed: _handleJoin,
          ),
        ),
      ],
    );
  }

  Widget _buildLeaveButton(
    BuildContext context, {
    double? minWidth,
  }) {
    return ActionButton(
      text: 'Leave',
      minWidth: minWidth,
      height: _actionButtonHeight,
      expand: true,
      color: const Color(0xFFC00000),
      textColor: Colors.white,
      onPressed: _handleLeave,
    );
  }

  Widget _buildDiagnoseIssuesButton() =>
      TroubleshootIssuesButton(linkColor: context.theme.colorScheme.onSurface);

  Widget _buildVideoContainer(String image) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: context.theme.colorScheme.onSurface),
        borderRadius: BorderRadius.circular(10),
        // This had no fill at all, so with the camera off you saw the page
        // through it and the constant-white overlay controls vanished against
        // a light one. A constant midtone, matching the in-call video-off
        // tile, since those controls don't follow the theme either.
        color: AppNeutralColors.neutral500,
      ),
      width: 334,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Keep HtmlElementView mounted. Re-inserting the same viewType
              // after removal is blank on Flutter web.
              _buildVideoElement(),
              if (!provider.cameraOn)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppNeutralColors.neutral500,
                    child: Center(
                      child: ProxiedImage(
                        image,
                        height: 50,
                        width: 50,
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildAVIcons(),
                      _buildAudioLevelIndicator(),
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

  Widget _buildVideoElement() => Positioned.fill(
        child: FittedBox(
          fit: BoxFit.cover,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(pi),
            child: SizedBox(
              width: AvCheckProvider.requestedSize.width,
              height: AvCheckProvider.requestedSize.height,
              child: HtmlElementView(viewType: provider.viewKey),
            ),
          ),
        ),
      );

  Widget _buildAVIcons() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAvIcon(
            onTap: provider.toggleVideo,
            icon: provider.cameraOn
                ? Icons.videocam_outlined
                : Icons.videocam_off_outlined,
            label: provider.cameraOn ? 'Turn camera off' : 'Turn camera on',
          ),
          SizedBox(width: 10),
          _buildAvIcon(
            onTap: provider.toggleMic,
            icon: provider.micOn ? Icons.mic_none : Icons.mic_off_outlined,
            label: provider.micOn ? 'Mute microphone' : 'Unmute microphone',
          ),
        ],
      );

  Widget _buildAvIcon({
    required void Function() onTap,
    required IconData icon,
    required String label,
  }) =>
      // Icon-only control: the label is its accessible name (WCAG).
      Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Constant white: these sit on the video preview, whose
              // brightness has nothing to do with the app's theme.
              border: Border.all(color: AppNeutralColors.neutral50),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: AppNeutralColors.neutral50,
            ),
          ),
        ),
      );

  Widget _buildAudioLevelIndicator() => Row(
        mainAxisSize: MainAxisSize.min,
        children: List<Widget>.generate(
          9,
          (i) {
            return Container(
              height: 20,
              width: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                // Also over the preview, so also constant: white bars, with
                // the active ones filled dark.
                color: i < provider.currentAudioLevel && provider.micOn
                    ? AppNeutralColors.neutral600
                    : AppNeutralColors.neutral50,
              ),
            );
          },
        ).intersperse(SizedBox(width: 5)).toList(),
      );

  Widget _buildSelectMic() => _buildDevicesDropdown(
        deviceKind: 'audioinput',
        currentDeviceId: provider.defaultMic,
        onChanged: provider.selectMic,
        icon: Icons.mic_none,
      );

  Widget _buildSelectVideo() => _buildDevicesDropdown(
        deviceKind: 'videoinput',
        currentDeviceId: provider.defaultCamera,
        onChanged: provider.selectCamera,
        icon: Icons.videocam_outlined,
      );

  /// Sized identically to the Leave button below it -- both stretch to the
  /// column's width, so neither can end up wider than the other.
  Widget _buildJoinNowButton(BuildContext context) => ActionButton(
        color: context.theme.colorScheme.primary,
        textColor: context.theme.colorScheme.onPrimary,
        height: _actionButtonHeight,
        expand: true,
        text: 'Join Now',
        onPressed: _handleJoin,
      );

  Widget _buildDevicesDropdown({
    required Function(String) onChanged,
    required String? currentDeviceId,
    required String deviceKind,
    required IconData icon,
  }) {
    final devices =
        provider.devicesList?.where((d) => d.kind == deviceKind).toList() ?? [];

    final currentDeviceFound =
        devices.any((d) => d.deviceId == currentDeviceId);
    if (!currentDeviceFound) {
      // ignore: parameter_assignments
      currentDeviceId = devices.firstOrNull?.deviceId;
      if (currentDeviceId != null) {
        WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
          onChanged(currentDeviceId!);
        });
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          alignment: Alignment.center,
          width: 48,
          height: 48,
          child: Icon(
            icon,
            size: 26,
            color: context.theme.colorScheme.onSurface,
          ),
        ),
        Container(
          width: 287,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            // Fill matches the page; the outline and label carry the
            // contrast instead. It used to fill with `primary`, which inverts
            // with the theme.
            border: Border.all(color: context.theme.colorScheme.outline),
            borderRadius: BorderRadius.circular(10),
            color: context.theme.colorScheme.surface,
          ),
          child: Builder(
            builder: (context) {
              if (devices.isEmpty) {
                return HeightConstrainedText(
                  'No alternative devices detected',
                  style: AppTextStyle.body
                      .copyWith(color: context.theme.colorScheme.onSurface),
                );
              } else {
                return DropdownButton<String>(
                  underline: SizedBox(),
                  onChanged: (deviceId) {
                    final id = devices
                        .firstWhere((d) => d.deviceId == deviceId)
                        .deviceId;
                    if (id != null) {
                      onChanged(id);
                    }
                  },
                  value: currentDeviceId,
                  icon: RotatedBox(
                    quarterTurns: 1,
                    child: Icon(
                      Icons.arrow_forward_ios,
                      color: context.theme.colorScheme.onSurface,
                      size: 20,
                    ),
                  ),
                  selectedItemBuilder: (context) => devices
                      .map(
                        (d) => _buildDropdownItem(
                          d,
                          textColor: context.theme.colorScheme.onSurface,
                        ),
                      )
                      .toList(),
                  items: [
                    for (final device in devices)
                      DropdownMenuItem(
                        value: device.deviceId,
                        child: _buildDropdownItem(
                          device,
                          textColor: context.theme.colorScheme.onSurface,
                        ),
                      ),
                  ],
                );
              }
            },
          ),
        ),
      ],
    );
  }

  /// [textColor] is required rather than defaulting to white -- that default
  /// is what kept these labels white under both themes.
  Widget _buildDropdownItem(device, {required Color textColor}) => Center(
        child: SizedBox(
          width: 240,
          child: HeightConstrainedText(
            '${device.deviceId == 'default' ? '(Default) ' : ''}${device.label}',
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.body.copyWith(color: textColor),
          ),
        ),
      );
}
