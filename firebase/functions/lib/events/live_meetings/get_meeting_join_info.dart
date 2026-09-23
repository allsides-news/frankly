import 'dart:async';

import 'package:collection/collection.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import '../../utils/infra/firebase_auth_utils.dart';
import 'live_meeting_utils.dart';
import '../../on_call_function.dart';
import '../../utils/infra/firestore_utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/user/public_user_info.dart';
import 'package:data_models/utils/utils.dart';

class GetMeetingJoinInfo extends OnCallMethod<GetMeetingJoinInfoRequest> {
  LiveMeetingUtils liveMeetingUtils;
  GetMeetingJoinInfo({LiveMeetingUtils? liveMeetingUtils})
      : liveMeetingUtils = liveMeetingUtils ?? LiveMeetingUtils(),
        super(
          'GetMeetingJoinInfo',
          (jsonMap) => GetMeetingJoinInfoRequest.fromJson(jsonMap),
        );

  @override
  Future<Map<String, dynamic>> action(
    GetMeetingJoinInfoRequest request,
    CallableContext context,
  ) async {
    // [capturedEvent] is set inside the transaction callback so that recording
    // setup — which involves Agora HTTP calls — can run *after* the transaction
    // commits. Keeping Agora calls outside the transaction prevents:
    //   • Long transaction durations that increase Firestore contention.
    //   • Duplicate Agora calls on each Firestore retry (up to 5×).
    //   • Uncaught Firestore abort errors surfacing as [firebase_functions/internal].
    Event? capturedEvent;

    final txResult = await firestore.runTransaction((transaction) async {
      final event = await firestoreUtils.getFirestoreObject(
        transaction: transaction,
        path: request.eventPath,
        constructor: (map) => Event.fromJson(map),
      );
      capturedEvent = event;

      final participant = await firestoreUtils.getFirestoreObject(
        transaction: transaction,
        path: '${request.eventPath}/event-participants/${context.authUid}',
        constructor: (map) => Participant.fromJson(map),
      );

      if (participant.status != ParticipantStatus.active) {
        throw HttpsError(HttpsError.failedPrecondition, 'unauthorized', null);
      }

      // Decide on user's display name
      final userSnapshot =
          await firestore.document('publicUser/${context.authUid}').get();
      final userMap = userSnapshot.exists
          ? firestoreUtils.fromFirestoreJson(userSnapshot.data.toMap())
          : <String, dynamic>{};
      final publicUserInfo = PublicUserInfo.fromJson(userMap);
      var displayName = publicUserInfo.displayName;
      print('Public user display name: $displayName');

      if (displayName == null || displayName.trim().isEmpty) {
        final userLookup = await firebaseAuthUtils.getUsers([context.authUid!]);
        displayName =
            firstAndLastInitial(userLookup.firstOrNull?.displayName) ??
                'User-${context.authUid!.substring(0, 4)}';
        print('Public user display name: $displayName');
      }

      return liveMeetingUtils.getMeetingJoinInfo(
        transaction: transaction,
        event: event,
        communityId: event.communityId,
        liveMeetingCollectionPath: '${request.eventPath}/live-meetings',
        meetingId: event.id,
        userId: context.authUid!,
      );
    });

    // Post-transaction: recording and STT setup (Agora API calls, state writes).
    // Runs after the Firestore transaction commits so that:
    //   • Transaction duration stays short → less contention.
    //   • Agora calls are not duplicated on Firestore retries.
    // The two operations are independent — run in parallel to halve post-transaction
    // latency when both are enabled. Failures are best-effort; the user already has
    // their Agora token. Mirrors the parallel stop pattern in on_event.dart.
    final event = capturedEvent;
    await Future.wait([
      // Backfill the agoraId field on the joiner's publicUser doc (older docs
      // lack it) so other participants' GetUserIdFromAgoraId lookups succeed.
      // Runs before the token is returned — the joiner can't connect to Agora
      // (and thus be looked up) until this completes. Best-effort internally.
      liveMeetingUtils.ensurePublicUserAgoraId(userId: context.authUid!),
      if (txResult.shouldRecord && event != null)
        Future(() async {
          try {
            await liveMeetingUtils.handleMainRoomRecordingOnJoin(
              liveMeetingCollectionPath: txResult.liveMeetingCollectionPath,
              meetingId: txResult.joinInfo.meetingId,
              userId: context.authUid!,
              event: event,
              screenSharerUserId: txResult.screenSharerUserId,
              screenShareAgoraUid: txResult.screenShareAgoraUid,
            );
          } catch (e) {
            print(
              'Warning: handleMainRoomRecordingOnJoin failed for '
              '${txResult.joinInfo.meetingId}: $e',
            );
          }
        }),
      if (txResult.shouldTranscribe && event != null)
        Future(() async {
          try {
            await liveMeetingUtils.handleMainRoomTranscriptionOnJoin(
              liveMeetingCollectionPath: txResult.liveMeetingCollectionPath,
              meetingId: txResult.joinInfo.meetingId,
              userId: context.authUid!,
              event: event,
            );
          } catch (e) {
            print(
              'Warning: handleMainRoomTranscriptionOnJoin failed for '
              '${txResult.joinInfo.meetingId}: $e',
            );
          }
        }),
    ]);

    return txResult.joinInfo.toJson();
  }
}
