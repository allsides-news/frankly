import 'dart:async';

import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import '../../on_firestore_function.dart';
import '../../utils/infra/firestore_event_function.dart';
import '../../utils/infra/firestore_utils.dart';
import 'agora_api.dart';

/// Firestore trigger that fires when a live-meeting document is updated.
///
/// Primary responsibility: dynamically update the Agora composite recording
/// layout when screen sharing starts or stops during a live event.
///
/// When [LiveMeeting.screenSharingUserId] changes:
///   - non-null → Vertical Presentation layout (screen sharer prominent)
///   - null     → Best Fit grid layout (all participants equal)
///
/// The recording state (resourceId, sid) is read from the
/// `{liveMeetingPath}/recording-state/current` document written by
/// [AgoraUtils.recordRoom]. If the room is not being recorded the update
/// is a no-op.
class OnLiveMeeting extends OnFirestoreFunction<LiveMeeting> {
  final AgoraUtils _agoraUtils;

  OnLiveMeeting({AgoraUtils? agoraUtils})
      : _agoraUtils = agoraUtils ?? AgoraUtils(),
        super(
          [
            AppFirestoreFunctionData(
              'LiveMeetingOnUpdate',
              FirestoreEventType.onUpdate,
            ),
          ],
          (snapshot) {
            if (!snapshot.exists) return LiveMeeting();
            return LiveMeeting.fromJson(
              firestoreUtils.fromFirestoreJson(snapshot.data.toMap()),
            );
          },
        );

  @override
  String get documentPath =>
      'community/{communityId}/templates/{templateId}/events/{eventId}/live-meetings/{meetingId}';

  @override
  Future<void> onUpdate(
    Change<DocumentSnapshot> changes,
    LiveMeeting before,
    LiveMeeting after,
    DateTime updateTime,
    EventContext context,
  ) async {
    // Only act when screenSharingUserId actually changed.
    if (before.screenSharingUserId == after.screenSharingUserId) return;

    final communityId = context.params['communityId'] as String;
    final templateId = context.params['templateId'] as String;
    final eventId = context.params['eventId'] as String;
    final meetingId = context.params['meetingId'] as String;

    final liveMeetingPath =
        'community/$communityId/templates/$templateId/events/$eventId/live-meetings/$meetingId';
    final recordingStatePath = '$liveMeetingPath/recording-state/current';

    print(
      'OnLiveMeeting: screenSharingUserId changed '
      '${before.screenSharingUserId} → ${after.screenSharingUserId} '
      'for meeting $meetingId',
    );

    final stateDoc = await firestore.document(recordingStatePath).get();
    if (!stateDoc.exists) {
      print('OnLiveMeeting: no recording state at $recordingStatePath — skipping layout update');
      return;
    }

    final state = stateDoc.data.toMap();
    final status = state['status'] as String?;
    if (status != 'recording') {
      print('OnLiveMeeting: recording not active (status: $status) — skipping layout update');
      return;
    }

    final resourceId = state['resourceId'] as String?;
    final sid = state['sid'] as String?;
    final roomId = state['roomId'] as String?;

    if (resourceId == null || sid == null || roomId == null) {
      print('OnLiveMeeting: missing recording fields (resourceId/sid/roomId) — skipping');
      return;
    }

    // screenShareAgoraUid is written by new dual-engine clients alongside
    // screenSharingUserId. Null for legacy single-engine clients — in that
    // case the recording layout falls back to the camera UID.
    await _agoraUtils.updateRecordingLayout(
      roomId: roomId,
      resourceId: resourceId,
      sid: sid,
      screenSharerUserId: after.screenSharingUserId,
      screenShareAgoraUid: after.screenShareAgoraUid,
    );
  }

  @override
  Future<void> onCreate(
    DocumentSnapshot snapshot,
    LiveMeeting data,
    DateTime updateTime,
    EventContext context,
  ) async {}

  @override
  Future<void> onWrite(
    Change<DocumentSnapshot> changes,
    LiveMeeting before,
    LiveMeeting after,
    DateTime updateTime,
    EventContext context,
  ) async {}

  @override
  Future<void> onDelete(
    DocumentSnapshot snapshot,
    LiveMeeting data,
    DateTime updateTime,
    EventContext context,
  ) async {}
}
