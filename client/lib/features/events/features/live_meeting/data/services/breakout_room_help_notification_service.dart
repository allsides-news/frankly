import 'dart:async';

import 'package:client/services.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/core/utils/persistent_f_toast_utils.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/community/membership.dart';
import 'package:flutter/material.dart';

/// Service that tracks when breakout rooms need help and notifies admins via persistent toast notifications.
class BreakoutRoomHelpNotificationService {
  final EventProvider eventProvider;
  final Function() getCurrentBreakoutSessionId;
  BuildContext? _context;

  StreamSubscription<List<BreakoutRoom>>? _breakoutRoomsSubscription;
  Set<String> _lastRoomsNeedingHelp = {};
  Map<String, bool> _dismissedRooms = {}; // Track which rooms admin dismissed
  Set<String> _previouslyDismissedRooms = {}; // Track rooms that were dismissed even after they stop needing help
  Timer? _debounceTimer;

  BreakoutRoomHelpNotificationService({
    required this.eventProvider,
    required this.getCurrentBreakoutSessionId,
  });

  /// Set the context for showing notifications
  void setContext(BuildContext context) {
    _context = context;
  }

  /// Start monitoring for breakout rooms that need help
  void startMonitoring() {
    final breakoutSessionId = getCurrentBreakoutSessionId();
    
    if (breakoutSessionId == null || breakoutSessionId.isEmpty) {
      return;
    }

    _startBreakoutRoomsMonitoring(breakoutSessionId!);
  }

  /// Start monitoring breakout rooms with help requests
  void _startBreakoutRoomsMonitoring(String breakoutSessionId) {
    _breakoutRoomsSubscription?.cancel();
    
    _breakoutRoomsSubscription = firestoreLiveMeetingService
        .breakoutRoomsStream(
      event: eventProvider.event,
      breakoutRoomSessionId: breakoutSessionId,
      filterNeedsHelp: true,
    )
        .listen(
      (rooms) {
        checkBreakoutRoomsNeedingHelp(rooms);
      },
    );
  }

  /// Restart monitoring when breakouts become active
  void restartMonitoring() {
    final breakoutSessionId = getCurrentBreakoutSessionId();
    
    if (breakoutSessionId != null && breakoutSessionId.isNotEmpty) {
      _startBreakoutRoomsMonitoring(breakoutSessionId!);
    }
  }

  /// Stop monitoring for help notifications
  void stopMonitoring() {
    _breakoutRoomsSubscription?.cancel();
    _breakoutRoomsSubscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lastRoomsNeedingHelp = {};
    _dismissedRooms = {};
    _previouslyDismissedRooms = {};
    PersistentFToast.dismiss();
  }

  /// Check for breakout rooms that need help
  void checkBreakoutRoomsNeedingHelp(List<BreakoutRoom> rooms) {
    // Only show notifications if current user is an admin
    final membershipStatus =
        userDataService.getMembership(eventProvider.event.communityId).status;
    
    if (membershipStatus?.isAdmin != true) {
      // If user is not admin, dismiss any existing toast and clear tracking
      if (PersistentFToast.isShowing) {
        PersistentFToast.dismiss();
      }
      _lastRoomsNeedingHelp = {};
      _dismissedRooms = {};
      _previouslyDismissedRooms = {};
      return;
    }

    final currentRoomsNeedingHelp = rooms
        .where((r) => r.flagStatus == BreakoutRoomFlagStatus.needsHelp)
        .map((r) => r.roomId)
        .toSet();

    // Check if the set of rooms needing help has changed
    final roomsChanged = !_setsEqual(_lastRoomsNeedingHelp, currentRoomsNeedingHelp);

    if (!roomsChanged) {
      // If nothing changed, don't do anything unless we need to dismiss
      if (currentRoomsNeedingHelp.isEmpty && PersistentFToast.isShowing) {
        PersistentFToast.dismiss();
        _lastRoomsNeedingHelp = {};
        _dismissedRooms = {};
      }
      return;
    }

    // Cancel any existing debounce timer
    _debounceTimer?.cancel();
    
    // Debounce the notification to prevent rapid flashing
    _debounceTimer = Timer(Duration(milliseconds: 500), () {
      _processBreakoutRoomsHelpChange(currentRoomsNeedingHelp, rooms);
    });
  }

