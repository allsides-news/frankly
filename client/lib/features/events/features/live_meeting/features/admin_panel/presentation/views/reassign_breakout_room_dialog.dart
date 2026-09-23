import 'dart:async';

import 'package:flutter/material.dart';
import 'package:client/features/events/features/live_meeting/features/admin_panel/presentation/widgets/admin_panel.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/core/widgets/custom_ink_well.dart';
import 'package:client/core/widgets/custom_stream_builder.dart';
import 'package:client/features/user/presentation/widgets/user_profile_chip.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:client/styles/styles.dart';
import 'package:client/core/data/providers/dialog_provider.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/core/localization/localization_helper.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:provider/provider.dart';

class ReassignResult {
  final String? reassignId;
  final int? expectedNewRoom;

  ReassignResult({required this.reassignId, this.expectedNewRoom});
}

class ReassignBreakoutRoomDialog extends StatefulWidget {
  final BuildContext outerContext;
  final String userId;
  final String? currentRoomNumber;

  /// The room this person is in right now, so the picker can mark it. The
  /// name above can't do this job: it's null for the waiting room, and it's a
  /// display name where the tiles are keyed by id.
  final String? currentRoomId;

  const ReassignBreakoutRoomDialog({
    required this.outerContext,
    required this.userId,
    this.currentRoomNumber,
    this.currentRoomId,
  });

  Future<ReassignResult?> show() async {
    return showCustomDialog<ReassignResult?>(
      builder: (_) => this,
    );
  }

  @override
  _ReassignBreakoutRoomDialogState createState() =>
      _ReassignBreakoutRoomDialogState();
}

/// Tall enough for the densest tile: the "Current" badge, the room name, and
/// the occupancy pill, plus the tile's own padding.
const double _kRoomTileHeight = 96;

