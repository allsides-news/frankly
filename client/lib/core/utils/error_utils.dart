import 'package:client/core/data/services/logging_service.dart';
import 'package:client/core/utils/navigation_utils.dart';
import 'package:client/core/utils/visible_exception.dart';
import 'package:client/core/widgets/height_constained_text.dart';
import 'package:client/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:client/core/data/providers/dialog_provider.dart';

import 'dart:async';

String sanitizeError(String error) {
  error = error
      .replaceAll('FirebaseError: ', '')
      .replaceAll(RegExp(r'\(.*\)'), '')
      .replaceAll(RegExp(r'\[.*\]'), '')
      .trim();

  if (error.contains('An account already exists with the same email address')) {
    return appLocalizationService.getLocalization().accountExistsWithSameEmail;
  }
  if (error.contains('The password is invalid')) {
    return appLocalizationService.getLocalization().passwordInvalid;
  }
  if (error.contains('There is no user record')) {
    return appLocalizationService.getLocalization().noAccountFound;
  }
  if (error
      .contains('The email address is already in use by another account')) {
    return appLocalizationService.getLocalization().emailAddressAlreadyInUse;
  }
  if (error.contains('Missing or insufficient permission')) {
    return appLocalizationService.getLocalization().notAuthorized;
  }
  if (error.trim().toLowerCase() == 'INTERNAL'.toLowerCase()) {
    return appLocalizationService.getLocalization().somethingWentWrong;
  }

  return error;
}

