import 'dart:math' show max;

import 'package:client/core/utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:client/core/widgets/profile_chip.dart';
import 'package:client/features/user/presentation/widgets/user_profile_chip.dart';
import 'package:client/features/user/data/services/user_service.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:data_models/events/event.dart';
import 'package:provider/src/provider.dart';

/// This is a list indicating the number of users registered for an event.
/// The profile icons are arranged in a stack next to text with a description
/// of the user count.
class ParticipantsList extends StatefulWidget {
  final Event event;
  final List<String> participantIds;
  final int numberOfIconsToShow;
  final double iconSize;
  final int? participantCount;
  final bool showParticipantCount;
  final bool showGoingText;
  final bool currentUserFirst;
  final bool excludeAvatarSemantics;
  final bool? isCurrentUserParticipant;

  const ParticipantsList({
    required this.event,
    required this.participantIds,
    required this.numberOfIconsToShow,
    this.iconSize = 40,
    this.participantCount,
    this.showParticipantCount = true,
    this.showGoingText = false,
    this.currentUserFirst = true,
    this.excludeAvatarSemantics = false,
    this.isCurrentUserParticipant,
    Key? key,
  }) : super(key: key);

  @override
  State<ParticipantsList> createState() => _ParticipantsListState();
}

class _ParticipantsListState extends State<ParticipantsList> {
  /// Set a seed so that the event uses the same random images all the time
  late final int randomImageSeedValue = widget.event.id.hashCode;

  String? get currentUserId => context.watch<UserService>().currentUserId;

  bool get isParticipant {
    if (widget.isCurrentUserParticipant != null) {
      return widget.isCurrentUserParticipant!;
    }
    final userId = currentUserId;
    return userId != null && widget.participantIds.contains(userId);
  }

  int get _participantCount =>
      widget.participantCount ??
      (widget.event.useParticipantCountEstimate
          ? (widget.event.participantCountEstimate ?? 1)
          : widget.participantIds.length);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.excludeAvatarSemantics)
          ExcludeSemantics(
            child: Stack(children: _buildUserIcons()),
          )
        else
          Stack(children: _buildUserIcons()),
        if (widget.showParticipantCount) ...[
          SizedBox(width: 5),
          Flexible(child: _buildParticipantCount()),
        ],
      ],
    );
  }

  List<Widget> _buildUserIcons() {
    final userId = currentUserId;
    final isCreator = userId != null && widget.event.creatorId == userId;

    // Show creator and current user first.
    final prefixParticipants = [
      if (isParticipant && !isCreator && userId != null) userId,
      widget.event.creatorId,
    ];

    final extraIconSlots =
        max(0, widget.numberOfIconsToShow - prefixParticipants.length);

    final List<Widget> chipWidgets;
    if (widget.event.useParticipantCountEstimate) {
      final numRandomParticipants = extraIconSlots;
      chipWidgets = [
        for (final participantId in prefixParticipants)
          _buildUserProfileChip(participantId),
        for (var i = 0; i < numRandomParticipants; i++) _buildProfileChip(i),
      ];
    } else {
      final participantIds = [
        ...prefixParticipants,
        ...widget.participantIds
            .where((p) => !prefixParticipants.contains(p))
            .take(extraIconSlots),
      ];
      chipWidgets = [
        for (final id in participantIds) _buildUserProfileChip(id),
      ];
    }

    if (widget.currentUserFirst) {
      return [
        for (var i = chipWidgets.length - 1; i >= 0; i--)
          Padding(
            padding: EdgeInsets.only(left: i * 19.0),
            child: chipWidgets[i],
          ),
      ];
    }

    // Put prefix widgets last since they are shown on top in the stack
    final reversedChipWidgets = chipWidgets.reversed.toList();
    return [
      for (var i = 0; i < reversedChipWidgets.length; i++)
        Padding(
          padding: EdgeInsets.only(left: i * 19.0),
          child: reversedChipWidgets[i],
        ),
    ];
  }

  Widget _buildUserProfileChip(String? id) {
    return UserProfileChip(
      userId: id,
      imageHeight: widget.iconSize,
      showName: false,
      enableOnTap: false,
    );
  }

  Widget _buildProfileChip(int i) {
    return ProfileChip(
      key: Key('profile-chip-$i'),
      imageUrl: generateRandomImageUrl(seed: randomImageSeedValue + i),
      imageHeight: widget.iconSize,
      showBorder: true,
      showName: false,
      onTap: null,
    );
  }

  Widget _buildParticipantCount() {
    final String text;

    if (isParticipant) {
      final otherParticipantCount = max(0, _participantCount - 1);

      if (widget.showGoingText && otherParticipantCount > 0) {
        text =
            'You + $otherParticipantCount ${otherParticipantCount == 1 ? 'person' : 'people'} are going';
      } else {
        text =
            'You ${_participantCount > 1 ? '+ ${_participantCount - 1}' : ''}';
      }
    } else if (widget.event.useParticipantCountEstimate) {
      text =
          '$_participantCount ${_participantCount == 1 ? 'Person' : 'People'}';
    } else if (_participantCount == 1) {
      // Show a generic count rather than the lone attendee's real name.
      text = '1 person';
    } else if (_participantCount > widget.numberOfIconsToShow) {
      text = '+${_participantCount - widget.numberOfIconsToShow}';
    } else if (_participantCount > 1) {
      text = '$_participantCount People';
    } else {
      text = '';
    }

    return HeightConstrainedText(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: context.theme.textTheme.bodyMedium!
          .copyWith(color: context.theme.colorScheme.onSurface),
    );
  }
}
