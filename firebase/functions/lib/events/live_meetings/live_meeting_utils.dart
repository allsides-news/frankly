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

/// Carries recording-related fields out of the Firestore transaction so that
/// Agora API calls happen after the transaction commits, not inside it.
///
/// Calling Agora inside a `runTransaction` callback:
///  1. Inflates transaction duration → more Firestore contention.
///  2. Duplicates Agora calls on every retry (Firestore retries up to 5×
///     on contention — common when many users join simultaneously).
///  3. Can cause the transaction to exceed its deadline and surface as
///     `[firebase_functions/internal] internal` to the client.
typedef MeetingJoinTransactionResult = ({
  GetMeetingJoinInfoResponse joinInfo,
  bool shouldRecord,
  bool shouldTranscribe,
  String liveMeetingCollectionPath,
  String? screenSharerUserId,
  int? screenShareAgoraUid,
});

class LiveMeetingUtils {
  bool _shouldRecord(Event event) => event.eventSettings?.alwaysRecord ?? false;
  bool _shouldTranscribe(Event event) =>
      event.eventSettings?.alwaysTranscribe ?? false;
  AgoraUtils agoraUtils;

  LiveMeetingUtils({AgoraUtils? agoraUtils})
      : agoraUtils = agoraUtils ?? AgoraUtils();

  /// Ensures the user's publicUser doc stores the agoraId their tokens are
  /// issued under, so other participants' GetUserIdFromAgoraId lookups (which
  /// query `where agoraId ==`) can find them. Older docs predate the agoraId
  /// field; the client backfills it in memory on read but never writes it.
  ///
  /// Called on every join, before the join response is returned — the joiner
  /// only connects to Agora after receiving their token, so the backfill is
  /// guaranteed to land before any other participant tries to look them up.
  ///
  /// Best-effort: failures are logged and never block the join.
  Future<void> ensurePublicUserAgoraId({required String userId}) async {
    try {
      final agoraId = uidToInt(userId);
      final docRef = firestore.document('publicUser/$userId');
      final snapshot = await docRef.get();
      // A missing doc means signup never created it; creating one here with
      // only an agoraId would produce a lookup result with no usable id.
      if (!snapshot.exists) return;
      if (snapshot.data.toMap()['agoraId'] != agoraId) {
        await docRef.setData(
          DocumentData.fromMap({'agoraId': agoraId}),
          SetOptions(merge: true),
        );
        print('Backfilled agoraId $agoraId on publicUser/$userId');
      }
    } catch (e) {
      print('Warning: failed to ensure agoraId on publicUser/$userId: $e');
    }
  }

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

