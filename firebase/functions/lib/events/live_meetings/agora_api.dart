@JS()
library agora_api;

import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'package:js/js.dart';
import 'package:data_models/utils/utils.dart';
import 'package:node_interop/node.dart';
import 'package:node_http/node_http.dart' as http;
import 'dart:convert' as convert;
import '../../utils/infra/firestore_utils.dart';

AgoraTokenModule get agoraModule =>
    _agoraModule ??= require('agora-token') as AgoraTokenModule;
AgoraTokenModule? _agoraModule;

String get _agoraAppId => functions.config.get('agora.app_id') as String? ?? '';
int _recordingUid = 456;

String get _agoraRestKey => functions.config.get('agora.rest_key') as String? ?? '';
String get _agoraRestSecret => functions.config.get('agora.rest_secret') as String? ?? '';
String get _agoraAppCertificate =>
    functions.config.get('agora.app_certificate') as String? ?? '';

String get _agoraStorageBucketName =>
    functions.config.get('agora.storage_bucket_name') as String? ?? '';
String get _agoraStorageAccessKey =>
    functions.config.get('agora.storage_access_key') as String? ?? '';
String get _agoraStorageSecretKey =>
functions.config.get('agora.storage_secret_key') as String? ?? '';

class AgoraUtils {
  /// Token + privilege lifetime. Must comfortably exceed the longest event:
  /// the web SDK's automatic reconnect re-joins with the ORIGINAL token, so
  /// a short TTL strands users whose network blips late in a meeting (join
  /// rejected until a manual refresh). The client also renews proactively
  /// via onTokenPrivilegeWillExpire as a second layer.
  static const _tokenExpireSeconds = 60 * 60 * 24;

  String createToken({required int uid, required String roomId}) {
    return agoraModule.RtcTokenBuilder.buildTokenWithUid(
      _agoraAppId,
      _agoraAppCertificate,
      roomId,
      uid,
      1 /** Publisher */,
      _tokenExpireSeconds,
      // agora-token 2.x takes a separate privilege expiry; previously
      // omitted (undefined). Pass it explicitly so join/publish privileges
      // match the token lifetime.
      _tokenExpireSeconds,
    );
  }