Future<void> showAlert(BuildContext context, String alert) =>
    showCustomDialog<void>(
      context: context,
      builder: (innerContext) => AlertDialog(
        content: SingleChildScrollView(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: HeightConstrainedText(
                    alert,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
                onPressed: () => Navigator.of(innerContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );

Future<T?> alertOnError<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? errorMessage,
}) async {
  try {
    return await action();
  } catch (e, s) {
    loggingService.log(e, logType: LogType.error);
    loggingService.log(s, logType: LogType.error);

    final sanitizedError = sanitizeError(e.toString());

    // The action can outlive the widget that triggered it (e.g. the page
    // rebuilds while an awaited dialog is open). Fall back to the root
    // navigator context so showing the alert never throws on a deactivated
    // element, which would swallow the alert and kill the calling flow.
    final alertContext = context.mounted ? context : navigatorState.context;
    await showAlert(alertContext, errorMessage ?? sanitizedError);
    return null;
  }
}

// Return callback w/ both the sanitized error and either firebase error code or exception msg when action fails
Future<void> authMessageOnError<T>(
  Future<T> Function() action, {
  required Function(String errorMessage, String code) errorCallback,
  Function()? callback,
}) async {
  try {
    await action();
    if (callback != null) {
      callback();
    }
  } catch (e, s) {
    loggingService.log(e, logType: LogType.error);
    loggingService.log(s, logType: LogType.error);

    final sanitizedError = sanitizeError(e.toString());

    if (e is FirebaseAuthException) {
      errorCallback(sanitizedError, e.code);
    } else if (e is VisibleException) {
      errorCallback(sanitizedError, e.msg);
    }
  }
}

// Note: Consider not swallowing all errors. Only a subset of error types.
Future<T?> swallowErrors<T>(
  FutureOr<T> Function() action, {
  String? errorMessage,
}) async {
  try {
    return await action();
  } catch (e, stackTrace) {
    loggingService.log('Error swallowed in tryCatch utility.');
    if (errorMessage != null) {
      loggingService.log(errorMessage);
    }
    loggingService.log(stackTrace);
    loggingService.log(e, logType: LogType.error, stackTrace: stackTrace);
  }
  return null;
}

T? swallowErrorsSync<T>(T Function() action) {
  try {
    return action();
  } catch (e, stackTrace) {
    loggingService.log('Error swallowed in tryCatchSync utility.');
    loggingService.log(e, logType: LogType.error, stackTrace: stackTrace);
  }
  return null;
}

bool isNullOrEmpty(String? value) => (value?.trim() ?? '').isEmpty;

/// Transient Firebase Auth network failures (timeout, offline, unreachable host).
/// These are expected on flaky mobile networks and should not crash the app
/// or be reported as Sentry errors.
bool isTransientAuthNetworkError(Object? error) {
  if (error == null) return false;
  if (error is FirebaseAuthException) {
    return error.code == 'network-request-failed' ||
        error.code == 'timeout' ||
        error.code == 'network-error';
  }
  final text = error.toString().toLowerCase();
  return text.contains('network-request-failed') ||
      text.contains('network autherror') ||
      text.contains('network-error');
}

/// Firestore security-rule denials surface as [FirebaseException] with this
/// code, or as a string that contains the same token / "insufficient permission".
bool isPermissionDeniedError(Object? error) {
  if (error == null) return false;
  if (error is FirebaseException && error.code == 'permission-denied') {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('permission-denied') ||
      text.contains('permission_denied') ||
      text.contains('missing or insufficient permission');
}

/// One-shot Firestore `.get()` fails with this when the web client has no
/// network / persistence cache. Snapshots wait; `.get()` throws.
bool isFirestoreUnavailableError(Object? error) {
  if (error == null) return false;
  if (error is FirebaseException && error.code == 'unavailable') {
    return true;
  }
  final text = error.toString().toLowerCase();
  return text.contains('cloud_firestore/unavailable') ||
      text.contains('client is offline');
}

/// Strings [AudioVideoErrorDisplay] already maps. Used when iris-web fails
/// capture without throwing a DOMException.
const kGumNotAllowedError = 'NotAllowedError: Permission denied';
const kGumNotReadableError = 'NotReadableError: Could not start video source';
const kGumNotFoundError = 'NotFoundError: Requested device not found';

/// Browser getUserMedia failures: camera/mic in use, missing, or blocked.
/// These are device/OS conditions, not application bugs.
bool isGetUserMediaError(Object? error) {
  if (error == null) return false;
  final text = error.toString();
  return text.contains('NotReadableError') ||
      text.contains('NotAllowedError') ||
      text.contains('NotFoundError') ||
      text.contains('OverconstrainedError') ||
      text.contains('AbortError') ||
      text.contains('Could not start video source') ||
      text.contains('Could not start audio source');
}

/// Cloud Function `HttpsError.notFound` (web: `[firebase_functions/not-found]`).
bool isCloudFunctionsNotFoundError(Object? error) {
  if (error == null) return false;
  final text = error.toString().toLowerCase();
  return text.contains('firebase_functions/not-found') ||
      text.contains('cloud_functions/not-found');
}

/// Firestore security-rule denials are expected (private event before RSVP,
/// signed-out users, etc.). Snapshot `unavailable` is a transient offline
/// blip. Log those at debug. Exhausted one-shot `.get()` retries are logged
/// at error by CustomStreamBuilder, not this helper.
void logStreamErrorUnlessPermissionDenied(
  String label,
  Object error,
  StackTrace stackTrace,
) {
  if (isPermissionDeniedError(error)) {
    loggingService.log(
      '$label permission denied',
      logType: LogType.debug,
      error: error,
    );
    return;
  }
  if (isFirestoreUnavailableError(error)) {
    loggingService.log(
      '$label firestore unavailable',
      logType: LogType.debug,
      error: error,
    );
    return;
  }
  loggingService.log(
    label,
    logType: LogType.error,
    error: error,
    stackTrace: stackTrace,
  );
}

/// [Stream.first] throws [StateError] ("Bad state: No element") when the
/// stream completes without emitting. That happens when a provider is disposed
/// while a page is still awaiting the first Firestore snapshot.
Future<T?> firstEmittedOrNull<T>(Stream<T> stream) async {
  try {
    return await stream.first;
  } on StateError {
    return null;
  }
}
