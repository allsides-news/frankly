import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'assign_to_breakouts.dart';
import '../../../on_call_function.dart';
import 'check_assign_to_breakouts_server.dart';
import '../../../utils/infra/firestore_utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/utils/utils.dart';
import 'package:meta/meta.dart';

class InitiateBreakouts extends OnCallMethod<InitiateBreakoutsRequest> {
  @visibleForTesting
  static math.Random random = math.Random();

  InitiateBreakouts()
      : super(
          InitiateBreakoutsRequest.functionName,
          (json) => InitiateBreakoutsRequest.fromJson(json),
          runWithOptions: RuntimeOptions(
            timeoutSeconds: 120,
            memory: '4GB',
            minInstances: 0,
          ),
        );

  @override
  Future<void> action(
    InitiateBreakoutsRequest request,
    CallableContext context,
  ) async {
    try {
      final event = await firestoreUtils.getFirestoreObject(
        path: request.eventPath,
        constructor: (map) => Event.fromJson(map),
      );

      print('checking is authorized');
      await _verifyCallerIsAuthorized(event, context);

      await initiateBreakouts(
        request: request,
        event: event,
        creatorId: context.authUid!,
      );
    } catch (e, stackTrace) {
      print('Error in InitiateBreakouts.action: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

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

    final isAuthorized = event.creatorId == context.authUid || membership.isMod;
    if (!isAuthorized) {
      throw HttpsError(HttpsError.failedPrecondition, 'unauthorized', null);
    }
  }

  Future<void> initiateBreakouts({
    required InitiateBreakoutsRequest request,
    required Event event,
    required String creatorId,
  }) async {
    print('InitiateBreakouts called for event ${event.id}, session ${request.breakoutSessionId}, creator: $creatorId');
    
    try {
      if (event.isHosted) {
        print('Event ${event.id} is hosted - assigning users to breakouts immediately.');
        await AssignToBreakouts().assignToBreakouts(
          targetParticipantsPerRoom: request.targetParticipantsPerRoom,
          breakoutSessionId: request.breakoutSessionId,
          assignmentMethod:
              request.assignmentMethod ?? BreakoutAssignmentMethod.targetPerRoom,
          includeWaitingRoom: request.includeWaitingRoom,
          event: event,
          creatorId: creatorId,
        );
      } else {
        print('Event ${event.id} is hostless - pinging breakout availability.');
        await _pingBreakoutsAvailability(
          event: event,
          request: request,
        );
      }
      print('InitiateBreakouts completed successfully for event ${event.id}');
    } catch (e, stackTrace) {
      print('Error in initiateBreakouts for event ${event.id}: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _pingBreakoutsAvailability({
    required Event event,
    required InitiateBreakoutsRequest request,
  }) async {
    final breakoutRoomSessionId = request.breakoutSessionId;
    final liveMeetingPath = '${event.fullPath}/live-meetings/${event.id}';

    print('Pinging breakout availability for session: $breakoutRoomSessionId');

    // Wait time before triggering smart matching. This buffer allows participants
    // to fully load, see the breakout dialog, and mark themselves as available.
    // The smart matching algorithm itself is fast (< 5s even for 10k+ participants),
    // so this delay is for participant collection and user interaction time.
    // 
    // For hostless events, participants must:
    // 1. Receive the pending breakout status update (network latency)
    // 2. See the dialog asking to join breakouts
    // 3. Click to confirm and mark themselves available
    // 4. Firestore write must complete
    //
    // 30 seconds provides adequate time for this entire flow to complete reliably,
    // even with network latency and multiple concurrent participants.
    // Late arrivals can still be reassigned if needed.
    const smartMatchingWaitTime = Duration(seconds: 30);

    final now = DateTime.now();
    final nowWithoutMilliseconds =
        now.subtract(Duration(milliseconds: now.millisecond));
    final scheduledTime = nowWithoutMilliseconds.add(smartMatchingWaitTime);

    print('Will schedule smart matching for: $scheduledTime (in ${smartMatchingWaitTime.inSeconds} seconds)');

    bool newlyInitiated = false;
    try {
      newlyInitiated = await firestore.runTransaction((transaction) async {
        print('Running transaction to create pending breakout session');
        final liveMeetingDocRef = firestore.document(liveMeetingPath);
        final liveMeetingDoc = await transaction.get(liveMeetingDocRef);
        
        LiveMeeting? liveMeeting;
        if (!liveMeetingDoc.exists) {
          print('Live meeting document does not exist at $liveMeetingPath - will be created');
          liveMeeting = null; // Will create new document
        } else {
          liveMeeting = LiveMeeting.fromJson(
            firestoreUtils.fromFirestoreJson(liveMeetingDoc.data.toMap()),
          );
        }
        
        final currentSessionId = liveMeeting?.currentBreakoutSession?.breakoutRoomSessionId;
        final currentStatus = liveMeeting?.currentBreakoutSession?.breakoutRoomStatus;
        
        print('Current breakout state: sessionId=$currentSessionId, status=$currentStatus');
        
        if (currentSessionId == breakoutRoomSessionId) {
          print('Breakout session $breakoutRoomSessionId already initiated. Returning.');
          return false;
        }
        
        // Also check if there's already an active or pending session
        if (currentStatus == BreakoutRoomStatus.active || 
            currentStatus == BreakoutRoomStatus.pending) {
          print('Breakout session already in progress with status $currentStatus. Returning.');
          return false;
        }
        
        final breakoutSession = BreakoutRoomSession(
          breakoutRoomSessionId: breakoutRoomSessionId,
          breakoutRoomStatus: BreakoutRoomStatus.pending,
          assignmentMethod: request.assignmentMethod ?? BreakoutAssignmentMethod.targetPerRoom,
          targetParticipantsPerRoom: request.targetParticipantsPerRoom,
          hasWaitingRoom: request.includeWaitingRoom,
          scheduledTime: scheduledTime,
        );
        
        print('Creating pending breakout session in transaction');
        transaction.set(
          liveMeetingDocRef,
          DocumentData.fromMap(
            jsonSubset(
              [LiveMeeting.kFieldCurrentBreakoutSession],
              firestoreUtils.toFirestoreJson(
                LiveMeeting(
                  currentBreakoutSession: breakoutSession,
                ).toJson(),
              ),
            ),
          ),
          merge: true,
        );
        return true;
      });
    } catch (e, stackTrace) {
      print('Error in transaction for event ${event.id}: $e');
      print('Stack trace: $stackTrace');
      // Don't rethrow - this might be a transient transaction failure
      // The scheduled check will handle it
      return;
    }

    if (newlyInitiated) {
      print('Scheduling CheckAssignToBreakoutsServer for event ${event.id} at $scheduledTime');
      try {
        await CheckAssignToBreakoutsServer().schedule(
          CheckAssignToBreakoutsRequest(
            eventPath: event.fullPath,
            breakoutSessionId: breakoutRoomSessionId,
          ),
          scheduledTime,
        );
        print('Successfully scheduled CheckAssignToBreakoutsServer');
      } catch (e, stackTrace) {
        print('Error scheduling CheckAssignToBreakoutsServer: $e');
        print('Stack trace: $stackTrace');
        rethrow;
      }
    } else {
      print('Not enqueuing CheckAssignToBreakoutsServer - session already setup or another process is handling it.');
    }
  }
}
