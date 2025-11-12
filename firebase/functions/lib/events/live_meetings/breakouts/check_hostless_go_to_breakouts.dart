import 'dart:async';

import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'initiate_breakouts.dart';
import '../../../on_call_function.dart';
import 'check_hostless_go_to_breakouts_server.dart';
import '../../../utils/infra/firestore_utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';

class CheckHostlessGoToBreakouts
    extends OnCallMethod<CheckHostlessGoToBreakoutsRequest> {
  CheckHostlessGoToBreakouts()
      : super(
          CheckHostlessGoToBreakoutsRequest.functionName,
          (jsonMap) => CheckHostlessGoToBreakoutsRequest.fromJson(jsonMap),
          runWithOptions: RuntimeOptions(
            timeoutSeconds: 240,
            memory: '4GB',
            minInstances: 0,
          ),
        );

  @override
  Future<void> action(
    CheckHostlessGoToBreakoutsRequest request,
    CallableContext context,
  ) async {
    try {
      await checkHostlessGoToBreakouts(request, context.authUid!);
    } catch (e, stackTrace) {
      print('Error in CheckHostlessGoToBreakouts: $e');
      print('Stack trace: $stackTrace');
      // Rethrow to let the client know there was an error
      rethrow;
    }
  }

  Future<void> checkHostlessGoToBreakouts(
    CheckHostlessGoToBreakoutsRequest request,
    String userId,
  ) async {
    print('CheckHostlessGoToBreakouts called for event: ${request.eventPath}, userId: $userId');
    
    final event = await firestoreUtils.getFirestoreObject(
      path: request.eventPath,
      constructor: (map) => Event.fromJson(map),
    );
    print('Retrieved event: ${event.id}, type: ${event.eventType}, status: ${event.status}');

    if (event.eventType != EventType.hostless) {
      print('Event is not hostless, returning.');
      return;
    }

    if (event.status != EventStatus.active) {
      print('Event is cancelled, returning.');
      return;
    }

    final nowWithBuffer = DateTime.now().add(const Duration(milliseconds: 100));

    final timeUntilWaitingRoomFinished =
        event.timeUntilWaitingRoomFinished(nowWithBuffer);

    print(
        'comparing now ($nowWithBuffer) to scheduled start time (${event.scheduledTime}). '
        'Waiting room finished in $timeUntilWaitingRoomFinished');
    if (!timeUntilWaitingRoomFinished.isNegative) {
      print('It is still before scheduled start time so returning.');
      return;
    }

    final liveMeetingPath = '${event.fullPath}/live-meetings/${event.id}';
    final liveMeeting = await firestoreUtils.getFirestoreObject(
      path: liveMeetingPath,
      constructor: (map) => LiveMeeting.fromJson(map),
    );

    final currentBreakoutStatus = liveMeeting.currentBreakoutSession?.breakoutRoomStatus;
    print('Current breakout status: $currentBreakoutStatus');
    
    if ([BreakoutRoomStatus.active, BreakoutRoomStatus.pending]
        .contains(currentBreakoutStatus)) {
      print('Breakouts have already been assigned or are being assigned, returning.');
      return;
    }
    const defaultTargetParticipants = 8;

    print('Initializing breakouts for ${event.id}');
    try {
      await InitiateBreakouts().initiateBreakouts(
        event: event,
        request: InitiateBreakoutsRequest(
          eventPath: event.fullPath,
          // Use the event ID so that any duplicate checks will use the same breakout session ID.
          breakoutSessionId: event.id,
          assignmentMethod: event.breakoutRoomDefinition?.assignmentMethod ??
              BreakoutAssignmentMethod.targetPerRoom,
          targetParticipantsPerRoom:
              event.breakoutRoomDefinition?.targetParticipants ??
                  defaultTargetParticipants,
          includeWaitingRoom: true,
        ),
        creatorId: userId,
      );
      print('Successfully finished initiating breakouts for ${event.id}');
    } catch (e, stackTrace) {
      print('Error initiating breakouts for ${event.id}: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> enqueueScheduledCheck(Event event) async {
    final timeToGoToBreakouts =
        DateTime.now().add(event.timeUntilWaitingRoomFinished(DateTime.now()));

    await CheckHostlessGoToBreakoutsServer().schedule(
      CheckHostlessGoToBreakoutsRequest(eventPath: event.fullPath),
      timeToGoToBreakouts,
    );
  }
}
