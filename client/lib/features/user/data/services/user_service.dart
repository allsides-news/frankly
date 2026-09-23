import 'dart:async';

import 'package:client/core/data/services/logging_service.dart';
import 'package:client/core/utils/error_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:client/features/user/data/providers/user_info_builder.dart';
import 'package:client/core/utils/visible_exception.dart';
import 'package:client/services.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/community/community_user_settings.dart';
import 'package:data_models/community/member_details.dart';
import 'package:data_models/user/public_user_info.dart';
import 'package:data_models/utils/utils.dart';
import 'package:pedantic/pedantic.dart';
import 'package:quiver/iterables.dart';
import 'package:rxdart/rxdart.dart';
import 'package:universal_html/html.dart' as html;

enum SignInState {
  loading,
  signedIn,
  signedOut,
}

/// What to do after [UserService]'s auth listener (or a retry) throws.
///
/// [authStateChanges] does not re-emit when the network returns if Firebase's
/// user is unchanged, so we cannot wait for another event to leave the splash.
@visibleForTesting
enum AuthFailureRecovery {
  /// Firebase already has a user; finish sign-in so the splash can dismiss.
  completeSignIn,

  /// No user yet and the error is a flaky network; try anonymous sign-in again.
  retryAnonymousSignIn,

  /// No user and the error will not heal itself; show the signed-out refresh UI.
  markSignedOut,
}

@visibleForTesting
AuthFailureRecovery recoveryForAuthFailure({
  required bool hasCurrentUser,
  required bool isTransientNetworkError,
}) {
  if (hasCurrentUser) return AuthFailureRecovery.completeSignIn;
  if (isTransientNetworkError) {
    return AuthFailureRecovery.retryAnonymousSignIn;
  }
  return AuthFailureRecovery.markSignedOut;
}

/// Unexpected failures still go to [runZonedGuarded] / Sentry. Skip expected
/// Auth network flickers and security-rule denials.
@visibleForTesting
bool shouldReportAuthFailure(Object error) {
  return !isTransientAuthNetworkError(error) && !isPermissionDeniedError(error);
}

class UserService with ChangeNotifier {
  static bool usingEmulator = false;
  static const _anonSignInRetryDelay = Duration(seconds: 2);
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  // ignore: close_sinks
  final BehaviorSubject<String> _currentUserChanges = BehaviorSubject();

  Timer? _returningUserTimer;
  Timer? _anonSignInRetryTimer;
  User? _currentUser;

  bool _signingInAnonymously = false;
  bool _redirectResultHandled = false;

  String? _redirectErrorMessage;

  /// Holds the display name to use with email registration.
  ///
  /// This display name is used by the authStateChanges callback to know what name to store for
  /// this user.
  String? _emailRegistrationDisplayName;

  SignInState _signInState = SignInState.loading;

  void verifyEmail() {
    _currentUser?.sendEmailVerification();
  }

  /// If there was an error signing in during redirect this flag indicates that.
  String? get redirectErrorMessage => _redirectErrorMessage;

  String? get currentUserId => _currentUser?.uid;

  Stream<String> get currentUserChanges => _currentUserChanges;

  FirebaseAuth get firebaseAuth => _firebaseAuth;

  bool get isSignedIn {
    final localCurrentUser = _currentUser;
    return localCurrentUser != null && !localCurrentUser.isAnonymous;
  }

  SignInState get signInState => _signInState;

  void _setCurrentUser(User user) {
    if (_currentUser?.uid != user.uid) {
      _currentUserChanges.add(user.uid);
    }
    _currentUser = user;
  }

  /// If we determine they are a returning user we expect firebase to sign them in automatically.
  ///
  /// We wait for a period and if we don't see them get signed in, we sign in anonymously.
  void _handleReturningUser() {
    _returningUserTimer = Timer(Duration(seconds: 1), () {
      final user = _firebaseAuth.currentUser;
      if (user != null) {
        // This path happens during hot reload mostly.
        loggingService.log(
          'Returning user timer has expired, but there is a current user so not signing in anonymously',
        );
        unawaited(_handleUserSignedIn(user));
        return;
      }
      loggingService
          .log('Returning user timer has expired, signing in anonymously');
      unawaited(_signInAnonymouslyOrRecover());
    });
  }

