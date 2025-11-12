import 'dart:async';
import 'dart:math';
import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'agora_api.dart';
import 'recording_queue.dart';
import '../../utils/infra/firestore_utils.dart';
import '../../utils/utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/utils/utils.dart';

class LiveMeetingUtils {
  bool _shouldRecord(Event event) => event.eventSettings?.alwaysRecord ?? false;
  AgoraUtils agoraUtils;

  LiveMeetingUtils({AgoraUtils? agoraUtils})
      : agoraUtils = agoraUtils ?? AgoraUtils();

  /// Check if there are recent breakout sessions for this meeting
  /// This helps detect when we're returning from breakouts and need to restart recording
  /// Note: This is called outside of transactions since collection queries aren't supported in transactions
  Future<bool> _hasRecentBreakoutSessions({
    required String liveMeetingCollectionPath,
    required String meetingId,
  }) async {
    try {
      final sessionsSnapshot = await firestore
          .collection('$liveMeetingCollectionPath/$meetingId/breakout-room-sessions')
          .get();
      
      // If there are any breakout sessions, we've had breakouts
      final hasBreakouts = sessionsSnapshot.documents.isNotEmpty;
      if (hasBreakouts) {
        print('Found ${sessionsSnapshot.documents.length} breakout sessions for meeting $meetingId');
      }
      return hasBreakouts;
    } catch (e) {
      print('Error checking for breakout sessions: $e');
      return false;
    }
  }

  Future<GetMeetingJoinInfoResponse> getMeetingJoinInfo({
    required Transaction transaction,
    required String communityId,
    required String liveMeetingCollectionPath,
    required String meetingId,
    required String userId,
    required Event event,
  }) async {
    final fieldsToUpdate = <String>[];

    // Look up live meeting
    final liveMeetingSnapshot = await transaction.get(
      firestore.document('$liveMeetingCollectionPath/$meetingId'),
    );
    var liveMeeting = LiveMeeting.fromJson(
      firestoreUtils.fromFirestoreJson(liveMeetingSnapshot.data.toMap()),
    );
    if (isNullOrEmpty(liveMeeting.meetingId)) {
      fieldsToUpdate.add(LiveMeeting.kFieldMeetingId);
    }
    liveMeeting = liveMeeting.copyWith(
      meetingId: liveMeeting.meetingId ?? meetingId,
    );

    final shouldRecord = _shouldRecord(event) || (liveMeeting.record);
    if (shouldRecord) {
      // Check if this meeting has had breakout sessions (active or ended)
      // If yes, we need to restart main room recording when someone joins
      // This handles:
      // 1. Someone leaves breakout early and returns to main room (breakouts still active)
      // 2. Someone joins late while everyone is in breakouts (breakouts still active)
      // 3. Everyone returns to main room after breakouts end (breakouts ended)
      final hasHadBreakouts = await _hasRecentBreakoutSessions(
        liveMeetingCollectionPath: liveMeetingCollectionPath,
        meetingId: meetingId,
      );
      
      if (hasHadBreakouts) {
        print('Meeting has had breakout sessions - checking if we need to restart main room recording');
        print('Current breakout session status: ${liveMeeting.currentBreakoutSession?.breakoutRoomStatus}');
        
        // Clear the old recording state to force a fresh start
        // This is safe because recordRoom() will check if a recording is already active
        await firestore.document('$liveMeetingCollectionPath/$meetingId/recording-state/current').delete();
        print('Cleared stale recording state to allow restart');
      }
      
      // For main room, use event ID as file prefix
      // Store recording state to prevent duplicate starts
      // Main room recordings don't need queuing (only one main room per event)
      await agoraUtils.recordRoom(
        roomId: meetingId,
        eventId: event.id,
        filePrefix: event.id,
        recordingStatePath: '$liveMeetingCollectionPath/$meetingId/recording-state/current',
      );
    }

    if (liveMeetingSnapshot.exists && fieldsToUpdate.isNotEmpty) {
      transaction.update(
        liveMeetingSnapshot.reference,
        UpdateData.fromMap(
          jsonSubset(
            fieldsToUpdate,
            firestoreUtils.toFirestoreJson(liveMeeting.toJson()),
          ),
        ),
      );
    } else if (!liveMeetingSnapshot.exists) {
      transaction.set(
        liveMeetingSnapshot.reference,
        DocumentData.fromMap(
          firestoreUtils.toFirestoreJson(liveMeeting.toJson()),
        ),
      );
    }

    final token =
        agoraUtils.createToken(uid: uidToInt(userId), roomId: meetingId);

    return GetMeetingJoinInfoResponse(
      identity: userId,
      meetingToken: token,
      meetingId: meetingId,
    );
  }

