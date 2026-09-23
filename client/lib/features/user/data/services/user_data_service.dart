import 'dart:async';

import 'package:client/features/auth/utils/auth_utils.dart';
import 'package:client/core/utils/extensions.dart';
import 'package:client/core/data/services/logging_service.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:client/core/widgets/confirm_dialog.dart';
import 'package:client/core/utils/visible_exception.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:data_models/analytics/analytics_entities.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/community/community.dart';
import 'package:data_models/community/membership.dart';
import 'package:rxdart/rxdart.dart';

class UserDataService with ChangeNotifier {
  String? _currentUserId;

  BehaviorSubjectWrapper<List<Membership>> _memberships =
      BehaviorSubjectWrapper<List<Membership>>(Stream.value([]));
  Stream<List<Membership>> get memberships => _memberships.stream;
  StreamSubscription? _membershipsSubscription;
  StreamSubscription? _connectedSubscription;
  DatabaseReference? _userStatusDatabaseRef;

  final _userCommunities = BehaviorSubject<List<Community>>.seeded(const []);
  Stream<List<Community>> get userCommunities => _userCommunities.stream;

  static bool usingEmulator = false;

  Future<void> initialize() async {
    if (usingEmulator) {
      FirebaseDatabase.instance.useDatabaseEmulator('localhost', 9000);
    }
    userService.addListener(_onUserServiceChanged);
    // [initializeServices] runs this in parallel with [userService.initialize].
    // Auth may emit and call [userService.notifyListeners] before we subscribed
    // above; ChangeNotifier does not replay past events, so we could otherwise
    // never call [_loadUserData] and "My spaces" stays empty until the next auth change.
    _onUserServiceChanged();
  }

  void _onUserServiceChanged() {
    if (_currentUserId == userService.currentUserId) {
      return;
    }
    _currentUserId = userService.currentUserId;
    _loadUserData();

    // Setup a listener so that when users disconnect, we can update things in our backend
    // Cancel the server-side onDisconnect handler and Dart-side listener
    // before setting up new ones for the incoming user.
    _userStatusDatabaseRef?.onDisconnect().cancel().catchError((e) {
      debugPrint('Failed to cancel onDisconnect handler on user change: $e');
    });
    _connectedSubscription?.cancel();
    _connectedSubscription = null;
    _userStatusDatabaseRef = null;

    if (_currentUserId != null) {
      // Create a reference to this user's specific status node.
      // This is where we will store data about being online/offline.
      _userStatusDatabaseRef =
          FirebaseDatabase.instance.ref('/status/$_currentUserId');
      final userStatusDatabaseRef = _userStatusDatabaseRef!;

      // We'll create two constants which we will write to
      // the Realtime database when this device is offline
      // or online.
      final isOfflineForDatabase = {
        'state': 'offline',
        'last_changed': ServerValue.timestamp,
      };

      final isOnlineForDatabase = {
        'state': 'online',
        'last_changed': ServerValue.timestamp,
      };

      // Capture the user ID once at subscription-setup time, not inside
      // the callback. This prevents a rapid sign-out + re-login race where
      // a buffered .info/connected event fires after the new user's ID is
      // set, causing capturedUserId to capture the new user's ID and the
      // guard to incorrectly pass while writing to the old user's RTDB ref.
      final subscriptionUserId = _currentUserId;

      // Create a reference to the special '.info/connected' path in
      // Realtime Database. This path returns `true` when connected
      // and `false` when disconnected.
      _connectedSubscription = FirebaseDatabase.instance
          .ref('.info/connected')
          .onValue
          .listen((event) {
        final isConnected = event.snapshot.value as bool?;

        // If we're not currently connected, don't do anything.
        if (isConnected == false) {
          return;
        }

        // Bail if the user changed between subscription setup and event
        // delivery — including the sign-out case (subscriptionUserId == null).
        if (subscriptionUserId == null ||
            _currentUserId != subscriptionUserId) {
          return;
        }

        // If we are currently connected, then use the 'onDisconnect()'
        // method to add a set which will only trigger once this
        // client has disconnected by closing the app,
        // losing internet, or any other means.
        userStatusDatabaseRef
            .onDisconnect()
            .set(isOfflineForDatabase)
            .then((_) {
          // The promise returned from .onDisconnect().set() will
          // resolve as soon as the server acknowledges the onDisconnect()
          // request, NOT once we've actually disconnected:
          // https://firebase.google.com/docs/reference/dart/firebase.database.OnDisconnect

          // Second guard for the async gap between the event and the
          // onDisconnect().set() future resolving.
          if (_currentUserId != subscriptionUserId) return;

          // We can now safely set ourselves as 'online' knowing that the
          // server will mark us as offline once we lose connection.
          debugPrint(
            'OnDisconnect function activated. User is logged as being online.',
          );
          userStatusDatabaseRef.set(isOnlineForDatabase).catchError((e) {
            debugPrint('Failed to set online status: $e');
          });
        }).catchError((e) {
          // If onDisconnect registration fails, do not mark user as online —
          // Firebase would never receive the offline callback on disconnect.
          debugPrint('Failed to register onDisconnect handler: $e');
        });
      });
    }
  }