  /// Process breakout rooms help changes
  void _processBreakoutRoomsHelpChange(
    Set<String> currentRoomsNeedingHelp,
    List<BreakoutRoom> allRooms,
  ) {
    if (_context == null) {
      return;
    }

    // Clean up dismissed rooms that no longer need help
    // But keep track of previously dismissed rooms for showing "help was requested"
    final roomsThatStoppedNeedingHelp = _lastRoomsNeedingHelp
        .where((roomId) => !currentRoomsNeedingHelp.contains(roomId))
        .toSet();
    
    // Move dismissed rooms that stopped needing help to previously dismissed set
    for (final roomId in roomsThatStoppedNeedingHelp) {
      if (_dismissedRooms.containsKey(roomId)) {
        _previouslyDismissedRooms.add(roomId);
        _dismissedRooms.remove(roomId);
      }
    }

    // Get active rooms (not dismissed)
    final activeRooms = currentRoomsNeedingHelp
        .where((roomId) => _dismissedRooms[roomId] != true)
        .toSet();

    if (activeRooms.isEmpty) {
      // All rooms were dismissed or no rooms need help, hide notification
      if (PersistentFToast.isShowing) {
        PersistentFToast.dismiss();
      }
      _lastRoomsNeedingHelp = currentRoomsNeedingHelp;
      return;
    }

    // Find newly added rooms (not in last set)
    final newlyNeedingHelp = activeRooms
        .where((roomId) => !_lastRoomsNeedingHelp.contains(roomId))
        .toSet();
    
    // Check if any newly needing help rooms were previously dismissed
    final previouslyDismissedNewRooms = newlyNeedingHelp
        .where((roomId) => _previouslyDismissedRooms.contains(roomId))
        .toSet();
    
    // Build message with all active rooms
    final roomDisplayNames = activeRooms.map((roomId) {
      final room = allRooms.firstWhere(
        (r) => r.roomId == roomId,
        orElse: () => allRooms.first,
      );
      return room.roomId == breakoutsWaitingRoomId
          ? room.roomName
          : 'Room ${room.roomName}';
    }).toList();
    
    // Sort room names for consistent display
    roomDisplayNames.sort();
    
    // Determine message prefix based on whether rooms were previously dismissed
    final hasPreviouslyDismissed = previouslyDismissedNewRooms.isNotEmpty;
    final messagePrefix = hasPreviouslyDismissed ? 'Help was requested in' : 'Help requested in';
    
    // Build the message
    String message;
    if (roomDisplayNames.length == 1) {
      message = '$messagePrefix ${roomDisplayNames.first}';
    } else {
      // Format: "Help requested in Room 1, Room 2, and Room 3"
      final lastRoom = roomDisplayNames.last;
      final roomsList = roomDisplayNames.sublist(0, roomDisplayNames.length - 1).join(', ');
      message = '$messagePrefix $roomsList, and $lastRoom';
    }
    
    // Remove newly added rooms from previously dismissed set since we're showing them
    for (final roomId in previouslyDismissedNewRooms) {
      _previouslyDismissedRooms.remove(roomId);
    }

    // Show notification if:
    // 1. The set of rooms has changed (new room needs help or room was removed), OR
    // 2. No notification is currently showing
    final shouldShow = newlyNeedingHelp.isNotEmpty ||
        roomsThatStoppedNeedingHelp.isNotEmpty ||
        (PersistentFToast.isShowing == false && activeRooms.isNotEmpty);

    if (shouldShow && activeRooms.isNotEmpty) {
      PersistentFToast.show(
        _context!,
        message,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        icon: Icons.help_outline,
        onDismiss: () {
          // Mark all current active rooms as dismissed
          for (final roomId in activeRooms) {
            _dismissedRooms[roomId] = true;
          }
          print('Breakout room help notification dismissed for: ${roomDisplayNames.join(", ")}');
        },
      );
    }

    // Update tracking
    _lastRoomsNeedingHelp = currentRoomsNeedingHelp;
  }

  /// Helper method to compare two sets for equality
  bool _setsEqual<T>(Set<T> set1, Set<T> set2) {
    if (set1.length != set2.length) return false;
    return set1.every((item) => set2.contains(item));
  }

  /// Reset the notification state
  void reset() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _lastRoomsNeedingHelp = {};
    _dismissedRooms = {};
    _previouslyDismissedRooms = {};
    PersistentFToast.dismiss();
  }
}