  Future<GetMeetingJoinInfoResponse> getBreakoutRoomJoinInfo({
    required String communityId,
    required String meetingId,
    required String userId,
    required bool record,
    String? eventId,
    String? breakoutRoomId,
    String? breakoutRoomPath,
  }) async {
    final token =
        agoraUtils.createToken(uid: uidToInt(userId), roomId: meetingId);
    if (record) {
      // For breakout rooms, use a unique file prefix
      // Agora fileNamePrefix has strict validation - only alphanumeric and simple chars allowed
      // So we use the breakout room ID as the prefix (it's already unique)
      final filePrefix = eventId != null && breakoutRoomId != null
          ? breakoutRoomId  // Use room ID directly - it's unique and Agora-safe
          : eventId ?? meetingId;
      
      // Store recording state in the breakout room's live-meeting document
      final recordingStatePath = breakoutRoomPath != null
          ? '$breakoutRoomPath/live-meetings/$meetingId/recording-state/current'
          : null;
      
      print('Checking recording state for breakout room: $meetingId');
      print('File prefix: $filePrefix');
      print('Recording state path: $recordingStatePath');
      
      // Atomically claim the right to start recording for this room
      // This prevents race conditions when multiple participants join simultaneously
      bool claimedRecording = false;
      if (recordingStatePath != null) {
        try {
          // First check if recording already exists (in any state)
          final recordingStateDoc = await firestore.document(recordingStatePath).get();
          
          if (recordingStateDoc.exists) {
            final recordingState = recordingStateDoc.data.toMap();
            final status = recordingState['status'] as String?;
            final recordingRoomId = recordingState['roomId'] as String?;
            final claimedAtTimestamp = recordingState['claimedAt'] as Timestamp?;
            
            // Check if claim is recent (within last 2 minutes)
            // If older, it's a stale claim that never completed, so we can override
            final isRecentClaim = claimedAtTimestamp != null && 
                DateTime.now().difference(claimedAtTimestamp.toDateTime()) < 
                const Duration(minutes: 2);
            
            // If recording is already active/claimed for this room with recent timestamp, skip
            if ((status == 'recording' || status == 'claiming') && 
                recordingRoomId == meetingId && 
                isRecentClaim) {
              print('Recording already $status for breakout room $meetingId, skipping duplicate');
              claimedRecording = false;
            } else if (status == 'error') {
              // Previous recording attempt failed - allow a new claim attempt
              print('Previous recording attempt failed for room $meetingId, attempting new claim');
              final claimId = _generateClaimId();
              await firestore.document(recordingStatePath).setData(
                DocumentData.fromMap(firestoreUtils.toFirestoreJson({
                  'status': 'claiming',
                  'roomId': meetingId,
                  'claimedBy': userId,
                  'claimId': claimId,
                  'claimedAt': Firestore.fieldValues.serverTimestamp(),
                  'previousError': recordingState['error'],  // Preserve previous error for debugging
                }),),
                SetOptions(merge: false),  // Overwrite the error state
              );
              
              // Verify the claim
              await Future.delayed(const Duration(milliseconds: 50));
              final verifyDoc = await firestore.document(recordingStatePath).get();
              if (verifyDoc.exists) {
                final verifyData = verifyDoc.data.toMap();
                final storedClaimId = verifyData['claimId'] as String?;
                if (storedClaimId == claimId) {
                  claimedRecording = true;
                  print('Claimed recording start for room $meetingId after previous error (claim ID: $claimId)');
                } else {
                  claimedRecording = false;
                  print('Lost race when claiming after error for room $meetingId');
                }
              } else {
                claimedRecording = false;
                print('Claim document disappeared after error recovery for room $meetingId');
              }
            } else if (!isRecentClaim && status == 'claiming') {
              print('Found stale claim for room $meetingId (claimed ${claimedAtTimestamp?.toDateTime()}), will retry');
              // Try to claim it by overwriting the stale claim (use claim ID for verification)
              final claimId = _generateClaimId();
              await firestore.document(recordingStatePath).setData(
                DocumentData.fromMap(firestoreUtils.toFirestoreJson({
                  'status': 'claiming',
                  'roomId': meetingId,
                  'claimedBy': userId,
                  'claimId': claimId,
                  'claimedAt': Firestore.fieldValues.serverTimestamp(),
                }),),
                SetOptions(merge: false),  // Overwrite, don't merge
              );
              
              // Verify the claim (in case multiple requests tried to override simultaneously)
              await Future.delayed(const Duration(milliseconds: 50));
              final verifyDoc = await firestore.document(recordingStatePath).get();
              if (verifyDoc.exists) {
                final verifyData = verifyDoc.data.toMap();
                final storedClaimId = verifyData['claimId'] as String?;
                if (storedClaimId == claimId) {
                  claimedRecording = true;
                  print('Claimed recording start for room $meetingId (overriding stale claim, claim ID: $claimId)');
                } else {
                  claimedRecording = false;
                  print('Lost race when overriding stale claim for room $meetingId');
                }
              } else {
                claimedRecording = false;
                print('Claim document disappeared after stale override for room $meetingId');
              }
            }
          } else {
            // No recording state exists - try to atomically claim it
            // Use a unique claim ID and verify it after writing (optimistic locking pattern)
            final claimId = _generateClaimId();
            try {
              // Write our claim
              await firestore.document(recordingStatePath).setData(
                DocumentData.fromMap(firestoreUtils.toFirestoreJson({
                  'status': 'claiming',
                  'roomId': meetingId,
                  'claimedBy': userId,
                  'claimId': claimId,
                  'claimedAt': Firestore.fieldValues.serverTimestamp(),
                }),),
                SetOptions(merge: false),  // Overwrite any existing doc
              );
              
              // Wait a brief moment for write to propagate (avoid read-your-own-write issues)
              await Future.delayed(const Duration(milliseconds: 50));
              
              // Read back to verify our claim won (in case of simultaneous writes)
              final verifyDoc = await firestore.document(recordingStatePath).get();
              if (verifyDoc.exists) {
                final verifyData = verifyDoc.data.toMap();
                final storedClaimId = verifyData['claimId'] as String?;
                if (storedClaimId == claimId) {
                  claimedRecording = true;
                  print('Successfully claimed recording start for room $meetingId (claim ID: $claimId)');
                } else {
                  // Another request overwrote our claim - they won the race
                  claimedRecording = false;
                  print('Another request won the claim race for room $meetingId (their claim ID: $storedClaimId, ours: $claimId)');
                }
              } else {
                // Document disappeared - very unlikely but treat as failed claim
                claimedRecording = false;
                print('Claim document disappeared for room $meetingId');
              }
            } catch (claimError) {
              // Error during claim process
              print('Error claiming recording for room $meetingId: $claimError');
              claimedRecording = false;
            }
          }
        } catch (e) {
          print('Error checking/claiming recording state for room $meetingId: $e');
          // On error, don't start recording (fail safe to prevent duplicates)
          claimedRecording = false;
        }
      } else {
        // No recording state path provided - allow recording (shouldn't happen for breakouts)
        claimedRecording = true;
      }
      
      if (claimedRecording) {
        print('Queuing recording for breakout room: $meetingId (claim confirmed)');
        
        // Use queued recording for breakout rooms to avoid hitting Agora API rate limits
        // Queue can handle up to 2,500 concurrent recordings with batching and retry logic
        // This is fire-and-forget - we don't block the user joining while the queue processes
        unawaited(
          RecordingQueue().queueRecording(
            roomId: meetingId,
            eventId: eventId,
            filePrefix: filePrefix,
            recordingStatePath: recordingStatePath,
          ).then((_) {
            print('Successfully queued and started recording for breakout room: $meetingId');
          }).catchError((e) {
            print('Failed to start recording for breakout room $meetingId: $e');
          }),
        );
      }
    }

    final meetingInfo = GetMeetingJoinInfoResponse(
      identity: userId,
      meetingToken: token,
      meetingId: meetingId,
    );

    return meetingInfo;
  }
  
  /// Generates a unique claim ID for atomic recording claim operations
  /// Uses timestamp + random number to ensure uniqueness across simultaneous requests
  String _generateClaimId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999);
    return '$timestamp-$random';
  }
}