  @override
  void dispose() {
    userService.removeListener(_onUserServiceChanged);
    _userStatusDatabaseRef?.onDisconnect().cancel().catchError((e) {
      debugPrint('Failed to cancel onDisconnect handler on dispose: $e');
    });
    _connectedSubscription?.cancel();
    _membershipsSubscription?.cancel();
    _memberships.dispose();
    _userCommunities.close();
    super.dispose();
  }

  void _loadUserData() {
    final userId = _currentUserId;
    // If we had been listening to the previous user's membership stream then cancel it.
    _membershipsSubscription?.cancel();
    _membershipsSubscription = null;
    _memberships.disposeSync();

    if (userId == null || !userService.isSignedIn) {
      _memberships = BehaviorSubjectWrapper<List<Membership>>(Stream.value([]));
      if (!_userCommunities.isClosed) {
        _userCommunities.add([]);
      }
    } else {
      // Load new memberships stream for user
      _memberships = firestoreMembershipService.userMembershipsStream(userId);

      // Listen to stream.  If memberships change, load new stream.
      _membershipsSubscription =
          _memberships.stream.listen(
        (membershipList) async {
          try {
            // Include attendee-only associations so "My spaces" matches how users think
            // about spaces they've joined for events; still excludes nonmember/banned.
            final communityIds = membershipList
                .where((m) => m.isAttendee)
                .map((m) => m.communityId)
                .toList();
            if (kDebugMode) {
              debugPrint(
                'UserDataService: uid=$userId membership docs=${membershipList.length} '
                'after isAttendee filter=${communityIds.length} '
                'statuses=${membershipList.map((m) => m.status).toList()}',
              );
            }
            final communityDocs =
                await firestoreDatabase.getCommunityDocuments(communityIds);
            if (kDebugMode) {
              debugPrint(
                'UserDataService: resolved communities=${communityDocs.withoutNulls.length}',
              );
            }
            _userCommunities.add(communityDocs.withoutNulls.toList());
            notifyListeners();
          } catch (e, stack) {
            loggingService.log(
              'UserDataService: failed to resolve communities for memberships',
              logType: LogType.error,
              error: e,
              stackTrace: stack,
            );
            if (!_userCommunities.isClosed) {
              _userCommunities.add([]);
            }
            notifyListeners();
          }
        },
        onError: (Object e, StackTrace stack) {
          loggingService.log(
            'UserDataService: memberships stream error',
            logType: LogType.error,
            error: e,
            stackTrace: stack,
          );
          if (!_userCommunities.isClosed) {
            _userCommunities.add([]);
          }
          notifyListeners();
        },
      );
    }

    notifyListeners();
  }

  Membership getMembership(String communityId) {
    // Auth can emit null (network flicker, sign-out, failed anonymous sign-in).
    // Callers treat this as "not a member"; do not throw on currentUserId!.
    final membership = Membership(
      userId: userService.currentUserId ?? _currentUserId ?? '',
      communityId: communityId,
      status: MembershipStatus.nonmember,
    );

    return _memberships.stream.valueOrNull?.firstWhere(
          (membership) => membership.communityId == communityId,
          orElse: () => membership,
        ) ??
        membership;
  }

  bool isMember({required String communityId}) =>
      getMembership(communityId).isMember;

  /// Make membership change
  Future<void> changeCommunityMembership({
    required String communityId,
    required String userId,
    required MembershipStatus newStatus,
    String? communityName,
    bool allowMemberDowngrade = true,
  }) async {
    final membership = await firestoreMembershipService
        .getMembershipForUser(
          userId: userId,
          communityId: communityId,
        )
        .first;

    var skipUpdate = membership?.status == newStatus;
    if (!allowMemberDowngrade &&
        [MembershipStatus.member, MembershipStatus.attendee]
            .contains(newStatus) &&
        (membership?.isMember ?? false)) {
      skipUpdate = true;
    }

    if (!skipUpdate) {
      await cloudFunctionsCommunityService.updateMembership(
        UpdateMembershipRequest(
          communityId: communityId,
          status: newStatus,
          userId: userId,
          invisible: null,
        ),
      );

      final wasMember = membership?.isMember ?? false;
      final isNowMember = newStatus.isMember;
      if (!wasMember && isNowMember) {
        analytics.logEvent(
          AnalyticsJoinCommunityEvent(communityId: communityId),
          communityName: communityName,
        );
      } else if (wasMember && !isNowMember) {
        analytics.logEvent(
          AnalyticsLeaveCommunityEvent(communityId: communityId),
          communityName: communityName,
        );
      }
    }
  }

  /// Trigger UI to change membership
  Future<void> requestChangeCommunityMembership({
    required Community community,
    required bool join,
  }) async {
    return guardSignedIn(() async {
      // This should already be handled by firestore rules but this would make a better error message.
      if (userDataService.getMembership(community.id).isAdmin && !join) {
        throw VisibleException('Cannot leave space you are admin of.');
      }

      if (!join) {
        final unsubscribe = await ConfirmDialog(
          title: appLocalizationService.getLocalization().unfollow,
          mainText:
              'Are you sure you want to unsubscribe from ${community.name}?',
          confirmText: 'Yes',
          cancelText: 'No',
        ).show();
        if (unsubscribe != true) {
          return;
        }
      }
      await userDataService.changeCommunityMembership(
        communityId: community.id,
        userId: userService.currentUserId!,
        newStatus: join ? MembershipStatus.member : MembershipStatus.nonmember,
        allowMemberDowngrade: false,
        communityName: community.name,
      );
    });
  }
}
