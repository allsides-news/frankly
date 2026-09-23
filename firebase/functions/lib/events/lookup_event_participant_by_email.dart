import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'package:functions/on_call_function.dart';
import 'package:functions/utils/infra/firebase_auth_utils.dart';
import 'package:functions/utils/infra/firestore_utils.dart';
import 'package:functions/utils/utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/community/membership.dart';

class LookupEventParticipantByEmail
    extends OnCallMethod<LookupEventParticipantByEmailRequest> {
  LookupEventParticipantByEmail()
      : super(
          'LookupEventParticipantByEmail',
          (json) => LookupEventParticipantByEmailRequest.fromJson(json),
        );

  @override
  Future<Map<String, dynamic>> action(
    LookupEventParticipantByEmailRequest request,
    CallableContext context,
  ) async {
    final eventPath = request.eventPath;

    final eventDoc = await firestore.document(eventPath).get();
    final event = Event.fromJson(
      firestoreUtils.fromFirestoreJson(eventDoc.data.toMap()),
    );

    final communityMembershipDoc = await firestore
        .document(
          'memberships/${context.authUid}/community-membership/${event.communityId}',
        )
        .get();
    
    if (!communityMembershipDoc.exists) {
      if (event.creatorId != context.authUid) {
        throw HttpsError(HttpsError.failedPrecondition, 'unauthorized', null);
      }
    } else {
      final membership = Membership.fromJson(
        firestoreUtils.fromFirestoreJson(communityMembershipDoc.data.toMap()),
      );

      if (event.creatorId != context.authUid && !membership.isFacilitator) {
        throw HttpsError(HttpsError.failedPrecondition, 'unauthorized', null);
      }
    }

    final userRecord =
        await firebaseAuthUtils.getUserByEmail(request.email.trim());
    if (userRecord == null) {
      return LookupEventParticipantByEmailResponse(
        isRegistered: false,
      ).toJson();
    }

    final userId = userRecord.uid;
    final participantDoc = await firestore
        .document('$eventPath/event-participants/$userId')
        .get();

    if (!participantDoc.exists) {
      return LookupEventParticipantByEmailResponse(
        isRegistered: false,
        userId: userId,
      ).toJson();
    }

    final participant = Participant.fromJson(
      firestoreUtils.fromFirestoreJson(participantDoc.data.toMap()),
    );

    String? displayName;
    try {
      if (isNullOrEmpty(userRecord.displayName)) {
        final publicUserDoc =
            await firestore.document('publicUser/$userId').get();
        displayName = publicUserDoc.data.toMap()['displayName'] as String?;
      } else {
        displayName = userRecord.displayName;
      }
    } catch (e) {
      print('Error getting display name for $userId: $e');
    }

    String? currentRoomName;
    final currentBreakoutRoomId = participant.currentBreakoutRoomId;

    if (participant.isPresent && currentBreakoutRoomId != null) {
      if (currentBreakoutRoomId == breakoutsWaitingRoomId) {
        currentRoomName = 'Waiting Room';
      } else {
        try {
          final liveMeetingDoc = await firestore
              .document('$eventPath/live-meetings/${event.id}')
              .get();
          final liveMeeting = LiveMeeting.fromJson(
            firestoreUtils.fromFirestoreJson(liveMeetingDoc.data.toMap()),
          );
          final sessionId =
              liveMeeting.currentBreakoutSession?.breakoutRoomSessionId;
          if (sessionId != null) {
            final roomDoc = await firestore
                .document(
                  '$eventPath/live-meetings/${event.id}/breakout-room-sessions/$sessionId/breakout-rooms/$currentBreakoutRoomId',
                )
                .get();
            if (roomDoc.exists) {
              final room = BreakoutRoom.fromJson(
                firestoreUtils.fromFirestoreJson(roomDoc.data.toMap()),
              );
              currentRoomName = room.roomName;
            }
          }
        } catch (e) {
          print('Error getting breakout room name for $currentBreakoutRoomId: $e');
        }
      }
    }

    return LookupEventParticipantByEmailResponse(
      isRegistered: true,
      isPresent: participant.isPresent,
      currentRoomName: currentRoomName,
      userId: userId,
      displayName: displayName,
    ).toJson();
  }
}