class _ReassignBreakoutRoomDialogState
    extends State<ReassignBreakoutRoomDialog> {
  Stream<BreakoutRoomSession>? _sessionDetails;

  BehaviorSubjectWrapper<List<BreakoutRoom>>? _breakoutRooms;

  /// Where this person is now, as it should read on the badge. Null when
  /// they're somewhere that isn't a room -- newly arrived, or on their way to
  /// one that doesn't exist yet.
  String? get _currentRoomLabel {
    final roomId = widget.currentRoomId;
    if (roomId == null || roomId == reassignNewRoomId) return null;
    if (roomId == breakoutsWaitingRoomId) return 'WAITING ROOM';
    final name = widget.currentRoomNumber;
    return name == null ? null : 'ROOM $name';
  }

  @override
  void dispose() {
    _breakoutRooms?.dispose();
    super.dispose();
  }

  Widget _buildBreakoutRoomGrid({
    required BreakoutRoomSession? sessionDetails,
  }) {
    final maxRoomNumber = sessionDetails?.maxRoomNumber;
    final expectedNewRoomNum = maxRoomNumber != null ? maxRoomNumber + 1 : null;

    final hasWaitingRoom = sessionDetails?.hasWaitingRoom ?? false;
    final isMobile = responsiveLayoutService.isMobile(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // Every room is listed, not just the five most recent: these tiles
          // are the only way to choose one now, and capped at five an admin
          // had no way to reach room 2 of twelve.
          //
          // Bounded so a session with many rooms scrolls the tiles rather
          // than growing the dialog past the bottom of the screen.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isMobile ? 320 : 260),
            child: CustomStreamBuilder<List<BreakoutRoom>>(
              entryFrom:
                  '_ReassignBreakoutRoomDialogState._buildBreakoutRoomGrid',
              stream: _breakoutRooms ??=
                  firestoreLiveMeetingService.breakoutRoomsStream(
                event: EventProvider.read(widget.outerContext).event,
                breakoutRoomSessionId:
                    LiveMeetingProvider.read(widget.outerContext)
                            .liveMeeting
                            ?.currentBreakoutSession
                            ?.breakoutRoomSessionId ??
                        '',
                descending: true,
              ),
              height: 100,
              builder: (context, breakoutRooms) {
                final rooms = [
                  if (hasWaitingRoom) fakeWaitingRoomObject,
                  ...(breakoutRooms ?? [])
                      .reversed
                      .where((r) => r.roomId != breakoutsWaitingRoomId)
                      .toList(),
                ];

                return ChangeNotifierProvider.value(
                  value: EventProvider.read(widget.outerContext),
                  child: ChangeNotifierProvider.value(
                    value: LiveMeetingProvider.read(widget.outerContext),
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: rooms.length + 1,
                      itemBuilder: (context, index) {
                        if (index < rooms.length) {
                          final room = rooms[index];
                          final roomNumResult =
                              room.roomId == breakoutsWaitingRoomId
                                  ? breakoutsWaitingRoomId
                                  : room.roomName;
                          final isCurrent = widget.currentRoomId != null &&
                              room.roomId == widget.currentRoomId;
                          return BreakoutRoomButton(
                            room: room,
                            style: BreakoutRoomButtonStyle.picker,
                            isCurrentOverride: isCurrent,
                            // Moving someone to where they already are isn't a
                            // move. A null onTap leaves CustomInkWell inert --
                            // no hover fill, no pointer cursor -- and the
                            // "Current" badge says why.
                            onTap: isCurrent
                                ? null
                                : () => Navigator.of(context).pop(
                                      ReassignResult(reassignId: roomNumResult),
                                    ),
                          );
                        }

                        return CustomInkWell(
                          onTap: () => Navigator.of(context).pop(
                            ReassignResult(
                              reassignId: reassignNewRoomId,
                              expectedNewRoom: expectedNewRoomNum,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: context
                                  .theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Same surface/onSurface pairing the room
                                // tiles beside this one use.
                                Icon(
                                  Icons.add,
                                  size: 36,
                                  color: context.theme.colorScheme.onSurface,
                                ),
                                SizedBox(height: 6),
                                HeightConstrainedText(
                                  'Add Room $expectedNewRoomNum',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: context.theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        // Two up on a phone: three 140-wide tiles don't fit, and
                        // squeezing them truncates the room names.
                        crossAxisCount: isMobile ? 2 : 3,
                        // A fixed height rather than an aspect ratio, which
                        // ties height to width and so to the screen. At
                        // 140:80 a 360px phone gave 114-wide cells and 65 of
                        // height -- against ~71 for the Add Room tile and ~79
                        // for one carrying the "Current" badge, so both
                        // overflowed. 96 clears the tallest with room to
                        // spare, at any width.
                        mainAxisExtent: _kRoomTileHeight,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Who is being moved, kept in front of the admin while they choose. An
  /// admin opens this from a roster of similar-looking rows, and the room
  /// tiles below say nothing about whose they'd be.
  Widget _buildSubject(BuildContext context) {
    final currentRoom = _currentRoomLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: UserProfileChip(
              userId: widget.userId,
              imageHeight: 28,
              // A header, not a link: this dialog is a decision about this
              // person, and leaving for their profile abandons it.
              enableOnTap: false,
            ),
          ),
          if (currentRoom != null) ...[
            SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: context.theme.colorScheme.onSurface,
                borderRadius: BorderRadius.circular(30),
              ),
              child: HeightConstrainedText(
                currentRoom,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: context.theme.colorScheme.surface,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          // Balances the close button so the title sits centred.
          SizedBox(width: 40),
          Expanded(
            child: HeightConstrainedText(
              context.l10n.reassign,
              textAlign: TextAlign.center,
              style: context.theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.theme.colorScheme.onSurface,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close),
            color: context.theme.colorScheme.onSurfaceVariant,
            tooltip: 'Close',
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Matches the other dialogs: the same surface, radius and hairline border.
    // This one had grown its own look -- a hardcoded 2px blue frame, with the
    // title in a filled tab hanging off the top-left corner.
    return Dialog(
      backgroundColor: context.theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppNeutralColors.of(context).neutral300),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 500),
        child: CustomStreamBuilder<BreakoutRoomSession>(
          entryFrom: '_ReassignBreakoutRoomDialogState.build',
          stream: _sessionDetails ??= firestoreLiveMeetingService
              .getBreakoutRoomSession(
                event: EventProvider.read(widget.outerContext).event,
                breakoutSessionId: LiveMeetingProvider.read(widget.outerContext)
                        .liveMeeting
                        ?.currentBreakoutSession
                        ?.breakoutRoomSessionId ??
                    '',
              )
              .asStream(),
          builder: (context, sessionDetails) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTitleRow(context),
              Divider(
                height: 1,
                color: AppNeutralColors.of(context).neutral300,
              ),
              _buildSubject(context),
              Divider(
                height: 1,
                color: AppNeutralColors.of(context).neutral300,
              ),
              SizedBox(height: 16),
              _buildBreakoutRoomGrid(sessionDetails: sessionDetails),
              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
