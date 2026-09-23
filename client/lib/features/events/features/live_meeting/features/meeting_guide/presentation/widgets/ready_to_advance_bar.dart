import 'package:client/core/widgets/buttons/action_button.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/features/events/features/live_meeting/features/meeting_guide/presentation/widgets/participant_avatar_stack.dart';
import 'package:client/features/events/features/live_meeting/presentation/views/live_meeting_mobile_page.dart'
    show kMeetingPanelInset;
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';

/// The single advance control for an agenda item.
///
/// Replaces three separate affordances that testers read as duplicates: the
/// count-plus-arrow in the mobile bottom bar, the "Ready to move on?" pill at
/// the foot of the agenda panel, and the host's bare Next button. One
/// component now, laid out as a right-hand rail on desktop and a full-width
/// strip at the foot of the panel on mobile.
///
/// Two modes, because the underlying action differs:
///
/// * A participant is **voting**. Everyone's vote is shown, and once cast it
///   can't be taken back, so the button becomes a static "Ready".
/// * A host **advances the room** unilaterally, and keeps Back alongside Next.
///   The tally is information rather than a threshold.
class ReadyToAdvanceBar extends StatelessWidget {
  /// Everyone present, and whether they have voted. Empty for a host, who has
  /// no tally to show.
  final List<ParticipantReadiness> participants;

  /// Whether the viewer has already voted. Never true for a host.
  final bool hasVoted;

  /// Hosts advance unilaterally and get Back as well as Next.
  final bool isHost;
  final bool showBackButton;

  final VoidCallback onNext;
  final VoidCallback? onBack;

  final bool isMobile;

  const ReadyToAdvanceBar({
    required this.participants,
    required this.hasVoted,
    required this.isHost,
    required this.showBackButton,
    required this.onNext,
    required this.onBack,
    required this.isMobile,
    Key? key,
  }) : super(key: key);

  /// Matches the "Ready" text and the ring on a voted avatar.
  static const Color _readyGreen = Color(0xFF258156);

  /// Taller than the app's usual control. This is the primary action of the
  /// whole panel, and a good share of the audience is older -- the extra
  /// height is worth more here than the tidiness of matching everything else.
  static const double _buttonHeight = 52;

  /// Width of each button once they stack on the desktop rail.
  ///
  /// Given to both so they match: left to size themselves they came out at
  /// different widths, which reads as a mistake when they're one above the
  /// other. Comfortably inside the rail's 168 of usable width.
  static const double _stackedButtonWidth = 140;

  /// The guide card's own corner radius. The rail sits flush against the
  /// card's right edge, so it has to round with it or it squares off a
  /// corner the card rounded.
  static const double cardRadius = 20;

