import 'dart:async';

import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    hide CloudFunction;
import '../cloud_function.dart';
import '../utils/infra/firestore_utils.dart';
import 'package:data_models/events/event.dart';

/// Scheduled function that runs periodically to check for events that should auto-end.
///
/// This function:
/// 1. Queries all active, unlocked events
/// 2. Checks if each event has passed its scheduled end time (scheduledTime + durationInMinutes)
/// 3. Locks events that have ended to prevent new participants from joining
///
/// This function should be scheduled to run every minute via Cloud Scheduler.
class AutoEndEvents implements CloudFunction {
  @override
  final String functionName = 'AutoEndEvents';

  FutureOr<void> action(EventContext context) async {
    print('AutoEndEvents: Starting check for events that should auto-end...');

    try {
      final now = DateTime.now();

      // Query all active events that are not locked
      final eventsSnapshot = await firestore
          .collectionGroup('events')
          .where(Event.kFieldStatus, isEqualTo: EventStatus.active.name)
          .where(Event.kFieldIsLocked, isEqualTo: false)
          .get();

      print(
        'AutoEndEvents: Found ${eventsSnapshot.documents.length} active, unlocked events to check',
      );

      int endedCount = 0;
      int skippedCount = 0;

      for (final eventDoc in eventsSnapshot.documents) {
        try {
          final event = Event.fromJson(
            firestoreUtils.fromFirestoreJson(eventDoc.data.toMap()),
          );

          // Check if event should end
          if (event.hasEnded(now)) {
            print(
                'AutoEndEvents: Auto-ending event ${event.id} - "${event.title}" '
                '(scheduled: ${event.scheduledTime}, duration: ${event.durationInMinutes} min)');

            // Lock the event to prevent new entries
            await eventDoc.reference.updateData(
              UpdateData.fromMap({
                Event.kFieldIsLocked: true,
              }),
            );

            endedCount++;
          } else {
            skippedCount++;
          }
        } catch (e, stackTrace) {
          print(
              'AutoEndEvents: Error processing event ${eventDoc.reference.documentID}: $e');
          print(stackTrace);
          // Continue processing other events even if one fails
        }
      }

      print(
        'AutoEndEvents: Completed. Auto-ended $endedCount events, skipped $skippedCount events still active',
      );
    } catch (e, stackTrace) {
      print('AutoEndEvents: Critical error during execution: $e');
      print(stackTrace);
      rethrow;
    }
  }

  @override
  void register(FirebaseFunctions functions) {
    functions[functionName] = functions
        .runWith(
          RuntimeOptions(
            timeoutSeconds: 60,
            memory: '256MB',
          ),
        )
        .pubsub
        .schedule('every 1 minutes')
        .onRun((_, context) => action(context));
  }
}
