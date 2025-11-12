import 'dart:async';

import 'package:client/services.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/core/utils/persistent_f_toast_utils.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/community/membership.dart';
import 'package:flutter/material.dart';

/// Service that tracks when users join the breakout waiting room after the meeting start time
/// and notifies admins via toast notifications.
class WaitingRoomNotificationService {
  final EventProvider eventProvider;
  final Function(String, {bool? hideOnMobile}) showToast;
  final Function() getCurrentBreakoutSessionId;
  final Function(
    BuildContext,
    String, {
    Color backgroundColor,
    Color textColor,
    VoidCallback? onDismiss,
  }) showPersistentToast;

  StreamSubscription<BreakoutRoom?>? _breakoutWaitingRoomRoomSubscription;
  int _lastWaitingRoomCount = 0;
  bool _hasShownNotification = false;
  bool _userDismissedNotification = false;
  List<String> _lastParticipantIds =
      []; // Track actual participant IDs, not just count
  Timer? _debounceTimer; // Add debounce timer to prevent rapid flashing
  String? _lastNotificationMessage; // Track the last message shown

  WaitingRoomNotificationService({
    required this.eventProvider,
    required this.showToast,
    required this.getCurrentBreakoutSessionId,
    required this.showPersistentToast,
  });

  /// Mark that the user has dismissed the notification
  void markNotificationDismissed() {
    _userDismissedNotification = true;
    print('DEBUG: User dismissed notification - marking as dismissed');
    print(
      'DEBUG: State after user dismissal: _hasShownNotification=$_hasShownNotification, _userDismissedNotification=$_userDismissedNotification, _lastWaitingRoomCount=$_lastWaitingRoomCount',
    );
  }

  /// Start monitoring for users joining the breakout waiting room after meeting start time
  void startMonitoring() {
    if (eventProvider.event.eventType != EventType.hostless) {
      return; // Only monitor hostless events
    }

    // Start monitoring when breakouts become active
    _startBreakoutWaitingRoomMonitoring();
  }

  /// Start monitoring the breakout waiting room when breakouts are active
  /// Uses BreakoutRoom.participantIds as the source of truth (server-maintained)
  void _startBreakoutWaitingRoomMonitoring() {
    final breakoutSessionId = getCurrentBreakoutSessionId();
    if (breakoutSessionId != null && breakoutSessionId.isNotEmpty) {
      _breakoutWaitingRoomRoomSubscription?.cancel();
      _breakoutWaitingRoomRoomSubscription = firestoreLiveMeetingService
          .breakoutRoomStream(
            event: eventProvider.event,
            breakoutRoomSessionId: breakoutSessionId,
            breakoutRoomId: breakoutsWaitingRoomId,
          )
          .stream
          .listen(
        (waitingRoom) {
          if (waitingRoom != null) {
            // Use participantIds from BreakoutRoom as the source of truth
            // This is maintained by the server and matches what the UI displays
            final participantIds = waitingRoom.participantIds;
            checkBreakoutWaitingRoomCount(
                participantIds.length, participantIds);
          } else {
            // No waiting room found, treat as empty
            checkBreakoutWaitingRoomCount(0, []);
          }
        },
      );
    }
  }

  /// Restart monitoring when breakouts become active (called from LiveMeetingProvider)
  void restartMonitoring() {
    _startBreakoutWaitingRoomMonitoring();
  }

  /// Stop monitoring for waiting room notifications
  void stopMonitoring() {
    _breakoutWaitingRoomRoomSubscription?.cancel();
    _breakoutWaitingRoomRoomSubscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lastWaitingRoomCount = 0;
    _hasShownNotification = false;
    _userDismissedNotification = false;
    _lastParticipantIds = [];
    _lastNotificationMessage = null;
    PersistentFToast.dismiss();
  }

