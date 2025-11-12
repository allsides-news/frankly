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
  String createToken({required int uid, required String roomId}) {
    return agoraModule.RtcTokenBuilder.buildTokenWithUid(
      _agoraAppId,
      _agoraAppCertificate,
      roomId,
      uid,
      1 /** Publisher */,
      60 * 10,
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

    print('Authorization field: $authorizationField');

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
  }) async {
    final token = createToken(uid: _recordingUid, roomId: roomId);
    final request = {
      "cname": roomId,
      "uid": _recordingUid.toString(),
      "clientRequest": {
        "token": token,
        "recordingConfig": {
          "transcodingConfig": {
            "height": 360,
            "width": 640,
            "bitrate": 500,
            "fps": 15,
            "mixedVideoLayout": 1,
            "backgroundColor": "#000000",
          },
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
  );
}
