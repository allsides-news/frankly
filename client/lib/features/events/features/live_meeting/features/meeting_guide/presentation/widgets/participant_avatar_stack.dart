import 'package:client/features/user/data/providers/user_info_builder.dart';
import 'package:client/features/user/presentation/widgets/user_profile_chip.dart';
import 'package:client/styles/styles.dart';
import 'package:flutter/material.dart';

/// One participant's readiness, in the order they should be drawn.
class ParticipantReadiness {
  final String userId;
  final bool isReady;

  const ParticipantReadiness({required this.userId, required this.isReady});
}

/// The people in the room, as overlapping avatars, ringed when they have voted
/// to move on.
///
/// Overlapping rather than spaced so a full room stays the width of roughly
/// three avatars. Past [_maxPerRow] it wraps to a second staggered row, and
/// past [_maxAvatars] the last slot becomes a "+N" count -- a room of thirty
/// is a number, not thirty faces.
class ParticipantAvatarStack extends StatelessWidget {
  final List<ParticipantReadiness> participants;
  final double avatarSize;

  const ParticipantAvatarStack({
    required this.participants,
    this.avatarSize = 28,
    Key? key,
  }) : super(key: key);

  static const int _maxPerRow = 4;
  static const int _maxRows = 2;
  static const int _maxAvatars = _maxPerRow * _maxRows;

  /// How much of each avatar the next one covers.
  static const double _overlapFraction = 0.32;

  /// Ring drawn around every avatar, so the ready ones read as a state change
  /// rather than as a different kind of thing.
  static const double _ringWidth = 2;

  /// Size of the tick badged onto a ready avatar.
  ///
  /// The ring alone carried the state in colour only, which leaves out anyone
  /// who can't distinguish the two ring colours. The tick is the same
  /// information in a second channel.
  static const double _badgeFraction = 0.44;

  /// The same purple the speaking indicator rings a video tile with, so
  /// "this person is signalling something" looks like one idea in the call.
  static const Color _readyRing = AppAccentColors.violet;

  double get _step => avatarSize * (1 - _overlapFraction);

  @override
  Widget build(BuildContext context) {
    if (participants.isEmpty) return const SizedBox.shrink();

    final overflow = participants.length > _maxAvatars
        ? participants.length - (_maxAvatars - 1)
        : 0;
    final shown = overflow > 0
        ? participants.take(_maxAvatars - 1).toList()
        : participants;

    // Fill the first row before starting the second, so three people read as
    // one row rather than two ragged ones.
    final rowCount = ((shown.length + (overflow > 0 ? 1 : 0)) / _maxPerRow)
        .ceil()
        .clamp(1, _maxRows);

    final rows = <List<Widget>>[];
    for (var r = 0; r < rowCount; r++) {
      final start = r * _maxPerRow;
      final end = (start + _maxPerRow).clamp(0, shown.length);
      final row = <Widget>[
        for (var i = start; i < end; i++) _buildAvatar(shown[i]),
      ];
      if (overflow > 0 && r == rowCount - 1) row.add(_buildOverflow(context, overflow));
      rows.add(row);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: avatarSize * 0.18),
          Padding(
            // Second row sits half a step in, so the columns interlock rather
            // than stacking into a grid.
            padding: EdgeInsets.only(left: r.isOdd ? _step / 2 : 0),
            child: _buildRow(rows[r]),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(List<Widget> children) {
    return SizedBox(
      height: avatarSize,
      width: _step * (children.length - 1) + avatarSize,
      child: Stack(
        children: [
          // Painted right-to-left so the leftmost face is frontmost. With the
          // natural order each avatar covered its neighbour's bottom-right
          // corner, which is exactly where the ready tick sits -- every badge
          // but the last one would have been hidden.
          for (var i = children.length - 1; i >= 0; i--)
            Positioned(left: _step * i, child: children[i]),
        ],
      ),
    );
  }

  Widget _buildAvatar(ParticipantReadiness p) {
    // The avatar hides the name and the tally beside it is only an aggregate,
    // so each face carries its own name and state for assistive technology --
    // otherwise "who is ready" is unavailable without seeing the ring.
    return UserInfoBuilder(
      userId: p.userId,
      builder: (context, isLoading, snapshot) {
        final name = isLoading
            ? 'Participant'
            : (snapshot.data?.displayName ?? 'Participant');

        return Semantics(
          label: p.isReady
              ? '$name is ready to move on'
              : '$name has not voted yet',
          excludeSemantics: true,
          child: _buildAvatarVisual(context, p),
        );
      },
    );
  }

  Widget _buildAvatarVisual(BuildContext context, ParticipantReadiness p) {
    final badgeSize = avatarSize * _badgeFraction;

    return SizedBox(
      width: avatarSize,
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: p.isReady
                    ? _readyRing
                    : context.theme.colorScheme.outlineVariant,
                width: _ringWidth,
              ),
              // Behind the avatar, so an overlapped neighbour is separated
              // from it by the card's own colour rather than bleeding
              // together.
              color: context.theme.colorScheme.surfaceContainerLowest,
            ),
            child: ClipOval(
              child: UserProfileChip(
                userId: p.userId,
                showName: false,
                enableOnTap: false,
                imageHeight: avatarSize - _ringWidth * 2,
                alignment: Alignment.center,
              ),
            ),
          ),
          if (p.isReady)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _readyRing,
                  border: Border.all(
                    color: context.theme.colorScheme.surfaceContainerLowest,
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.check,
                  size: badgeSize * 0.7,
                  color: context.theme.colorScheme.surfaceContainerLowest,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverflow(BuildContext context, int count) {
    return Semantics(
      label: '$count more participants',
      excludeSemantics: true,
      child: _buildOverflowVisual(context, count),
    );
  }

  Widget _buildOverflowVisual(BuildContext context, int count) {
    return Container(
      width: avatarSize,
      height: avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.theme.colorScheme.surfaceContainerHighest,
        border: Border.all(
          color: context.theme.colorScheme.outlineVariant,
          width: _ringWidth,
        ),
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Text(
            '+$count',
            style: context.theme.textTheme.labelSmall?.copyWith(
              color: context.theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
