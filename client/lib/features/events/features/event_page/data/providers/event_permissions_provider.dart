import 'package:client/core/utils/provider_utils.dart';
import 'package:flutter/material.dart';
import 'package:client/features/community/data/providers/community_permissions_provider.dart';
import 'package:client/features/events/features/event_page/data/providers/event_provider.dart';
import 'package:client/features/events/features/live_meeting/data/providers/live_meeting_provider.dart';
import 'package:client/features/community/data/providers/community_provider.dart';
import 'package:client/services.dart';
import 'package:data_models/chat/chat.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/community/membership.dart';
import 'package:provider/provider.dart';

/// This class provides the user's permissions in relation to a particular event
class EventPermissionsProvider with ChangeNotifier {
  final EventProvider eventProvider;
  final CommunityProvider communityProvider;
  final CommunityPermissionsProvider communityPermissions;

  EventPermissionsProvider({
    required this.eventProvider,
    required this.communityPermissions,
    required this.communityProvider,
  });

  void initialize() => userDataService.addListener(() => notifyListeners());

  bool get avCheckEnabled =>
      communityProvider.settings.enableAVCheck &&
      eventProvider.event.eventType == EventType.hosted;

  bool get showTalkingTimeWarnings => !_isHost;

  bool get isAgendaVisibleOverride =>
      _isHost || communityPermissions.membershipStatus.isFacilitator;

  bool get canDuplicateEvent => communityPermissions.canCreateEvent;

  bool get canRefreshGuide => communityPermissions.membershipStatus.isMod;

  bool get canChat => eventProvider.isParticipant || canEditEvent;

  bool get canEditEvent {
    if (communityProvider.settings.allowUnofficialTemplates) {
      return _isHost || communityPermissions.membershipStatus.isMod;
    } else {
      return (_isHost && communityPermissions.membershipStatus.isFacilitator) ||
          communityPermissions.membershipStatus.isMod;
    }
  }

  bool get canDownloadRegistrationData =>
      communityPermissions.membershipStatus.isAdmin;

  bool get canModerateSuggestions =>
      _isHost || communityPermissions.membershipStatus.isMod;

  bool get canCancelEvent =>
      _isHost || communityPermissions.membershipStatus.isMod;

  bool get canAccessAdminTabInEvent {
    return _isHost || communityPermissions.membershipStatus.isFacilitator;
  }

  /// Checks if user can view participant counts in events, waiting rooms, and breakout rooms.
  /// Hosts, facilitators, moderators, admins, and owners can all see participant counts.
  bool get canViewParticipantCounts {
    return _isHost || communityPermissions.membershipStatus.isFacilitator;
  }

  bool get canEditEventTitle {
    return canEditEvent &&
            (communityProvider.settings.allowUnofficialTemplates) ||
        communityPermissions.membershipStatus.isMod;
  }

  bool get canStartEvent =>
      _isHost || communityPermissions.membershipStatus.isMod;

  bool get canCancelParticipation {
    return !_isHost && eventProvider.isParticipant;
  }

  bool get canJoinEvent {
    // Check if event has ended based on duration
    if (eventProvider.event.hasEnded(clockService.now())) {
      return false;
    }

    if (eventProvider.event.isLocked) {
      return false;
    } else if (communityProvider.settings.requireApprovalToJoin) {
      return communityPermissions.membershipStatus.isMember;
    } else {
      return communityPermissions.membershipStatus.isNotBanned;
    }
  }

  bool get _isHost {
    final currentUser = userService.currentUserId;
    return currentUser != null && 
           eventProvider.event.creatorId == currentUser;
  }

  bool get canBroadcastChat =>
      _isHost || communityPermissions.membershipStatus.isMod;

  /// Returns true if the user should have chat disabled in hostless waiting room.
  /// Members and Attendees cannot chat in hostless waiting room, but can chat in breakouts.
  bool shouldDisableChatInHostlessWaitingRoom(BuildContext context) {
    // Only disable for hostless events
    if (eventProvider.event.eventType != EventType.hostless) {
      return false;
    }

    // Check if we have a LiveMeetingProvider available
    final liveMeetingProvider = watchProviderOrNull<LiveMeetingProvider>(context);
    
    // Only disable in waiting room, not in breakouts
    final isInWaitingRoom = liveMeetingProvider?.shouldBeInWaitingRoom ?? false;
    final isInBreakout = liveMeetingProvider?.isInBreakout ?? false;
    
    if (!isInWaitingRoom || isInBreakout) {
      return false;
    }

    // Disable for Members and Attendees only
    // Facilitators, Mods, Admins, and Owners can still chat
    final status = communityPermissions.membershipStatus;
    final isRestrictedRole = 
        (status == MembershipStatus.member || 
         status == MembershipStatus.attendee) &&
        !status.isFacilitator;
    
    return isRestrictedRole;
  }

  bool get canPinItemInParticipantWidget => _isHost;

  bool canMuteParticipantInParticipantWidget(String userId) =>
      userId != userService.currentUserId && _isHost;

  bool canKickParticipantInParticipantWidget(String userId) =>
      userId != userService.currentUserId &&
      eventProvider.event.eventType == EventType.hostless;

  bool get canParticipate => eventProvider.isParticipant;

  bool canDeleteEventMessage(ChatMessage message) =>
      userService.currentUserId != null &&
      (userService.currentUserId == message.creatorId ||
          communityPermissions.canModerateContent);

  bool canDeleteSuggestedItem(SuggestedAgendaItem item) =>
      (item.creatorId == userService.currentUserId) ||
      _isHost ||
      communityPermissions.canModerateContent;

  bool canRemoveParticipant(Participant participant) {
    final participantIsHostOfEvent =
        participant.id == eventProvider.event.creatorId;
    final participantIsUser = participant.id == userService.currentUserId;

    return !participantIsHostOfEvent &&
        (_isHost ||
            participantIsUser ||
            communityPermissions.canModerateContent);
  }

  static EventPermissionsProvider? watch(BuildContext context) =>
      providerOrNull(() => Provider.of<EventPermissionsProvider>(context));

  static EventPermissionsProvider? read(BuildContext context) => providerOrNull(
        () => Provider.of<EventPermissionsProvider>(context, listen: false),
      );
}