  /// Records a room with idempotency check to prevent duplicate recording starts.
  /// 
  /// This checks if recording has already been started for the given roomId and only
  /// starts a new recording if one is not already in progress.
  /// 
  /// Uses a claim-based system to prevent race conditions when multiple users join simultaneously:
  /// 1. Caller must claim the recording (set status='claiming') before calling this
  /// 2. This function verifies the claim exists
  /// 3. Starts recording with Agora
  /// 4. Updates claim to status='recording' on success
  /// 
  /// [roomId] - The Agora channel name to record
  /// [eventId] - The event ID for file storage organization
  /// [filePrefix] - Optional custom file prefix. If not provided, uses eventId
  /// [recordingStatePath] - Optional Firestore path to store recording state for idempotency
  Future<void> recordRoom({
    required String roomId,
    String? eventId,
    String? filePrefix,
    String? recordingStatePath,
    String? screenSharerUserId,
    int? screenShareAgoraUid,
  }) async {
    // Verify that recording has been properly claimed before proceeding
    if (recordingStatePath != null) {
      final recordingStateDoc = await firestore.document(recordingStatePath).get();
      
      if (recordingStateDoc.exists) {
        final recordingState = recordingStateDoc.data.toMap();
        final status = recordingState['status'] as String?;
        final recordingRoomId = recordingState['roomId'] as String?;
        final timestamp = recordingState['startedAt'] as Timestamp? ?? 
                         recordingState['claimedAt'] as Timestamp?;
        
        // Check if recording state is recent (within last 15 minutes)
        // If it's older, assume it's stale and skip (don't restart - another claim should handle it)
        final isRecent = timestamp != null && 
            DateTime.now().difference(timestamp.toDateTime()) < 
            const Duration(minutes: 15);
        
        // If recording is already fully started for this room AND recent, skip
        if (status == 'recording' && recordingRoomId == roomId && isRecent) {
          print('Recording already in progress for room $roomId (started ${timestamp.toDateTime()}), skipping');
          return;
        }
        
        // If status is not 'claiming' or 'recording', something is wrong - skip
        if (status != 'claiming' && status != 'recording') {
          print('Recording state has unexpected status "$status" for room $roomId, skipping');
          return;
        }
        
        // If claim is stale (older than 15 minutes), skip (a fresh claim should be made)
        if (!isRecent) {
          print('Found stale recording state for room $roomId (timestamp ${timestamp?.toDateTime()}), skipping (needs fresh claim)');
          return;
        }
        
        // Valid claim exists - proceed with recording start
        print('Verified claim for room $roomId, proceeding with recording start');
      } else {
        // No claim exists - should not start recording without a claim (prevents race conditions)
        print('No recording claim found for room $roomId, skipping (claim required)');
        return;
      }
    }

    // Get a resource ID
    final resourceId = await _acquireResourceId(roomId: roomId);
    print('Acquired resource ID: $resourceId for room: $roomId');

    try {
      final sid = await _startRecording(
        roomId: roomId,
        resourceId: resourceId,
        filePrefix: filePrefix ?? eventId ?? roomId,
        screenSharerUserId: screenSharerUserId,
        screenShareAgoraUid: screenShareAgoraUid,
      );
      
      // Update recording state from 'claiming' to 'recording' in Firestore
      if (recordingStatePath != null) {
        await firestore.document(recordingStatePath).setData(
          DocumentData.fromMap(firestoreUtils.toFirestoreJson({
            'status': 'recording',
            'roomId': roomId,
            'resourceId': resourceId,
            'sid': sid,
            'filePrefix': filePrefix ?? eventId ?? roomId,
            'startedAt': Firestore.fieldValues.serverTimestamp(),
            // Keep claimedBy and claimedAt from original claim (merge: true preserves them)
          }),),
          SetOptions(merge: true),
        );
        print('Updated recording state to "recording" at $recordingStatePath');
      }
    } catch (e) {
      print("Error in starting recording for room $roomId");
      print(e);
      
      // Store error state and clear the claim so another attempt can be made
      if (recordingStatePath != null) {
        await firestore.document(recordingStatePath).setData(
          DocumentData.fromMap(firestoreUtils.toFirestoreJson({
            'status': 'error',
            'roomId': roomId,
            'error': e.toString(),
            'errorAt': Firestore.fieldValues.serverTimestamp(),
            // Keep claimedBy and claimedAt for debugging (merge: true preserves them)
          }),),
          SetOptions(merge: true),
        );
        print('Marked recording claim as failed for room $roomId to allow retry');
      }
      
      // Rethrow so the caller knows it failed
      rethrow;
    }
  }

  Map<String, String> _getAuthHeaders() {
    final plainCredential = '$_agoraRestKey:$_agoraRestSecret';
    final authorizationField =
        'Basic ${convert.base64.encode(convert.utf8.encode(plainCredential))}';
    return {
      'Authorization': authorizationField,
      'Content-Type': 'application/json',
    };
  }

  Future<String> _acquireResourceId({required String roomId}) async {
    final body = convert.json.encode({
      "cname": roomId,
      "uid": _recordingUid.toString(),
      "clientRequest": {},
    });

    print("Sending with body: $body");

    final result = await http.post(
      Uri.parse(
        'https://api.agora.io/v1/apps/$_agoraAppId/cloud_recording/acquire',
      ),
      headers: _getAuthHeaders(),
      body: body,
    );

    return convert.jsonDecode(result.body)["resourceId"];
  }