  /// The rail/strip chrome on its own.
  ///
  /// Exposed because states with nothing to advance -- a card still counting
  /// down to its start -- belong in the same frame. Returning a bare widget
  /// there collapsed the rail to nothing and took the advance control off
  /// screen with it.
  static Widget shell({required bool isMobile, required Widget child}) {
    return Builder(
      builder: (context) => isMobile
          ? Container(
              padding: const EdgeInsets.symmetric(
                horizontal: kMeetingPanelInset,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                // Sits between the panel above and the bottom bar below, so
                // it needs to be neither. Under a dark theme this lands on
                // the same neutral900 as the bar and the top border is what
                // separates them; in light it reads as its own tone.
                color: AppNeutralColors.of(context).neutral100,
                border: Border(
                  top: BorderSide(
                    color: context.theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: child,
            )
          : Container(
              width: 200,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                // Same tone as the mobile strip, so the control reads as one
                // surface across both layouts.
                color: AppNeutralColors.of(context).neutral100,
                border: Border(
                  left: BorderSide(
                    color: context.theme.colorScheme.outlineVariant,
                  ),
                ),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(cardRadius),
                  bottomRight: Radius.circular(cardRadius),
                ),
              ),
              child: Center(child: child),
            ),
    );
  }

  int get _readyCount => participants.where((p) => p.isReady).length;

  @override
  Widget build(BuildContext context) {
    return isMobile ? _buildMobile(context) : _buildDesktop(context);
  }

  /// A strip across the foot of the agenda panel: label and tally on the left,
  /// faces in the middle, the action on the right.
  Widget _buildMobile(BuildContext context) {
    return shell(
      isMobile: true,
      child: Row(
        children: [
          Expanded(child: _buildLabel(context)),
          if (participants.isNotEmpty) ...[
            const SizedBox(width: 12),
            ParticipantAvatarStack(participants: participants, avatarSize: 26),
          ],
          const SizedBox(width: 12),
          _buildActions(context),
        ],
      ),
    );
  }

  /// A rail down the right-hand side of the agenda panel: faces and tally at
  /// the top, the action pinned to the bottom.
  Widget _buildDesktop(BuildContext context) {
    // Vertically centred rather than pinned top-and-bottom: the rail is as
    // tall as the whole card, and a tall agenda item left the controls
    // stranded at opposite ends of it.
    return shell(
      isMobile: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (participants.isNotEmpty) ...[
            ParticipantAvatarStack(participants: participants),
            const SizedBox(height: 12),
          ],
          _buildLabel(context, centred: true),
          const SizedBox(height: 16),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildLabel(BuildContext context, {bool centred = false}) {
    final tally = participants.isEmpty
        ? null
        : '$_readyCount of ${participants.length} are ready';
    final align = centred ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment:
          centred ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        HeightConstrainedText(
          'Ready to move on?',
          textAlign: align,
          style: context.theme.textTheme.bodyMedium?.copyWith(
            color: context.theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (tally != null) ...[
          const SizedBox(height: 2),
          HeightConstrainedText(
            tally,
            textAlign: align,
            style: context.theme.textTheme.bodySmall?.copyWith(
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    // A cast vote is final, so the control stops being a control.
    if (hasVoted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 16, color: _readyGreen),
          const SizedBox(width: 4),
          HeightConstrainedText(
            'Ready',
            style: context.theme.textTheme.bodyMedium?.copyWith(
              color: _readyGreen,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final next = ActionButton(
      type: ActionButtonType.filled,
      color: context.theme.colorScheme.primary,
      textColor: context.theme.colorScheme.onPrimary,
      tooltipText: isHost
          ? 'Move the room on to the next agenda item.'
          : 'Click when you’re ready to move on.',
      minWidth: isMobile ? 96 : _stackedButtonWidth,
      height: _buttonHeight,
      // Desktop rail inner width is 168. ActionButton padding stacks on M3's
      // 24px button padding; 24+24 overflows Next by ~18px on web.
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 0,
        vertical: 8,
      ),
      borderRadius: BorderRadius.circular(10),
      onPressed: onNext,
      text: 'Next',
    );

    if (!isHost || !showBackButton) {
      if (isMobile) return next;
      // scaleDown so a longer label can't overrun the rail.
      return FittedBox(fit: BoxFit.scaleDown, child: next);
    }

    final back = ActionButton(
      type: ActionButtonType.outline,
      color: context.theme.colorScheme.primary,
      minWidth: isMobile ? 0 : _stackedButtonWidth,
      height: _buttonHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      borderRadius: BorderRadius.circular(10),
      onPressed: onBack,
      text: 'Back',
    );

    // The rail is 200 wide, 168 inside its padding, and the two buttons need
    // about 190 side by side -- so Next was clipped at the rail's edge.
    //
    // Centred rather than stretched: ActionButton wraps its content in a
    // Row(mainAxisSize: min), so a stretched slot widens around the button and
    // leaves it at the left edge instead of filling. Matching minWidths size
    // them, and FittedBox keeps a longer label inside the rail.
    if (!isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: next),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: back),
        ],
      );
    }

    // The mobile strip is full-width, so they fit in a row.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        back,
        const SizedBox(width: 8),
        next,
      ],
    );
  }
}
