import 'dart:async';

import 'package:firebase_admin_interop/firebase_admin_interop.dart'
    hide EventType;
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import '../utils/infra/firestore_event_function.dart';
import '../utils/infra/on_firestore_helper.dart';
import 'live_meetings/breakouts/check_hostless_go_to_breakouts.dart';
import '../on_firestore_function.dart';
import 'notifications/event_emails.dart';
import '../utils/infra/firestore_utils.dart';
import 'live_meetings/agora_api.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/community/community.dart';

class OnEvent extends OnFirestoreFunction<Event> {
  EventEmails eventEmails;
  OnEvent({EventEmails? eventEmails})
      : eventEmails = eventEmails ?? EventEmails(),
        super(
          [
            AppFirestoreFunctionData(
              'EventOnUpdate',
              FirestoreEventType.onUpdate,
            ),
            AppFirestoreFunctionData(
              'EventOnCreate',
              FirestoreEventType.onCreate,
            ),
          ],
          (snapshot) {
            return Event.fromJson(
              firestoreUtils.fromFirestoreJson(snapshot.data.toMap()),
            ).copyWith(id: snapshot.documentID);
          },
        );

  @override
  String get documentPath =>
      'community/{communityId}/templates/{templateId}/events/{eventId}';

  @override
  Future<void> onUpdate(
    Change<DocumentSnapshot> changes,
    Event before,
    Event after,
    DateTime updateTime,
    EventContext context,
  ) async {
    print("Staring onupdate for ${before.fullPath}");
    if (before.status == EventStatus.canceled) {
      print('Event was canceled before. Not sending any emails.');
      return;
    }

    final actions = [
      _swallowErrors(
        action: () => _checkHostlessUpdates(before, after, updateTime, context),
        description: 'check hostless update',
      ),
      _swallowErrors(
        action: () => _sendEmailUpdates(before, after, updateTime, context),
        description: 'send email updates',
      ),
    ];

    await Future.wait(actions);
  }

  Future<void> _swallowErrors({
    required Future<void> Function() action,
    required String description,
  }) async {
    try {
      await action();
    } catch (e, stacktrace) {
      print('Error during $description');
      print(e);
      print(stacktrace);
    }
  }

  Future<void> _sendEmailUpdates(
    Event before,
    Event after,
    DateTime updateTime,
    EventContext context,
  ) async {
    EventEmailType? emailType;
    if (before.status != EventStatus.canceled &&
        after.status == EventStatus.canceled) {
      emailType = EventEmailType.canceled;
    } else if (before.scheduledTime != after.scheduledTime) {
      emailType = EventEmailType.updated;
    } else if (!before.isLocked && after.isLocked) {
      // Event was just locked - but only stop recordings if event has ACTUALLY ended
      // This allows admins to lock events (prevent new joins) while keeping recordings active
      
      final now = DateTime.now();
      final hasActuallyEnded = after.hasEnded(now);
      
      if (hasActuallyEnded) {
        // Event has truly ended - stop recordings and send thank you emails
        emailType = EventEmailType.ended;
        
        print('Event locked AND past end time - stopping all recordings for event: ${after.id}');
        try {
          await AgoraUtils().stopAllRecordingsForEvent(
            eventPath: after.fullPath,
            eventId: after.id,
          );
        } catch (e) {
          print('Error stopping recordings for event ${after.id}: $e');
          // Continue with event ending even if recording stop fails
        }
      } else {
        // Event locked but still within duration - keep recordings running
        print('Event locked but still within scheduled duration - keeping recordings active for event: ${after.id}');
        print('Scheduled end: ${after.scheduledEndTime}, Current time: $now');
        // Don't send ended email or stop recordings yet
      }
    }

    if (emailType == null) return;

    final community = await firestoreUtils.getFirestoreObject(
      path: '/community/${after.communityId}',
      constructor: (map) => Community.fromJson(map),
    );

    // Don't send create notifications if they are turned off in the event settings
    if (!(after.eventSettings?.reminderEmails ??
        community.eventSettingsMigration.reminderEmails ??
        true)) {
      return;
    }

    // Send email notification to all participants
    await eventEmails.sendEmailsToUsers(
      eventPath: after.fullPath,
      emailType: emailType,
      sendId: after.id,
    );

    if (emailType == EventEmailType.updated) {
      // Note: Old reminders in the task queue will still
      // fire and should not send emails if it is not within a thirty minute
      // buffer of expected email reminder time. But they are a waste as they
      // do not do anything and are a potential cause for bugs.
      await eventEmails.enqueueReminders(after);
    }
  }

  Future<void> _checkHostlessUpdates(
    Event before,
    Event after,
    DateTime updateTime,
    EventContext context,
  ) async {
    print("Checking hostless updates");
    print(before);
    print(after);
    final eventTypeChanged = before.eventType != after.eventType;
    final now = DateTime.now();
    final waitingRoomFinishedTimeChanged =
        before.timeUntilWaitingRoomFinished(now) !=
            after.timeUntilWaitingRoomFinished(now);
    print('Finished time change: $waitingRoomFinishedTimeChanged');
    if (after.eventType == EventType.hostless &&
        (eventTypeChanged || waitingRoomFinishedTimeChanged)) {
      await CheckHostlessGoToBreakouts().enqueueScheduledCheck(after);
    }
  }

  @override
  Future<void> onCreate(
    DocumentSnapshot documentSnapshot,
    Event parsedData,
    DateTime updateTime,
    EventContext context,
  ) async {
    print('Event (${documentSnapshot.documentID}) has been created');

    final communityId = context.params[FirestoreHelper.kCommunityId];
    if (communityId == null) {
      throw ArgumentError.notNull('communityId');
    }

    await onboardingStepsHelper.updateOnboardingSteps(
      communityId,
      documentSnapshot,
      firestoreHelper,
      OnboardingStep.hostEvent,
    );

    // Schedule reminder emails for the new event
    print('Scheduling reminder emails for new event: ${parsedData.id}');
    await eventEmails.enqueueReminders(parsedData);
  }

  @override
  Future<void> onDelete(
    DocumentSnapshot documentSnapshot,
    Event parsedData,
    DateTime updateTime,
    EventContext context,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> onWrite(
    Change<DocumentSnapshot> changes,
    Event before,
    Event after,
    DateTime updateTime,
    EventContext context,
  ) {
    throw UnimplementedError();
  }
}