  Future<String> _startRecording({
    required String roomId,
    required String resourceId,
    required String filePrefix,
    String? screenSharerUserId,
    int? screenShareAgoraUid,
  }) async {
    final token = createToken(uid: _recordingUid, roomId: roomId);

    // If screen sharing is already active when recording starts, begin with
    // Vertical Presentation layout so the screen UID occupies the large slot
    // from the first frame. Without this, the layout defaults to grid and
    // only switches when the OnLiveMeeting Firestore trigger fires — but that
    // trigger already fired before recording started, so the layout would
    // never update for this session.
    final Map<String, dynamic> transcodingConfig;
    if (screenSharerUserId != null) {
      final maxUid = screenShareAgoraUid ?? uidToInt(screenSharerUserId);
      transcodingConfig = {
        "height": 720,
        "width": 1280,
        "bitrate": 2000,
        "fps": 20,
        "mixedVideoLayout": 2,
        "backgroundColor": "#000000",
        "maxResolutionUid": maxUid.toString(),
      };
    } else {
      transcodingConfig = {
        // 720p is the minimum resolution for screen content to be readable.
        "height": 720,
        "width": 1280,
        "bitrate": 2000,
        "fps": 20,
        "mixedVideoLayout": 1,
        "backgroundColor": "#000000",
      };
    }

    final request = {
      "cname": roomId,
      "uid": _recordingUid.toString(),
      "clientRequest": {
        "token": token,
        "recordingConfig": {
          "transcodingConfig": transcodingConfig,
        },
        "recordingFileConfig": {
          "avFileType": ["hls", "mp4"],
        },
        "storageConfig": {
          // Google Cloud
          "vendor": 6,
          // Has no effect in Google cloud but it is required
          "region": 0,
          "bucket": _agoraStorageBucketName,
          "accessKey": _agoraStorageAccessKey,
          "secretKey": _agoraStorageSecretKey,
          "fileNamePrefix": [filePrefix],
        },
      },
    };

    print('Sending recording start request for room: $roomId with filePrefix: $filePrefix');
    print('Request: $request');
    final result = await http.post(
      Uri.parse(
        'https://api.agora.io/v1/apps/$_agoraAppId/cloud_recording/resourceid/$resourceId/mode/mix/start',
      ),
      headers: _getAuthHeaders(),
      body: convert.json.encode(request),
    );

    print('Recording start result body: ${result.body}');

    if (result.statusCode < 200 || result.statusCode > 299) {
      print('Error starting recording: ${result.statusCode}');
      throw HttpsError(HttpsError.internal, 'Error starting recording', null);
    }

    final sid = convert.jsonDecode(result.body)['sid'] as String;
    
    await _queryRecordingState(
      resourceId: resourceId,
      sid: sid,
    );

    return sid;
  }

  Future<void> _queryRecordingState({
    required String sid,
    required String resourceId,
  }) async {
    final result = await http.get(
      Uri.parse(
        'https://api.agora.io/v1/apps/$_agoraAppId/cloud_recording/resourceid/$resourceId/sid/$sid/mode/mix/query',
      ),
      headers: _getAuthHeaders(),
    );

    print('Recording state: ${result.body}');
  }

