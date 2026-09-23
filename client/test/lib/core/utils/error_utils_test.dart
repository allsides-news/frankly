import 'package:client/core/utils/error_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isPermissionDeniedError', () {
    test('is true for Firestore permission-denied strings', () {
      expect(
        isPermissionDeniedError(
          '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
        ),
        isTrue,
      );
      expect(
        isPermissionDeniedError('Missing or insufficient permission'),
        isTrue,
      );
    });

    test('is false for unrelated errors', () {
      expect(isPermissionDeniedError(null), isFalse);
      expect(
        isPermissionDeniedError(StateError('Bad state: No element')),
        isFalse,
      );
    });
  });

  group('isFirestoreUnavailableError', () {
    test('is true for offline get() strings', () {
      expect(
        isFirestoreUnavailableError(
          '[cloud_firestore/unavailable] Failed to get document because the client is offline.',
        ),
        isTrue,
      );
    });

    test('is false for unrelated errors', () {
      expect(isFirestoreUnavailableError(null), isFalse);
      expect(
        isFirestoreUnavailableError(StateError('Bad state: No element')),
        isFalse,
      );
      expect(
        isFirestoreUnavailableError(
          '[cloud_firestore/permission-denied] Missing or insufficient permissions.',
        ),
        isFalse,
      );
    });
  });

  group('isGetUserMediaError', () {
    test('is true for browser camera/mic refusals', () {
      expect(
        isGetUserMediaError('NotReadableError: Could not start video source'),
        isTrue,
      );
      expect(isGetUserMediaError('NotAllowedError: Permission denied'), isTrue);
      expect(isGetUserMediaError('NotFoundError: Requested device not found'), isTrue);
      expect(isGetUserMediaError(kGumNotAllowedError), isTrue);
      expect(isGetUserMediaError(kGumNotReadableError), isTrue);
    });

    test('is false for unrelated errors', () {
      expect(isGetUserMediaError(null), isFalse);
      expect(
        isGetUserMediaError(StateError('Bad state: No element')),
        isFalse,
      );
    });
  });

  group('isCloudFunctionsNotFoundError', () {
    test('is true for GetUserIdFromAgoraId not-found strings', () {
      expect(
        isCloudFunctionsNotFoundError(
          '[firebase_functions/not-found] User with agora ID 678 not found',
        ),
        isTrue,
      );
    });

    test('is false for unrelated errors', () {
      expect(isCloudFunctionsNotFoundError(null), isFalse);
      expect(
        isCloudFunctionsNotFoundError(
          '[cloud_firestore/unavailable] client is offline',
        ),
        isFalse,
      );
    });
  });

  group('isTransientAuthNetworkError', () {
    test('is true for firebase_auth network-request-failed strings', () {
      expect(
        isTransientAuthNetworkError(
          '[firebase_auth/network-request-failed] A network AuthError (such as timeout, interrupted connection or unreachable host) has occurred.',
        ),
        isTrue,
      );
    });

    test('is false for unrelated errors', () {
      expect(isTransientAuthNetworkError(null), isFalse);
      expect(
        isTransientAuthNetworkError(StateError('Bad state: No element')),
        isFalse,
      );
    });
  });

  group('firstEmittedOrNull', () {
    test('returns the first value', () async {
      expect(await firstEmittedOrNull(Stream.value(7)), 7);
    });

    test('returns null when the stream completes with no element', () async {
      expect(await firstEmittedOrNull(Stream<int>.empty()), isNull);
    });
  });
}
