import 'package:client/features/user/data/services/user_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('recoveryForAuthFailure', () {
    test('completes sign-in when Firebase already has a user', () {
      expect(
        recoveryForAuthFailure(
          hasCurrentUser: true,
          isTransientNetworkError: true,
        ),
        AuthFailureRecovery.completeSignIn,
      );
      expect(
        recoveryForAuthFailure(
          hasCurrentUser: true,
          isTransientNetworkError: false,
        ),
        AuthFailureRecovery.completeSignIn,
      );
    });

    test('retries anonymous sign-in on a transient error with no user', () {
      expect(
        recoveryForAuthFailure(
          hasCurrentUser: false,
          isTransientNetworkError: true,
        ),
        AuthFailureRecovery.retryAnonymousSignIn,
      );
    });

    test('marks signed out on a permanent error with no user', () {
      expect(
        recoveryForAuthFailure(
          hasCurrentUser: false,
          isTransientNetworkError: false,
        ),
        AuthFailureRecovery.markSignedOut,
      );
    });
  });

  group('shouldReportAuthFailure', () {
    test('is false for transient Auth network and permission-denied', () {
      expect(
        shouldReportAuthFailure(
          '[firebase_auth/network-request-failed] A network AuthError has occurred.',
        ),
        isFalse,
      );
      expect(
        shouldReportAuthFailure(
          '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
        ),
        isFalse,
      );
    });

    test('is true for unexpected errors so they still reach Sentry', () {
      expect(
        shouldReportAuthFailure(StateError('Bad state: No element')),
        isTrue,
      );
    });
  });
}
