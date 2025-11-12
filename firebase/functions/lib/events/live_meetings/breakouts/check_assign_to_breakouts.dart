import 'dart:async';

import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'assign_to_breakouts.dart';
import '../../../on_call_function.dart';
import '../../../utils/infra/firestore_utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';

class CheckAssignToBreakouts
    extends OnCallMethod<CheckAssignToBreakoutsRequest> {
  static const _clockSkewBuffer = Duration(milliseconds: 100);

  CheckAssignToBreakouts()
      : super(
          CheckAssignToBreakoutsRequest.functionName,
          (jsonMap) => CheckAssignToBreakoutsRequest.fromJson(jsonMap),
          runWithOptions: RuntimeOptions(
            timeoutSeconds: 240,
            memory: '4GB',
            minInstances: 0,
          ),
        );

  @override
  Future<void> action(
    CheckAssignToBreakoutsRequest request,
    CallableContext context,
  ) async {
    try {
      await checkAssignToBreakouts(request, context.authUid!);
    } catch (e, stackTrace) {
      print('Error in CheckAssignToBreakouts.action: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> checkAssignToBreakouts(
    CheckAssignToBreakoutsRequest request,
    String userId,
  ) async {
    print('CheckAssignToBreakouts called for event: ${request.eventPath}, breakoutSessionId: ${request.breakoutSessionId}, userId: $userId');
    
    try {
      final event = await firestoreUtils.getFirestoreObject(
        path: request.eventPath,
        constructor: (map) => Event.fromJson(map),
      );
      print('Retrieved event: ${event.id}, type: ${event.eventType}, status: ${event.status}');

      if (event.status != EventStatus.active) {
        print('Event is cancelled, returning.');
        return;
      }

      final liveMeetingPath = '${event.fullPath}/live-meetings/${event.id}';
      final liveMeeting = await firestoreUtils.getFirestoreObject(
        path: liveMeetingPath,
        constructor: (map) => LiveMeeting.fromJson(map),
      );

      final breakoutSession = liveMeeting.currentBreakoutSession;

      if (breakoutSession == null) {
        print('Breakout session not found in live meeting.');
        return;
      }

      // Check if it is currently after the expected amount of time of the waiting room
      final scheduledStartTime =
          breakoutSession.scheduledTime?.subtract(_clockSkewBuffer);
      if (scheduledStartTime == null) {
        print('Scheduled start time is null.');
        return;
      }

      final now = DateTime.now();
      print(
        'Comparing now ($now) and scheduled start time ($scheduledStartTime) with buffer',
      );
      if (now.isBefore(scheduledStartTime)) {
        print(
          'It is currently ($now) still before scheduled start time ($scheduledStartTime) so returning.',
        );
        return;
      }

      if (breakoutSession.breakoutRoomSessionId != request.breakoutSessionId) {
        print(
            'Current breakout session (${breakoutSession.breakoutRoomSessionId})'
            ' does not match requested session ID (${request.breakoutSessionId}).');
        return;
      }

      if (BreakoutRoomStatus.active == breakoutSession.breakoutRoomStatus) {
        print('Breakouts have already been assigned so returning.');
        return;
      }

      print('Starting smart match assignment for event ${event.id}, method: ${breakoutSession.assignmentMethod}');
      await AssignToBreakouts().assignToBreakouts(
        breakoutSessionId: breakoutSession.breakoutRoomSessionId,
        assignmentMethod: breakoutSession.assignmentMethod,
        targetParticipantsPerRoom: breakoutSession.targetParticipantsPerRoom,
        includeWaitingRoom: breakoutSession.hasWaitingRoom,
        event: event,
        creatorId: userId,
      );
      print('Successfully completed smart match assignment for event ${event.id}');
    } catch (e, stackTrace) {
      print('Error in checkAssignToBreakouts for event path ${request.eventPath}: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
