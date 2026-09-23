import 'dart:async';

import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import '../on_call_function.dart';
import '../utils/infra/firestore_utils.dart';
import 'notifications/event_emails.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/community/membership.dart';

/// Resend registration emails for users who didn't receive them
class ResendEventEmails extends OnCallMethod<ResendEventEmailsRequest> {
  EventEmails eventEmailUtils;
  ResendEventEmails({EventEmails? eventEmailUtils})
      : eventEmailUtils = eventEmailUtils ?? EventEmails(),
        super(
          'resendEventEmails',
          (jsonMap) => ResendEventEmailsRequest.fromJson(jsonMap),
        );

  Future<void> _verifyCallerIsAuthorized(
    Event event,
    CallableContext context,
  ) async {
    final communityMembershipDoc = await firestore
        .document(
          'memberships/${context.authUid}/community-membership/${event.communityId}',
        )
        .get();

    final membership = Membership.fromJson(
      firestoreUtils.fromFirestoreJson(communityMembershipDoc.data.toMap()),
    );

    final isAuthorized =
        event.creatorId == context.authUid || membership.isMod;
    if (!isAuthorized) {
      throw HttpsError(HttpsError.failedPrecondition, 'unauthorized', null);
    }
  }

  @override
  Future<void> action(
    ResendEventEmailsRequest request,
    CallableContext context,
  ) async {
    final event = await firestoreUtils.getFirestoreObject(
      path: request.eventPath,
      constructor: (map) => Event.fromJson(map),
    );

    await _verifyCallerIsAuthorized(event, context);

    print('Resending registration emails for event: ${request.eventId}');
    print('  userIds: ${request.userIds}');

    await eventEmailUtils.sendEmailsToUsers(
      eventPath: request.eventPath,
      userIds: request.userIds,
      emailType: EventEmailType.initialSignUp,
    );

    print('Successfully queued ${request.userIds.length} registration emails');
  }
}