  /// Stops an active recording and finalizes the files to Cloud Storage
  /// Includes simple retry logic for rate limit errors (429)
  Future<void> stopRecording({
    required String roomId,
    required String resourceId,
    required String sid,
  }) async {
    const maxRetries = 2;
    
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print('Stopping recording for room: $roomId, sid: $sid (attempt $attempt/$maxRetries)');
        
        final result = await http.post(
          Uri.parse(
            'https://api.agora.io/v1/apps/$_agoraAppId/cloud_recording/resourceid/$resourceId/sid/$sid/mode/mix/stop',
          ),
          headers: _getAuthHeaders(),
          body: convert.json.encode({
            "cname": roomId,
            "uid": _recordingUid.toString(),
            "clientRequest": {},
          }),
        );

        print('Stop recording result: ${result.body}');

        // Check for rate limit (429)
        if (result.statusCode == 429) {
          if (attempt < maxRetries) {
            final delaySeconds = attempt * 2; // 2s, 4s
            print('Rate limit (429) stopping room $roomId, retrying in ${delaySeconds}s');
            await Future.delayed(Duration(seconds: delaySeconds));
            continue; // Retry
          }
          throw HttpsError(HttpsError.resourceExhausted, 'Rate limit stopping recording', null);
        }

        // 404 means Agora already auto-stopped the recording (channel went empty before event ended).
        // The files are already finalized in Cloud Storage — treat as success.
        if (result.statusCode == 404) {
          print('Recording for room $roomId already stopped by Agora (404) — treating as success');
          return;
        }

        if (result.statusCode < 200 || result.statusCode > 299) {
          print('Error stopping recording: ${result.statusCode}');
          throw HttpsError(HttpsError.internal, 'Error stopping recording', null);
        }
        
        print('Successfully stopped recording for room $roomId');
        return; // Success!
        
      } catch (e) {
        if (attempt == maxRetries) {
          print('Error stopping room $roomId after $maxRetries attempts: $e');
          rethrow;
        }
        // Retry on exception (network errors, etc)
        print('Exception stopping room $roomId (attempt $attempt/$maxRetries): $e, retrying...');
        await Future.delayed(Duration(seconds: attempt));
      }
    }
  }

  /// Stops all recordings for an event (main room + all breakouts)
  /// Uses batched processing to avoid Agora API rate limits
  Future<void> stopAllRecordingsForEvent({
    required String eventPath,
    required String eventId,
  }) async {
    print('Stopping all recordings for event: $eventId');
    final liveMeetingPath = '$eventPath/live-meetings/$eventId';
    
    try {
      // Collect all recording tasks
      final stopTasks = <_StopRecordingTask>[];
      
      // 1. Add main room recording
      final mainRoomStatePath = '$liveMeetingPath/recording-state/current';
      stopTasks.add(_StopRecordingTask(
        statePath: mainRoomStatePath,
        roomType: 'main room',
      ),);
      
      // 2. Add all breakout room recordings
      final sessionsSnapshot = await firestore
          .collection('$liveMeetingPath/breakout-room-sessions')
          .get();
      
      for (final sessionDoc in sessionsSnapshot.documents) {
        final roomsSnapshot = await firestore
            .collection('$liveMeetingPath/breakout-room-sessions/${sessionDoc.documentID}/breakout-rooms')
            .get();
        
        for (final roomDoc in roomsSnapshot.documents) {
          final roomId = roomDoc.documentID;
          final statePath = '$liveMeetingPath/breakout-room-sessions/${sessionDoc.documentID}/breakout-rooms/$roomId/live-meetings/$roomId/recording-state/current';
          stopTasks.add(_StopRecordingTask(
            statePath: statePath,
            roomType: 'breakout room $roomId',
          ),);
        }
      }
      
      print('Found ${stopTasks.length} recordings to stop for event $eventId');
      
      // 3. Process in batches to avoid rate limits
      const batchSize = 100;
      const batchDelay = Duration(milliseconds: 200);
      
      for (var i = 0; i < stopTasks.length; i += batchSize) {
        final batch = stopTasks.skip(i).take(batchSize).toList();
        print('Stopping batch ${(i / batchSize).floor() + 1} of ${(stopTasks.length / batchSize).ceil()} (${batch.length} recordings)');
        
        // Process batch concurrently
        await Future.wait(
          batch.map((task) => _stopRecordingFromState(task.statePath, task.roomType)),
        );
        
        // Delay between batches (except after last batch)
        if (i + batchSize < stopTasks.length) {
          await Future.delayed(batchDelay);
        }
      }
      
      print('Finished stopping all recordings for event $eventId');
    } catch (e) {
      print('Error stopping recordings for event $eventId: $e');
      // Don't rethrow - event can still end even if recording stop fails
    }
  }

  /// Helper to stop recording from a recording state document
  Future<void> _stopRecordingFromState(String statePath, String roomType) async {
    try {
      final stateDoc = await firestore.document(statePath).get();
      
      if (!stateDoc.exists) {
        print('No recording state found at $statePath for $roomType');
        return;
      }
      
      final state = stateDoc.data.toMap();
      final status = state['status'] as String?;
      final resourceId = state['resourceId'] as String?;
      final sid = state['sid'] as String?;
      final roomId = state['roomId'] as String?;
      
      if (status != 'recording' || resourceId == null || sid == null || roomId == null) {
        print('Recording not active for $roomType (status: $status)');
        return;
      }
      
      print('Stopping $roomType recording (roomId: $roomId, sid: $sid)');
      await stopRecording(
        roomId: roomId,
        resourceId: resourceId,
        sid: sid,
      );
      
      // Update state to stopped
      await firestore.document(statePath).setData(
        DocumentData.fromMap(firestoreUtils.toFirestoreJson({
          'status': 'stopped',
          'stoppedAt': Firestore.fieldValues.serverTimestamp(),
        }),),
        SetOptions(merge: true),
      );
      
      print('Successfully stopped and marked $roomType recording as stopped');
    } catch (e) {
      print('Error stopping $roomType recording at $statePath: $e');
      // Continue to try stopping other recordings
    }
  }

  /// Updates the composite recording layout when screen sharing starts or stops.
  ///
  /// When [screenSharerUserId] is non-null (screen sharing active):
  ///   - Switches to Vertical Presentation layout (mixedVideoLayout: 2)
  ///   - The screen sharer's video (now the screen stream, not camera) occupies
  ///     ~75% of the frame on the left; other participants fill a column on the right
  ///
  /// When [screenSharerUserId] is null (screen sharing stopped):
  ///   - Reverts to Best Fit grid layout (mixedVideoLayout: 1)
  ///
  /// This is non-blocking/best-effort — a failure does not interrupt the meeting.
  Future<void> updateRecordingLayout({
    required String roomId,
    required String resourceId,
    required String sid,
    required String? screenSharerUserId,
    int? screenShareAgoraUid,
  }) async {
    final Map<String, dynamic> layoutConfig;

    if (screenSharerUserId != null) {
      // Use the screen UID (bit 30 set) as maxResolutionUid only when the
      // client confirmed it joined the channel (dual-engine path). Legacy
      // clients publish screen capture on the camera UID via
      // publishScreenCaptureVideo — the screen UID never joins, so pointing
      // maxResolutionUid there would render the large slot black.
      final maxUid = screenShareAgoraUid ?? uidToInt(screenSharerUserId);
      layoutConfig = {
        "mixedVideoLayout": 2,
        "backgroundColor": "#000000",
        "maxResolutionUid": maxUid.toString(),
      };
    } else {
      layoutConfig = {
        "mixedVideoLayout": 1,
        "backgroundColor": "#000000",
      };
    }

    try {
      final result = await http.post(
        Uri.parse(
          'https://api.agora.io/v1/apps/$_agoraAppId/cloud_recording/resourceid/$resourceId/sid/$sid/mode/mix/updateLayout',
        ),
        headers: _getAuthHeaders(),
        body: convert.json.encode({
          "cname": roomId,
          "uid": _recordingUid.toString(),
          "clientRequest": layoutConfig,
        }),
      );

      print('updateRecordingLayout result (room $roomId, sharer: $screenSharerUserId): ${result.statusCode} ${result.body}');

      if (result.statusCode < 200 || result.statusCode > 299) {
        // Log but don't throw — recording can continue with the old layout.
        print('Warning: recording layout update failed for room $roomId: ${result.statusCode}');
      }
    } catch (e) {
      print('Warning: recording layout update threw for room $roomId: $e');
    }
  }

  // ─── Real-Time Speech-to-Text (STT) ────────────────────────────────────────

  /// UID used by the STT bot in every channel. Must not collide with real user
  /// UIDs (which are 30-bit values derived from Firebase UIDs).
  static const int _sttBotUid = 678;

  /// Starts an Agora Real-Time STT agent for the given [roomId].
  ///
  /// One agent per room subscribes to all participants. The Agora output (JSON
  /// format) includes the speaker UID alongside each utterance, providing
  /// diarization without per-participant bots.
  ///
  /// Files are stored under [filePrefix] in the configured GCS bucket
  /// (e.g. ["stt", "{eventId}"] → gs://bucket/stt/{eventId}/...).
  ///
  /// Uses the same claim-based idempotency pattern as [recordRoom] to prevent
  /// duplicate STT starts when multiple participants join simultaneously.
  Future<void> startSttAgent({
    required String roomId,
    required String filePrefix,
    String? sttStatePath,
    String? expectedClaimId,
    List<String> languages = const ['en-US'],
  }) async {
    if (sttStatePath != null) {
      final stateDoc = await firestore.document(sttStatePath).get();
      if (stateDoc.exists) {
        final state = stateDoc.data.toMap();
        final status = state['status'] as String?;
        final stateRoomId = state['roomId'] as String?;
        final timestamp = state['startedAt'] as Timestamp? ??
            state['claimedAt'] as Timestamp?;
        final isRecent = timestamp != null &&
            DateTime.now().difference(timestamp.toDateTime()) <
                const Duration(minutes: 15);
        if (status == 'running' && stateRoomId == roomId && isRecent) {
          print('STT agent already running for room $roomId, skipping');
          return;
        }
        if (status != 'claiming' && status != 'running') {
          print('STT state has unexpected status "$status" for $roomId, skipping');
          return;
        }
        if (!isRecent) {
          print('Found stale STT state for $roomId, skipping (needs fresh claim)');
          return;
        }
        if (expectedClaimId != null) {
          final storedClaimId = state['claimId'] as String?;
          if (storedClaimId != expectedClaimId) {
            print('STT claim ID mismatch for $roomId (expected $expectedClaimId, got $storedClaimId) — lost race, skipping');
            return;
          }
        }
        print('Verified STT claim for $roomId, proceeding with agent start');
      } else {
        print('No STT claim found for $roomId, skipping (claim required)');
        return;
      }
    }

    final agentName = _buildSttAgentName(roomId);
    final token = createToken(uid: _sttBotUid, roomId: roomId);

    final request = {
      'languages': languages,
      'name': agentName,
      'maxIdleTime': 300,
      'rtcConfig': {
        'channelName': roomId,
        // This endpoint IS the Real-Time STT v7.x API. The "/v1/" segment is the
        // REST path version for this API family; the product version (v7.x) is
        // reflected in the docs URL, not the path. v6.x used a different path:
        // /v1/projects/{id}/rtsc/speech-to-text/...
        // In v7.x, subBotUid is deprecated — pubBotUid covers both subscribe and publish.
        // https://docs.agora.io/en/real-time-stt/rest-api/v7.x/join
        'pubBotUid': _sttBotUid.toString(),
        'pubBotToken': token,
        'enableJsonProtocol': true,
      },
      'captionConfig': {
        'sliceDuration': 60,
        'storage': {
          'vendor': 6,
          'region': 0,
          'bucket': _agoraStorageBucketName,
          'accessKey': _agoraStorageAccessKey,
          'secretKey': _agoraStorageSecretKey,
          'fileNamePrefix': filePrefix.split('/'),
        },
      },
    };

    print('Starting STT agent for room $roomId with name $agentName');
    try {
      final result = await http.post(
        Uri.parse(
          'https://api.agora.io/api/speech-to-text/v1/projects/$_agoraAppId/join',
        ),
        headers: _getAuthHeaders(),
        body: convert.json.encode(request),
      );

      print('STT start result: ${result.statusCode} ${result.body}');

      if (result.statusCode < 200 || result.statusCode > 299) {
        throw HttpsError(HttpsError.internal, 'Error starting STT agent', null);
      }

      final agentId = convert.jsonDecode(result.body)['agent_id'] as String;

      if (sttStatePath != null) {
        await firestore.document(sttStatePath).setData(
          DocumentData.fromMap(firestoreUtils.toFirestoreJson({
            'status': 'running',
            'roomId': roomId,
            'agentId': agentId,
            'agentName': agentName,
            'filePrefix': filePrefix,
            'startedAt': Firestore.fieldValues.serverTimestamp(),
          })),
          SetOptions(merge: true),
        );
        print('Updated STT state to "running" for room $roomId (agent $agentId)');
      }
    } catch (e) {
      print('Error starting STT agent for room $roomId: $e');
      if (sttStatePath != null) {
        await firestore.document(sttStatePath).setData(
          DocumentData.fromMap(firestoreUtils.toFirestoreJson({
            'status': 'error',
            'roomId': roomId,
            'error': e.toString(),
            'errorAt': Firestore.fieldValues.serverTimestamp(),
          })),
          SetOptions(merge: true),
        );
      }
      rethrow;
    }
  }

  /// Stops the STT agent identified by [agentId] for the given [roomId].
  Future<void> stopSttAgent({
    required String roomId,
    required String agentId,
  }) async {
    print('Stopping STT agent $agentId for room $roomId');
    try {
      final result = await http.post(
        Uri.parse(
          'https://api.agora.io/api/speech-to-text/v1/projects/$_agoraAppId/agents/$agentId/leave',
        ),
        headers: _getAuthHeaders(),
      );

      print('STT stop result: ${result.statusCode} ${result.body}');

      if (result.statusCode == 404) {
        print('STT agent $agentId already stopped (404) — treating as success');
        return;
      }
      if (result.statusCode < 200 || result.statusCode > 299) {
        throw HttpsError(HttpsError.internal, 'Error stopping STT agent', null);
      }
    } catch (e) {
      print('Error stopping STT agent $agentId for room $roomId: $e');
      rethrow;
    }
  }

  /// Stops all STT agents for an event (main room + all breakouts).
  Future<void> stopAllSttForEvent({
    required String eventPath,
    required String eventId,
  }) async {
    print('Stopping all STT agents for event: $eventId');
    final liveMeetingPath = '$eventPath/live-meetings/$eventId';

    try {
      final stopTasks = <_StopSttTask>[];

      // Main room STT
      stopTasks.add(_StopSttTask(
        statePath: '$liveMeetingPath/stt-state/current',
        roomType: 'main room',
      ));

      // Breakout room STTs — fetch all sessions' room collections in parallel.
      final sessionsSnapshot = await firestore
          .collection('$liveMeetingPath/breakout-room-sessions')
          .get();

      await Future.wait(
        sessionsSnapshot.documents.map((sessionDoc) async {
          final roomsSnapshot = await firestore
              .collection(
                '$liveMeetingPath/breakout-room-sessions/${sessionDoc.documentID}/breakout-rooms',
              )
              .get();
          for (final roomDoc in roomsSnapshot.documents) {
            final docId = roomDoc.documentID;
            // roomId is the Agora channel name stored in the document — must match
            // the live-meetings/{id} segment written at join time in live_meeting_utils.dart.
            final agoraRoomId = roomDoc.data.toMap()['roomId'] as String? ?? docId;
            stopTasks.add(_StopSttTask(
              statePath:
                  '$liveMeetingPath/breakout-room-sessions/${sessionDoc.documentID}/breakout-rooms/$docId/live-meetings/$agoraRoomId/stt-state/current',
              roomType: 'breakout room $agoraRoomId',
            ));
          }
        }),
      );

      print('Found ${stopTasks.length} STT agent(s) to stop for event $eventId');

      const batchSize = 100;
      const batchDelay = Duration(milliseconds: 200);

      for (var i = 0; i < stopTasks.length; i += batchSize) {
        final batch = stopTasks.skip(i).take(batchSize).toList();
        await Future.wait(
          batch.map((task) => _stopSttFromState(task.statePath, task.roomType)),
        );
        if (i + batchSize < stopTasks.length) {
          await Future.delayed(batchDelay);
        }
      }

      print('Finished stopping all STT agents for event $eventId');
    } catch (e) {
      print('Error stopping STT agents for event $eventId: $e');
    }
  }

  Future<void> _stopSttFromState(String statePath, String roomType) async {
    try {
      final stateDoc = await firestore.document(statePath).get();
      if (!stateDoc.exists) return;

      final state = stateDoc.data.toMap();
      final status = state['status'] as String?;
      final agentId = state['agentId'] as String?;
      final roomId = state['roomId'] as String?;

      if (status == 'claiming') {
        // Agent not yet started — delete the claim so the racing startSttAgent
        // finds no document and aborts rather than starting after event end.
        await firestore.document(statePath).delete();
        print('Deleted in-progress STT claim for $roomType — event ended mid-claim');
        return;
      }

      if (status != 'running' || agentId == null || roomId == null) {
        print('STT not active for $roomType (status: $status)');
        return;
      }

      await stopSttAgent(roomId: roomId, agentId: agentId);

      await firestore.document(statePath).setData(
        DocumentData.fromMap(firestoreUtils.toFirestoreJson({
          'status': 'stopped',
          'stoppedAt': Firestore.fieldValues.serverTimestamp(),
        })),
        SetOptions(merge: true),
      );
      print('Stopped STT agent for $roomType');
    } catch (e) {
      print('Error stopping STT for $roomType at $statePath: $e');
    }
  }

  /// Builds a unique STT agent name from [roomId] (max 64 chars, unique).
  /// The name cannot be reused across calls; timestamp suffix ensures uniqueness.
  String _buildSttAgentName(String roomId) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    // "stt-" prefix + up to 46 chars of roomId + "-" + 13-digit timestamp = max 64
    final safeRoomId = roomId.length > 46 ? roomId.substring(0, 46) : roomId;
    return 'stt-$safeRoomId-$ts';
  }

  Future<void> kickParticipant({
    required String roomId,
    required String userId,
  }) async {
    final result = await http.post(
      Uri.parse('https://api.agora.io/dev/v1/kicking-rule'),
      headers: _getAuthHeaders(),
      body: convert.json.encode(
        {
          "appid": _agoraAppId,
          "cname": roomId,
          "uid": uidToInt(userId),
          "time": 1440,
          "privileges": ["join_channel"],
        },
      ),
    );

    print('Result body: ${result.body}');

    if (result.statusCode < 200 || result.statusCode > 299) {
      print('Error result: ${result.statusCode}');
      throw HttpsError(HttpsError.internal, 'Error kicking user', null);
    }
  }
}

/// Helper class for batching stop STT tasks
class _StopSttTask {
  final String statePath;
  final String roomType;

  _StopSttTask({required this.statePath, required this.roomType});
}

/// Helper class for batching stop recording tasks
class _StopRecordingTask {
  final String statePath;
  final String roomType;

  _StopRecordingTask({
    required this.statePath,
    required this.roomType,
  });
}

@JS()
@anonymous
abstract class AgoraTokenModule {
  //ignore: non_constant_identifier_names
  RtcTokenBuilderClient get RtcTokenBuilder;
}

@JS()
@anonymous
abstract class RtcTokenBuilderClient {
  external String buildTokenWithUid(
    String appId,
    String appCertificate,
    String channelName,
    int uid,
    int role,
    int tokenExpire,
    int privilegeExpire,
  );
}