  /// Transactional part of joining a main meeting room.
  ///
  /// Reads and (if needed) initialises the live-meeting document, generates
  /// Agora tokens, and returns a [MeetingJoinTransactionResult] that carries
  /// any recording context needed by [handleMainRoomRecordingOnJoin].
  ///
  /// **No Agora API calls are made here.** Recording setup is intentionally
  /// deferred to [handleMainRoomRecordingOnJoin], which must be called after
  /// the enclosing `runTransaction` commits. This keeps the transaction short
  /// and avoids Agora call duplication on Firestore retries.
  Future<MeetingJoinTransactionResult> getMeetingJoinInfo({
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
    final liveMeetingMap = liveMeetingSnapshot.exists
        ? firestoreUtils.fromFirestoreJson(liveMeetingSnapshot.data.toMap())
        : <String, dynamic>{};
    var liveMeeting = LiveMeeting.fromJson(liveMeetingMap);
    if (isNullOrEmpty(liveMeeting.meetingId)) {
      fieldsToUpdate.add(LiveMeeting.kFieldMeetingId);
    }
    liveMeeting = liveMeeting.copyWith(
      meetingId: liveMeeting.meetingId ?? meetingId,
    );

    final shouldRecord = _shouldRecord(event) || liveMeeting.record;
    final shouldTranscribe = _shouldTranscribe(event);

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
    // Screen share UID occupies bit 30 — guaranteed non-colliding with camera UIDs
    // (which are < 2^30 by the modValue in uidToInt).
    final screenUid = uidToInt(userId) | (1 << 30);
    final screenShareToken =
        agoraUtils.createToken(uid: screenUid, roomId: meetingId);

    return (
      joinInfo: GetMeetingJoinInfoResponse(
        identity: userId,
        meetingToken: token,
        meetingId: meetingId,
        screenShareToken: screenShareToken,
      ),
      shouldRecord: shouldRecord,
      shouldTranscribe: shouldTranscribe,
      liveMeetingCollectionPath: liveMeetingCollectionPath,
      screenSharerUserId: liveMeeting.screenSharingUserId,
      screenShareAgoraUid: liveMeeting.screenShareAgoraUid,
    );
  }

  /// Handles recording setup for the main meeting room **after** the Firestore
  /// transaction in [getMeetingJoinInfo] has committed.
  ///
  /// Separating this from the transaction avoids three failure modes:
  ///  1. Long Agora HTTP round-trips inside a transaction inflate its duration,
  ///     increasing the chance of Firestore contention aborts.
  ///  2. On each Firestore retry the Agora calls would be duplicated, potentially
  ///     starting multiple recordings.
  ///  3. If the transaction exhausted its retries, the uncaught Firestore error
  ///     propagated as `[firebase_functions/internal] internal`.
  ///
  /// This method is best-effort: any failure is logged but does not block the
  /// user join (they already have their Agora token from [getMeetingJoinInfo]).
  Future<void> handleMainRoomRecordingOnJoin({
    required String liveMeetingCollectionPath,
    required String meetingId,
    required String userId,
    required Event event,
    required String? screenSharerUserId,
    required int? screenShareAgoraUid,
  }) async {
    // Check if this meeting has had breakout sessions (active or ended).
    // If yes, we may need to restart main-room recording when someone joins.
    // Handles:
    //  1. Someone leaves a breakout early and returns to the main room.
    //  2. Someone joins late while everyone else is in breakouts.
    //  3. Everyone returns to the main room after breakouts end.
    final hasHadBreakouts = await _hasRecentBreakoutSessions(
      liveMeetingCollectionPath: liveMeetingCollectionPath,
      meetingId: meetingId,
    );

    final recordingStatePath =
        '$liveMeetingCollectionPath/$meetingId/recording-state/current';

    if (hasHadBreakouts) {
      print(
        'Meeting $meetingId has had breakout sessions — '
        'checking whether main-room recording needs a restart',
      );

      // Guard: never delete an actively-running Agora session.
      // Only clear the state doc when it is in a terminal or stale state so
      // that a fresh claim can be placed below.
      final existingStateDoc =
          await firestore.document(recordingStatePath).get();
      if (existingStateDoc.exists) {
        final status =
            existingStateDoc.data.toMap()['status'] as String?;
        if (status == 'recording') {
          // claimedAt is set at claim time only; Agora session may run much longer.
          print(
            'Recording already active for $meetingId — '
            'skipping state reset (breakout restart not needed)',
          );
          return;
        }
      }

      await firestore.document(recordingStatePath).delete();
      print('Cleared stale recording state for $meetingId to allow restart');
    }

    // Recording-state uses direct Firestore reads/writes (not the outer
    // transaction), so the claim is immediately visible to recordRoom's own
    // .get() call. The outer transaction only updated the live-meeting document.
    final recordingStateDoc =
        await firestore.document(recordingStatePath).get();
    var shouldCallRecordRoom = false;

    if (!recordingStateDoc.exists) {
      shouldCallRecordRoom = await _tryClaimMainRoomRecording(
        recordingStatePath: recordingStatePath,
        meetingId: meetingId,
        userId: userId,
      );
    } else {
      final recordingState = recordingStateDoc.data.toMap();
      final status = recordingState['status'] as String?;
      final recordingRoomId = recordingState['roomId'] as String?;
      final claimedAtTimestamp = recordingState['claimedAt'] as Timestamp?;
      final isRecentClaim = claimedAtTimestamp != null &&
          DateTime.now().difference(claimedAtTimestamp.toDateTime()) <
              const Duration(minutes: 2);

      if (status == 'recording' &&
          (recordingRoomId == meetingId || recordingRoomId == null)) {
        // In-flight Agora sessions can exceed the stale-claim window; never clobber.
        // null roomId means doc was written before claim pattern; treat as matching.
        print('Main-room recording already $status for $meetingId; skip recordRoom');
      } else if (status == 'claiming' &&
          recordingRoomId == meetingId &&
          isRecentClaim) {
        print('Main-room recording already $status for $meetingId; skip recordRoom');
      } else if (status == 'error') {
        shouldCallRecordRoom = await _tryClaimMainRoomRecording(
          recordingStatePath: recordingStatePath,
          meetingId: meetingId,
          userId: userId,
          previousError: recordingState['error'],
        );
      } else if (status == 'claiming' &&
          recordingRoomId == meetingId &&
          !isRecentClaim) {
        shouldCallRecordRoom = await _tryClaimMainRoomRecording(
          recordingStatePath: recordingStatePath,
          meetingId: meetingId,
          userId: userId,
        );
      } else {
        // Stale recording, odd states, or missing fields — overwrite with a verified claim.
        shouldCallRecordRoom = await _tryClaimMainRoomRecording(
          recordingStatePath: recordingStatePath,
          meetingId: meetingId,
          userId: userId,
        );
      }
    }

    if (shouldCallRecordRoom) {
      try {
        await agoraUtils.recordRoom(
          roomId: meetingId,
          eventId: event.id,
          filePrefix: event.id,
          recordingStatePath: recordingStatePath,
          // Pass the current screen sharer so recording starts in Vertical
          // Presentation layout rather than grid when sharing is already active.
          screenSharerUserId: screenSharerUserId,
          screenShareAgoraUid: screenShareAgoraUid,
        );
      } catch (e) {
        // Recording failure must not block join — user already has their token.
        // recordRoom already wrote 'error' status to Firestore for retry.
        print('Warning: recordRoom failed for $meetingId: $e');
      }
    }
  }

  /// Handles STT agent startup for the main meeting room **after** the
  /// Firestore transaction in [getMeetingJoinInfo] has committed.
  ///
  /// Uses the same claim-based idempotency pattern as
  /// [handleMainRoomRecordingOnJoin] to prevent duplicate STT starts.
  Future<void> handleMainRoomTranscriptionOnJoin({
    required String liveMeetingCollectionPath,
    required String meetingId,
    required String userId,
    required Event event,
  }) async {
    final sttStatePath =
        '$liveMeetingCollectionPath/$meetingId/stt-state/current';

    // Mirror the recording restart logic: when participants return to the main
    // room after breakouts, the STT agent may have auto-stopped (maxIdleTime=300s)
    // while Firestore still shows status:'running'. Clear stale state so a fresh
    // claim can be placed below.
    final hasHadBreakouts = await _hasRecentBreakoutSessions(
      liveMeetingCollectionPath: liveMeetingCollectionPath,
      meetingId: meetingId,
    );

    String? sttClaimId;

    if (hasHadBreakouts) {
      // After breakouts: check current state once and decide without a second read.
      final existingDoc = await firestore.document(sttStatePath).get();
      if (existingDoc.exists) {
        final state = existingDoc.data.toMap();
        final status = state['status'] as String?;
        if (status == 'running') {
          final startedAt = state['startedAt'] as Timestamp? ??
              state['claimedAt'] as Timestamp?;
          final isRecent = startedAt != null &&
              DateTime.now().difference(startedAt.toDateTime()) <
                  const Duration(seconds: 300);
          if (isRecent) {
            // Agent is likely still alive — don't clobber it.
            print('STT already active for $meetingId after breakouts — skipping reset');
            return;
          }
          print('Stale running STT state for $meetingId after breakouts — resetting');
        }
        // Non-running or stale-running doc — delete and claim directly.
        // No second read needed: we just deleted it, so it is guaranteed non-existent.
        await firestore.document(sttStatePath).delete();
        print('Cleared stale STT state for $meetingId to allow post-breakout restart');
      }
      sttClaimId = await _tryClaimRoomStt(
        sttStatePath: sttStatePath,
        meetingId: meetingId,
        userId: userId,
        logLabel: 'main room',
      );
    } else {
      final stateDoc = await firestore.document(sttStatePath).get();
      if (!stateDoc.exists) {
        sttClaimId = await _tryClaimRoomStt(
          sttStatePath: sttStatePath,
          meetingId: meetingId,
          userId: userId,
          logLabel: 'main room',
        );
      } else {
        final state = stateDoc.data.toMap();
        final status = state['status'] as String?;
        final stateRoomId = state['roomId'] as String?;
        final claimedAt = state['claimedAt'] as Timestamp?;
        final isRecentClaim = claimedAt != null &&
            DateTime.now().difference(claimedAt.toDateTime()) <
                const Duration(minutes: 2);
        final startedAt = state['startedAt'] as Timestamp? ??
            state['claimedAt'] as Timestamp?;
        final isRecentRunning = startedAt != null &&
            DateTime.now().difference(startedAt.toDateTime()) <
                const Duration(minutes: 15);

        if (status == 'running' &&
            (stateRoomId == meetingId || stateRoomId == null) &&
            isRecentRunning) {
          print('STT already running for $meetingId; skip startSttAgent');
        } else if (status == 'claiming' && stateRoomId == meetingId && isRecentClaim) {
          print('STT already claiming for $meetingId; skip startSttAgent');
        } else {
          sttClaimId = await _tryClaimRoomStt(
            sttStatePath: sttStatePath,
            meetingId: meetingId,
            userId: userId,
            logLabel: 'main room',
          );
        }
      }
    }

    if (sttClaimId != null) {
      unawaited(
        agoraUtils.startSttAgent(
          roomId: meetingId,
          filePrefix: 'stt/${event.id}',
          sttStatePath: sttStatePath,
          expectedClaimId: sttClaimId,
        ).catchError((Object e) {
          print('Warning: startSttAgent failed for $meetingId: $e');
        }),
      );
    }
  }

  Future<String?> _tryClaimRoomStt({
    required String sttStatePath,
    required String meetingId,
    required String userId,
    required String logLabel,
  }) async {
    final claimId = _generateClaimId();
    try {
      await firestore.document(sttStatePath).setData(
        DocumentData.fromMap(firestoreUtils.toFirestoreJson({
          'status': 'claiming',
          'roomId': meetingId,
          'claimedBy': userId,
          'claimId': claimId,
          'claimedAt': Firestore.fieldValues.serverTimestamp(),
        })),
        SetOptions(merge: false),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      final verifyDoc = await firestore.document(sttStatePath).get();
      if (!verifyDoc.exists) return null;
      final storedClaimId = verifyDoc.data.toMap()['claimId'] as String?;
      if (storedClaimId == claimId) {
        print('STT claim verified for $logLabel $meetingId ($claimId)');
        return claimId;
      }
      print('Lost STT claim race for $logLabel $meetingId');
      return null;
    } catch (e) {
      print('STT claim failed for $logLabel $meetingId: $e');
      return null;
    }
  }

  Future<GetMeetingJoinInfoResponse> getBreakoutRoomJoinInfo({
    required String communityId,
    required String meetingId,
    required String userId,
    required bool record,
    bool transcribe = false,
    String? eventId,
    String? breakoutRoomId,
    String? breakoutRoomPath,
    String? screenSharerUserId,
    int? screenShareAgoraUid,
  }) async {
    await ensurePublicUserAgoraId(userId: userId);

    final token =
        agoraUtils.createToken(uid: uidToInt(userId), roomId: meetingId);

    if (transcribe && breakoutRoomPath != null && breakoutRoomId != null) {
      final sttStatePath =
          '$breakoutRoomPath/live-meetings/$meetingId/stt-state/current';
      // meetingId == breakoutRoom.roomId (Agora channel name) — must match the
      // GCS prefix the download function searches: stt/${room.roomId}/
      final sttFilePrefix = 'stt/$meetingId';

      String? sttClaimId;
      try {
        final sttStateDoc = await firestore.document(sttStatePath).get();
        if (sttStateDoc.exists) {
          final sttState = sttStateDoc.data.toMap();
          final status = sttState['status'] as String?;
          final stateRoomId = sttState['roomId'] as String?;
          final claimedAt = sttState['claimedAt'] as Timestamp?;
          final isRecentClaim = claimedAt != null &&
              DateTime.now().difference(claimedAt.toDateTime()) <
                  const Duration(minutes: 2);
          // Use startedAt for the running-state staleness check — matches the 15-minute
          // threshold in startSttAgent. An agent auto-stopped by Agora after maxIdleTime
          // (300s) leaves status:'running' in Firestore; the staleness guard lets a
          // rejoining participant reclaim and restart it.
          final startedAt = sttState['startedAt'] as Timestamp? ??
              sttState['claimedAt'] as Timestamp?;
          final isRecentRunning = startedAt != null &&
              DateTime.now().difference(startedAt.toDateTime()) <
                  const Duration(minutes: 15);
          if (status == 'running' && stateRoomId == meetingId && isRecentRunning) {
            print('STT already running for breakout room $meetingId, skipping');
          } else if (status == 'claiming' &&
              stateRoomId == meetingId &&
              isRecentClaim) {
            print('STT already claiming for breakout room $meetingId, skipping');
          } else {
            sttClaimId = await _tryClaimRoomStt(
              sttStatePath: sttStatePath,
              meetingId: meetingId,
              userId: userId,
              logLabel: 'breakout room',
            );
          }
        } else {
          sttClaimId = await _tryClaimRoomStt(
            sttStatePath: sttStatePath,
            meetingId: meetingId,
            userId: userId,
            logLabel: 'breakout room',
          );
        }
      } catch (e) {
        print('Error claiming STT for breakout $meetingId: $e');
      }

      if (sttClaimId != null) {
        // Fire-and-forget — do not block the join on an unbounded Agora HTTP call.
        // Errors are written to Firestore as status:'error' by startSttAgent itself.
        // Mirrors the unawaited recording pattern at the bottom of this method.
        unawaited(
          agoraUtils.startSttAgent(
            roomId: meetingId,
            filePrefix: sttFilePrefix,
            sttStatePath: sttStatePath,
            expectedClaimId: sttClaimId,
          ).catchError((Object e) {
            print('Warning: startSttAgent failed for breakout $meetingId: $e');
          }),
        );
      }
    }

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
            screenSharerUserId: screenSharerUserId,
            screenShareAgoraUid: screenShareAgoraUid,
          ).then((_) {
            print('Successfully queued and started recording for breakout room: $meetingId');
          }).catchError((e) {
            print('Failed to start recording for breakout room $meetingId: $e');
          }),
        );
      }
    }

    final screenUid = uidToInt(userId) | (1 << 30);
    final screenShareToken =
        agoraUtils.createToken(uid: screenUid, roomId: meetingId);

    return GetMeetingJoinInfoResponse(
      identity: userId,
      meetingToken: token,
      meetingId: meetingId,
      screenShareToken: screenShareToken,
    );
  }

  /// Same optimistic-claim pattern as breakout rooms: write `claimId`, re-read, and only
  /// return true if our claim survived (avoids duplicate Agora starts when two joins race).
  Future<bool> _tryClaimMainRoomRecording({
    required String recordingStatePath,
    required String meetingId,
    required String userId,
    Object? previousError,
  }) async {
    final claimId = _generateClaimId();
    final payload = <String, Object?>{
      'status': 'claiming',
      'roomId': meetingId,
      'claimedBy': userId,
      'claimId': claimId,
      'claimedAt': Firestore.fieldValues.serverTimestamp(),
    };
    if (previousError != null) {
      payload['previousError'] = previousError;
    }
    try {
      await firestore.document(recordingStatePath).setData(
        DocumentData.fromMap(firestoreUtils.toFirestoreJson(payload)),
        SetOptions(merge: false),
      );
      await Future.delayed(const Duration(milliseconds: 50));
      final verifyDoc = await firestore.document(recordingStatePath).get();
      if (!verifyDoc.exists) {
        print('Main-room claim doc missing after write for $meetingId');
        return false;
      }
      final storedClaimId = verifyDoc.data.toMap()['claimId'] as String?;
      if (storedClaimId == claimId) {
        print('Main-room recording claim verified for $meetingId ($claimId)');
        return true;
      }
      print(
        'Main-room lost claim race for $meetingId (stored: $storedClaimId, ours: $claimId)',
      );
      return false;
    } catch (e) {
      print('Main-room claim failed for $meetingId: $e');
      return false;
    }
  }

  /// Generates a unique claim ID for atomic recording claim operations
  /// Uses timestamp + random number to ensure uniqueness across simultaneous requests
  String _generateClaimId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(999999);
    return '$timestamp-$random';
  }
}