  /// Check for changes in the breakout waiting room count
  /// Uses participantIds from BreakoutRoom as the source of truth
  void checkBreakoutWaitingRoomCount(int count, List<String> participantIds) {
    final now = clockService.now();
    final meetingStartTime =
        eventProvider.event.timeUntilWaitingRoomFinished(now);

    print(
      'DEBUG: checkBreakoutWaitingRoomCount called with count=$count, participantIds=$participantIds',
    );
    print('DEBUG: meetingStartTime.isNegative=${meetingStartTime.isNegative}');
    print('DEBUG: PersistentFToast.isShowing=${PersistentFToast.isShowing}');
    if (!meetingStartTime.isNegative) {
      // If meeting hasn't started yet, dismiss any existing toast
      if (PersistentFToast.isShowing) {
        print('DEBUG: Dismissing toast - meeting not started yet');
        PersistentFToast.dismiss();
        _hasShownNotification = false; // Reset since this is system dismissal
        _userDismissedNotification = false;
        _lastParticipantIds = [];
        _lastNotificationMessage = null;
      }
      return;
    }

    // Check if we have a breakout session
    final breakoutSessionId = getCurrentBreakoutSessionId();
    print('DEBUG: breakoutSessionId=$breakoutSessionId');
    if (breakoutSessionId == null) {
      // No breakout session - only dismiss if there are no participants
      print(
        'DEBUG: No breakout session, count=$count',
      );
      if (count == 0) {
        // Only dismiss if we have a toast showing and no participants
        if (PersistentFToast.isShowing) {
          print(
            'DEBUG: Dismissing toast - no breakout session and no participants',
          );
          PersistentFToast.dismiss();
          _hasShownNotification = false;
          _userDismissedNotification = false;
          _lastParticipantIds = [];
          _lastNotificationMessage = null;
        }
      }
      return;
    }

    final currentWaitingRoomCount = count;
    final currentParticipantIds = participantIds;

    // Only show notification if current user is host, facilitator, mod, admin, or owner
    final isHost = eventProvider.event.creatorId == userService.currentUserId;
    final membershipStatus =
        userDataService.getMembership(eventProvider.event.communityId).status;
    final canViewCounts = isHost || (membershipStatus?.isFacilitator ?? false);

    print(
      'DEBUG: isHost=$isHost, membershipStatus.isFacilitator=${membershipStatus?.isFacilitator}',
    );
    print('DEBUG: canViewCounts=$canViewCounts');

    if (!canViewCounts) {
      // If user doesn't have permission, only dismiss if there are no participants
      print(
        'DEBUG: User cannot view counts, count=$count',
      );
      if (count == 0) {
        // Only dismiss if we have a toast showing and no participants
        if (PersistentFToast.isShowing) {
          print(
            'DEBUG: Dismissing toast - user cannot view counts and no participants',
          );
          PersistentFToast.dismiss();
          _hasShownNotification = false;
          _userDismissedNotification = false;
          _lastParticipantIds = [];
          _lastNotificationMessage = null;
        }
      }
      _lastParticipantIds = currentParticipantIds; // Update tracking
      return;
    }

    // Only process if the participant list has actually changed
    final participantListChanged =
        !_listsEqual(_lastParticipantIds, currentParticipantIds);
    print('DEBUG: participantListChanged=$participantListChanged');
    print('DEBUG: _lastParticipantIds=$_lastParticipantIds');
    print('DEBUG: currentParticipantIds=$currentParticipantIds');

    if (!participantListChanged) {
      print(
        'DEBUG: Participant list unchanged, syncing toast with current state',
      );
      // Always sync toast state with current waiting room count
      // This ensures toast reflects the source of truth (waiting room state)
      if (currentWaitingRoomCount == 0) {
        // Dismiss toast if waiting room is empty (source of truth)
        if (PersistentFToast.isShowing) {
          print(
            'DEBUG: Participant list unchanged but count is 0, dismissing toast',
          );
          PersistentFToast.dismiss();
          _hasShownNotification = false;
          _userDismissedNotification = false;
          _lastNotificationMessage = null;
        }
        _lastWaitingRoomCount = 0; // Update count to reflect current state
      } else {
        // If count > 0, ensure toast shows correct count
        // Cancel debounce timer and process immediately to sync state
        _debounceTimer?.cancel();
        final previousCount = _lastWaitingRoomCount;
        _lastWaitingRoomCount = currentWaitingRoomCount;
        _processWaitingRoomChange(
          currentWaitingRoomCount,
          previousCount: previousCount,
          isStateSync: true,
        );
      }
      // Update participant IDs to match current state
      _lastParticipantIds = currentParticipantIds;
      return;
    }

    print(
      'DEBUG: Participant list changed from $_lastParticipantIds to $currentParticipantIds',
    );

    // Cancel any existing debounce timer
    _debounceTimer?.cancel();

    // Update participant IDs tracking immediately
    _lastParticipantIds = currentParticipantIds;

    // IMPORTANT: Update count immediately when participant list changes
    // This ensures we always have the correct previous count for comparison
    // even if rapid changes occur before the debounce timer fires
    final previousCount = _lastWaitingRoomCount;
    _lastWaitingRoomCount = currentWaitingRoomCount;

    // Process the change immediately (no debounce) to ensure toast always reflects current state
    // This fixes the issue where rapid changes would skip intermediate counts
    print(
      'DEBUG: Processing change immediately: count=$currentWaitingRoomCount (previous count: $previousCount)',
    );
    _processWaitingRoomChange(
      currentWaitingRoomCount,
      previousCount: previousCount,
      isStateSync: false,
    );
  }

