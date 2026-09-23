import 'dart:math' as math;

import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/proxied_image.dart';
import 'package:client/services.dart';
import 'package:client/styles/app_asset.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';

class MeetingGuideTutorial extends StatefulWidget {
  @override
  State<MeetingGuideTutorial> createState() => _MeetingGuideTutorialState();
}

class _MeetingGuideTutorialState extends State<MeetingGuideTutorial> {
  @override
  Widget build(BuildContext context) {
    final isMobile = responsiveLayoutService.isMobile(context);
    final kDialogWidth = isMobile ? 300.0 : 950.0;
    final kDialogHeight = isMobile ? 540.0 : 540.0;
    // Arrow and text takes extra additional space in the page. These measurements are the threshold
    // where text and arrow doesn't overflow/clip. After threshold is reached - this section is hidden.
    final bool canShowTutorialTextArrowSectionOutside =
        !isMobile && MediaQuery.of(context).size.height >= 560;

    // Clamped to what the screen can actually give it, so a short phone gets
    // a dialog that fits rather than one running off both ends.
    final available = MediaQuery.of(context).size;
    const inset = AppSize.kDialogEdgeInset;

    return Padding(
      padding: const EdgeInsets.all(inset),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(kDialogWidth, available.width - inset * 2),
          maxHeight: math.min(kDialogHeight, available.height - inset * 2),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Padding(
              padding: isMobile
                  ? EdgeInsets.zero
                  : EdgeInsets.symmetric(vertical: 100, horizontal: 125),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: isMobile
                    ? Column(
                        children: [
                          Expanded(flex: 5, child: _buildMainCard()),
                          Expanded(flex: 3, child: _buildSupportCard()),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(flex: 5, child: _buildMainCard()),
                          Expanded(flex: 2, child: _buildSupportCard()),
                        ],
                      ),
              ),
            ),
            if (canShowTutorialTextArrowSectionOutside)
              _buildTutorialHelperOutside(),
          ],
        ),
      ),
    );
  }

  Widget _buildTutorialHelperOutside() {
    return Positioned(
      bottom: 6,
      right: 6,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The artwork's mint is baked in; tinted to the same violet that
          // rings a speaking tile, so the call's one "look here" colour is
          // the same everywhere.
          ColorFiltered(
            colorFilter: const ColorFilter.mode(
              AppAccentColors.violet,
              BlendMode.srcIn,
            ),
            child: ProxiedImage(
              null,
              asset: AppAsset('media/tutorial-arrow-bottom-up-left.png'),
              height: 70,
            ),
          ),
          Text(
            'Click here when\nyou’re ready to\nget started',
            style: GoogleFonts.fingerPaint(
              fontSize: _getDynamicSize(18),
              fontWeight: FontWeight.normal,
              // This sits outside the cards, on the dialog's black54 barrier
              // -- dark whatever the theme. onPrimary is white in light but
              // neutral800 in dark, which is why it disappeared there.
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  double _getDynamicSize(double originalValue, {double scale = 2 / 3}) {
    final value = responsiveLayoutService.isMobile(context)
        ? originalValue * scale
        : originalValue;

    return value.roundToDouble();
  }

  Widget _buildMainCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      color: context.theme.colorScheme.surfaceContainerLowest,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HeightConstrainedText(
                'Agenda Item 1 of 10',
                style: TextStyle(
                  fontSize: _getDynamicSize(24),
                  fontWeight: FontWeight.w700,
                  color: context.theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          DottedBorder(
            padding: EdgeInsets.symmetric(
              vertical: _getDynamicSize(40),
              horizontal: _getDynamicSize(32),
            ),
            color: context.theme.colorScheme.primary,
            strokeWidth: 1,
            dashPattern: const [8, 4],
            child: Column(
              children: [
                HeightConstrainedText(
                  'This is your agenda.',
                  style: TextStyle(
                    fontSize: _getDynamicSize(24),
                    fontWeight: FontWeight.w700,
                    color: context.theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                HeightConstrainedText(
                  '''Prompts will appear here. Once most people have clicked “Next”, we’ll move on to the next agenda item.''',
                  style: TextStyle(
                    fontSize: _getDynamicSize(16),
                    fontWeight: FontWeight.normal,
                    color: context.theme.colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A stand-in for one of the faces in [ParticipantAvatarStack].
  ///
  /// Drawn rather than drawn from media/profile-empty.png, which has a mint
  /// ring baked into it -- the real stack rings ready participants in violet
  /// and had already moved on without this preview following.
  Widget _buildProfileImage(double emptyProfileSize, {required bool isReady}) {
    return Container(
      width: emptyProfileSize,
      height: emptyProfileSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: isReady
              ? AppAccentColors.violet
              : context.theme.colorScheme.outlineVariant,
          width: 2,
        ),
      ),
      child: Icon(
        Icons.person,
        size: emptyProfileSize * 0.6,
        color: context.theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildSupportCard() {
    const kEmptyProfileSize = 32.0;

    return Container(
      color: context.theme.colorScheme.surface,
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Spacer(),
          Stack(
            alignment: Alignment.center,
            children: [
              // Two ringed and one not, matching the "2 of 3" below it and
              // the real stack's ready-first order.
              Align(
                child: Padding(
                  padding:
                      const EdgeInsets.only(right: kEmptyProfileSize * 1.25),
                  child:
                      _buildProfileImage(kEmptyProfileSize, isReady: true),
                ),
              ),
              Align(
                child: _buildProfileImage(kEmptyProfileSize, isReady: true),
              ),
              Align(
                child: Padding(
                  padding:
                      const EdgeInsets.only(left: kEmptyProfileSize * 1.25),
                  child:
                      _buildProfileImage(kEmptyProfileSize, isReady: false),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          HeightConstrainedText(
            'Ready to move on?',
            style: TextStyle(
              fontSize: _getDynamicSize(18),
              fontWeight: FontWeight.w700,
              color: context.theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 10),
          HeightConstrainedText(
            '2 of 3 are ready',
            style: TextStyle(
              fontSize: _getDynamicSize(16),
              fontWeight: FontWeight.w400,
              color: context.theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          Spacer(),
          Row(
            mainAxisAlignment: responsiveLayoutService.isMobile(context)
                ? MainAxisAlignment.center
                : MainAxisAlignment.end,
            children: [
              ActionButton(
                color: context.theme.colorScheme.primary,
                textColor: context.theme.colorScheme.onPrimary,
                text: 'Next',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