  /// Handle redirect sign in failures by showing a dialog.
  ///
  /// After a user signs in using google they are redirected back to our site.
  /// If they signed in successfully firebase auth signs them in. However, if they failed for some
  /// reason we have to check the redirectResult which will throw an error.
  Future<void> _handleRedirectResult() async {
    if (!_redirectResultHandled) {
      _redirectResultHandled = true;

      try {
        await _firebaseAuth.getRedirectResult();
      } catch (e) {
        // If the error is a FirebaseAuthException that contains TypeError then it can be ignored.
        // It shows up due to an apparent bug in firebase auth that throws an exception if there
        // is no redirect result pending.
        if (!e.toString().contains('An unknown error occurred')) {
          _redirectErrorMessage = e.toString();
          notifyListeners();
        }
      }
    }
  }

  Future<void> initialize() async {
    if (usingEmulator) {
      await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
    }
    await sharedPreferencesService.initialize();
    if (sharedPreferencesService.isReturningUser()) {
      _handleReturningUser();
    }

    _firebaseAuth.authStateChanges().listen((user) async {
      loggingService.log(
        'Firebase user updated ${user?.uid}: Email - ${user?.email} Anonymous: ${user?.isAnonymous}',
      );

      // Keep [_currentUser] in sync with [user] *before* notifying. Otherwise the first
      // [notifyListeners] can run while [currentUserId] / [isSignedIn] still describe the
      // previous account (e.g. anonymous → real user), and services such as [UserDataService]
      // can miss a transition or load membership under the wrong uid.
      if (user != null) {
        _setCurrentUser(user);
      } else {
        _currentUser = null;
      }

      notifyListeners();

      // On macos it throws un-implemented error, thus wrap in control flow
      if (kIsWeb) {
        unawaited(_handleRedirectResult());
      }

      if (!sharedPreferencesService.isReturningUser() &&
          user == null &&
          !_signingInAnonymously) {
        await _signInAnonymouslyOrRecover();
      } else if (user == null && _signInState == SignInState.signedIn) {
        _signInState = SignInState.signedOut;
        notifyListeners();
      } else if (user != null) {
        await _handleUserSignedIn(user);
      }
    });
  }

  void _recoverFromAuthFailure(Object e, StackTrace st) {
    final transient = isTransientAuthNetworkError(e);
    if (transient) {
      loggingService.log(
        'Auth state change hit a transient network error',
        logType: LogType.warning,
        error: e,
        stackTrace: st,
      );
    }

    switch (recoveryForAuthFailure(
      hasCurrentUser: _currentUser != null,
      isTransientNetworkError: transient,
    )) {
      case AuthFailureRecovery.completeSignIn:
        _markSignedIn();
        break;
      case AuthFailureRecovery.retryAnonymousSignIn:
        _scheduleAnonymousSignInRetry();
        break;
      case AuthFailureRecovery.markSignedOut:
        if (_signInState == SignInState.loading) {
          _signInState = SignInState.signedOut;
          notifyListeners();
        }
        break;
    }
  }

  void _markSignedIn() {
    _returningUserTimer?.cancel();
    _anonSignInRetryTimer?.cancel();
    if (_signInState == SignInState.signedIn) return;
    _signInState = SignInState.signedIn;
    notifyListeners();
  }

  void _scheduleAnonymousSignInRetry() {
    if (_currentUser != null || _signingInAnonymously) return;
    if (_returningUserTimer?.isActive ?? false) return;
    if (_anonSignInRetryTimer?.isActive ?? false) return;

    _anonSignInRetryTimer = Timer(_anonSignInRetryDelay, () {
      if (_currentUser != null || _signingInAnonymously) return;
      unawaited(_signInAnonymouslyOrRecover());
    });
  }

  Future<void> _signInAnonymouslyOrRecover() async {
    try {
      await signInAnonymously();
    } catch (e, st) {
      // Leave the splash, then rethrow unexpected errors so runZonedGuarded
      // still reports them. Transient Auth network failures are expected.
      _recoverFromAuthFailure(e, st);
      if (shouldReportAuthFailure(e)) {
        Error.throwWithStackTrace(e, st);
      }
    }
  }

  Future<void> _handleUserSignedIn(User user) async {
    unawaited(sharedPreferencesService.setIsReturningUser(true));
    _setCurrentUser(user);
    // Dismiss the splash as soon as Firebase has a user. Profile writes can
    // fail or hang on a flaky network; do not keep [SignInState.loading].
    _markSignedIn();

    if (!user.isAnonymous) {
      try {
        await createCurrentUserInfoIfNotExists(
          displayName: _emailRegistrationDisplayName,
        );
      } catch (e, st) {
        if (!shouldReportAuthFailure(e)) {
          loggingService.log(
            'Failed to create or reload public user info after sign-in',
            logType: LogType.warning,
            error: e,
            stackTrace: st,
          );
          return;
        }
        Error.throwWithStackTrace(e, st);
      }
    }
  }