  /// Process waiting room changes
  /// [isStateSync] indicates this is a state synchronization call (participant list unchanged)
  /// vs a change notification (participant list changed)
  /// [previousCount] is the count before this change (used for accurate comparison)
  void _processWaitingRoomChange(
    int currentWaitingRoomCount, {
    bool isStateSync = false,
    int? previousCount,
  }) {
    // Use provided previousCount if available, otherwise use _lastWaitingRoomCount
    final countToCompare = previousCount ?? _lastWaitingRoomCount;
    print(
      'DEBUG: Processing waiting room change: count=$currentWaitingRoomCount, previousCount=$countToCompare, _lastWaitingRoomCount=$_lastWaitingRoomCount, isStateSync=$isStateSync',
    );

    // Always update the toast to reflect the current state of the waiting room (source of truth)
    if (currentWaitingRoomCount == 0) {
      // Dismiss toast if no one is in waiting room
      if (PersistentFToast.isShowing) {
        print('DEBUG: Dismissing toast - no one in waiting room');
        PersistentFToast.dismiss();
        _hasShownNotification = false; // Reset since this is system dismissal
        _userDismissedNotification = false;
        _lastNotificationMessage = null;
      }
      // Update the count after processing
      _lastWaitingRoomCount = currentWaitingRoomCount;
    } else {
      // Show or update persistent toast based on waiting room count
      // Always update to reflect current count, regardless of previous state
      // This ensures toast always matches the waiting room state (source of truth)
      _showPersistentWaitingRoomNotification(
        currentWaitingRoomCount,
        forceUpdate: isStateSync,
        previousCount: previousCount,
      );
      // Count is already updated above, no need to update again
    }
  }

  /// Show the persistent waiting room notification toast
  /// [forceUpdate] forces the toast to update even if user dismissed it (for state sync)
  /// [previousCount] is the count before this change (used for accurate comparison)
  void _showPersistentWaitingRoomNotification(
    int userCount, {
    bool forceUpdate = false,
    int? previousCount,
  }) {
    // Format message according to user requirements:
    // - 1 participant: "participant is in a waiting room"
    // - 2+ participants: "2 participants are in a waiting room"
    final message = userCount == 1
        ? 'Participant is in a waiting room'
        : '$userCount participants are in a waiting room';

    // Use provided previousCount if available, otherwise use _lastWaitingRoomCount
    final countToCompare = previousCount ?? _lastWaitingRoomCount;
    print(
      'DEBUG: _showPersistentWaitingRoomNotification: userCount=$userCount, previousCount=$countToCompare, _lastWaitingRoomCount=$_lastWaitingRoomCount, _userDismissedNotification=$_userDismissedNotification, _lastNotificationMessage=$_lastNotificationMessage, forceUpdate=$forceUpdate',
    );

    // If user dismissed the notification, don't show it again until count changes
    // Unless this is a state sync (forceUpdate=true), in which case we always sync to match waiting room
    if (!forceUpdate &&
        _userDismissedNotification &&
        countToCompare == userCount) {
      print('DEBUG: Skipping notification - user dismissed for this count');
      return;
    }

    // Always update the toast to reflect the current count
    // If the count changed or the message changed, update the toast
    // If forceUpdate is true (state sync), only update if the message would be different
    final countChanged = countToCompare != userCount;
    final messageChanged = _lastNotificationMessage != message;

    // Determine if we should show/update the toast
    // For state sync (forceUpdate), only update if message would change or toast isn't showing
    final shouldUpdate = forceUpdate
        ? (messageChanged ||
            !_hasShownNotification ||
            !PersistentFToast.isShowing)
        : (countChanged || messageChanged || !_hasShownNotification);

    if (shouldUpdate) {
      print(
        'Showing waiting room notification: $message (count changed: $countChanged, message changed: $messageChanged, forceUpdate: $forceUpdate)',
      );

      // Use the showToast callback which will be handled specially in MeetingDialog
      // to show a persistent toast for waiting room notifications
      showToast(message, hideOnMobile: false);

      _hasShownNotification = true;
      _userDismissedNotification =
          false; // Reset dismissal flag when showing new notification
      _lastNotificationMessage = message; // Track the last message shown
    } else {
      print(
        'DEBUG: Skipping notification - same count and message already shown',
      );
    }
  }

  /// Reset the notification state (useful for testing or when meeting restarts)
  void reset() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lastWaitingRoomCount = 0;
    _hasShownNotification = false;
    _userDismissedNotification = false;
    _lastParticipantIds = [];
    _lastNotificationMessage = null;
  }

  /// Helper method to compare two lists for equality
  bool _listsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }
}