  PublicUserInfo getDefaultPublicUserInfo({String? displayName}) {
    final currentUser = _currentUser;
    if (currentUser == null) {
      throw StateError('Cannot build public user info while signed out');
    }
    return PublicUserInfo(
      id: currentUser.uid,
      agoraId: uidToInt(currentUser.uid),
      displayName:
          firstAndLastInitial(displayName ?? currentUser.displayName) ??
              'User-${currentUser.uid.substring(0, 4)}',
      imageUrl: isNullOrEmpty(currentUser.photoURL)
          ? 'https://picsum.photos/seed/${currentUser.uid}/80'
          : currentUser.photoURL,
    );
  }

  CommunityUserSettings getDefaultCommunityUserSettings({
    required String communityId,
  }) {
    return CommunityUserSettings(
      userId: _currentUser!.uid,
      communityId: communityId,
      notifyAnnouncements: NotificationEmailType.immediate,
      notifyEvents: NotificationEmailType.immediate,
    );
  }

  Future<void> updateCommunityUserSettings(
    CommunityUserSettings settings,
  ) async {
    await firestorePrivateUserDataService.updateCommunityUserSettings(
      communityUserSettings: settings,
    );
  }

  Future<void> createCurrentUserInfoIfNotExists({String? displayName}) async {
    if (_currentUser == null) return;
    loggingService.log(
      'UserService.createCurrentUserInfoIfNotExists: updating current user info to $displayName',
    );
    final userInfo = await firestoreUserService.getOrCreatePublicUserInfo(
      defaultUserInfo: getDefaultPublicUserInfo(displayName: displayName),
    );

    final userId = currentUserId;
    if (userId == null) return;

    // Update the agora ID for anyone who logs in
    unawaited(updateCurrentUserInfo(userInfo, [PublicUserInfo.kFieldAgoraId]));

    UserInfoProvider.reloadUser(userId);
  }

  Future<void> updateCurrentUserInfo(
    PublicUserInfo newUserInfo,
    Iterable<String> keys,
  ) async {
    await firestoreUserService.updatePublicUser(
      userInfo: newUserInfo,
      keys: keys,
    );
    final userId = currentUserId;
    if (userId == null) return;
    UserInfoProvider.reloadUser(userId);
  }

  Future<UserCredential> signInAnonymously() async {
    _signingInAnonymously = true;
    loggingService.log('signing in anonymously');
    try {
      return await _firebaseAuth.signInAnonymously();
    } finally {
      _signingInAnonymously = false;
    }
  }

  Future<void> signOut() async {
    await sharedPreferencesService.setIsReturningUser(false);
    try {
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (e, st) {
      // Returning-user is already cleared; always reload so we never stay in a
      // half-signed-out UI if the Auth RPC fails for any code.
      loggingService.log(
        'signOut: FirebaseAuthException (${e.code}), reloading anyway',
        logType: LogType.warning,
        error: e,
        stackTrace: st,
      );
    }

    html.window.location.reload();
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = userCredential.user;
    if (user != null) {
      await _handleUserSignedIn(user);
    }
  }

  Future<void> signInWithGoogle() async {
    await _firebaseAuth.signInWithRedirect(
      GoogleAuthProvider()..setCustomParameters({'prompt': 'select_account'}),
    );
  }

  Future<void> registerWithEmail({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (displayName.trim().isEmpty) {
      throw VisibleException('Your name is required.');
    }
    // Store the display name in this variable so that the authStateChanges callback will know what
    // to set the users name as.
    _emailRegistrationDisplayName = displayName;
    try {
      await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      _emailRegistrationDisplayName = null;
      rethrow;
    }
  }

  Future<void> resetPassword({required String email}) {
    if (email.trim().isEmpty) {
      throw VisibleException('Email must be entered to reset password.');
    }

    return firebaseAuth.sendPasswordResetEmail(email: email);
  }

  Future<List<MemberDetails>> getMemberDetails({
    required List<String> membersList,
    required String communityId,
    String? eventPath,
  }) async {
    final responseFutures = <Future<GetMembersDataResponse>>[];
    for (final membersListBatch in partition(membersList, 1000)) {
      responseFutures.add(
        cloudFunctionsCommunityService.getMembersData(
          request: GetMembersDataRequest(
            communityId: communityId,
            userIds: membersListBatch,
            eventPath: eventPath,
          ),
        ),
      );
    }
    final responses = await Future.wait(responseFutures);
    final membersDetailsLists =
        responses.map((response) => response.membersDetailsList ?? []);
    final members = <MemberDetails>[];
    for (final list in membersDetailsLists) {
      members.addAll(list);
    }
    return members;
  }
}
