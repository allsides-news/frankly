import 'package:data_models/community/membership.dart';
import 'package:data_models/events/event_proposal.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import 'package:functions/events/live_meetings/vote_to_kick.dart';
import 'package:functions/utils/infra/firestore_utils.dart';

import 'package:data_models/events/event.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:firebase_admin_interop/firebase_admin_interop.dart'
    hide EventType;

import '../../util/community_test_utils.dart';
import '../../util/event_test_utils.dart';
import '../../util/function_test_fixture.dart';
import '../../util/live_meeting_test_utils.dart';

// Voter IDs that participate in breakout room alongside the target.
const voterUserId1 = adminUserId;
const voterUserId2 = 'testUser3';

void main() {
  late String communityId;
  const targetUserId = 'testUser2';
  const templateId = '9654';
  const liveMeetingId = 'testMeeting123';
  final eventUtils = EventTestUtils();
  final communityUtils = CommunityTestUtils();
  late Event testEvent;
  late MockAgoraUtils mockAgoraUtils;
  setupTestFixture();

  /// Joins [uid] to [testEvent] and places them in [liveMeetingId] as an
  /// active, present participant — matching the real-world state a participant
  /// has while sitting in a breakout room.
  Future<void> joinIntoRoom(
    String uid, {
    ParticipantStatus status = ParticipantStatus.active,
    bool isPresent = true,
    MembershipStatus membershipStatus = MembershipStatus.attendee,
  }) =>
      eventUtils.joinEvent(
        communityId: communityId,
        templateId: templateId,
        eventId: testEvent.id,
        uid: uid,
        currentBreakoutRoomId: liveMeetingId,
        isPresent: isPresent,
        participantStatus: status,
        participantMembershipStatus: membershipStatus,
      );

  setUp(() async {
    setFirebaseAppFactory(() => FirebaseAdmin.instance.initializeApp()!);

    communityId = await communityUtils.createTestCommunity();

    testEvent = Event(
      id: '5678',
      status: EventStatus.active,
      communityId: communityId,
      templateId: templateId,
      creatorId: adminUserId,
      nullableEventType: EventType.hostless,
      collectionPath: '',
    );
    testEvent = await eventUtils.createEvent(
      event: testEvent,
      userId: adminUserId,
    );

    // Place all four room members into the breakout room.
    // targetUserId is the person being voted on; the other two are voters.
    // adminUserId was created by createEvent without a room assignment, so we
    // re-join them here (merge: true) to set currentBreakoutRoomId.
    await joinIntoRoom(targetUserId);
    await joinIntoRoom(voterUserId1);
    await joinIntoRoom(voterUserId2);

    mockAgoraUtils = MockAgoraUtils();
    when(
      () => mockAgoraUtils.kickParticipant(
        roomId: any(named: 'roomId'),
        userId: any(named: 'userId'),
      ),
    ).thenAnswer((_) => Future.value());
  });

  VoteToKickRequest buildRequest({bool inFavor = true, String? reason}) =>
      VoteToKickRequest(
        eventPath: testEvent.fullPath,
        liveMeetingPath: '${testEvent.fullPath}/live-meetings/$liveMeetingId',
        targetUserId: targetUserId,
        inFavor: inFavor,
        reason: reason ?? 'Inappropriate behavior',
      );

  test('Successfully creates new kick proposal', () async {
    final voteToKick = VoteToKick(agoraUtils: mockAgoraUtils);

    await voteToKick.action(
      buildRequest(),
      CallableContext(voterUserId1, null, 'fakeInstanceId'),
    );

    final proposalsSnapshot = await firestore
        .collection(
          '${testEvent.fullPath}/live-meetings/$liveMeetingId/proposals',
        )
        .where('type', isEqualTo: 'kick')
        .where('targetUserId', isEqualTo: targetUserId)
        .get();

    expect(proposalsSnapshot.documents.length, equals(1));
    final proposal = EventProposal.fromJson(
      firestoreUtils.fromFirestoreJson(
        proposalsSnapshot.documents.first.data.toMap(),
      ),
    );
    expect(proposal.initiatingUserId, equals(voterUserId1));
    expect(proposal.targetUserId, equals(targetUserId));
    expect(proposal.status, equals(EventProposalStatus.open));
    expect(proposal.votes?.length, equals(1));
    expect(proposal.votes?.first.inFavor, isTrue);
    expect(proposal.votes?.first.reason, equals('Inappropriate behavior'));
  });

  test('Proposal stays open until all present participants have voted',
      () async {
    // With 3 participants in the room (target + 2 voters), the threshold is 2.
    // After only one voter votes the proposal must remain open.
    final voteToKick = VoteToKick(agoraUtils: mockAgoraUtils);

    await voteToKick.action(
      buildRequest(),
      CallableContext(voterUserId1, null, 'fakeInstanceId'),
    );

    final proposalsSnapshot = await firestore
        .collection(
          '${testEvent.fullPath}/live-meetings/$liveMeetingId/proposals',
        )
        .where('type', isEqualTo: 'kick')
        .where('targetUserId', isEqualTo: targetUserId)
        .get();

    final proposal = EventProposal.fromJson(
      firestoreUtils.fromFirestoreJson(
        proposalsSnapshot.documents.first.data.toMap(),
      ),
    );
    expect(proposal.status, equals(EventProposalStatus.open));
  });

  test('User gets kicked when all present participants vote in favour',
      () async {
    final voteToKick = VoteToKick(agoraUtils: mockAgoraUtils);

    await voteToKick.action(
      buildRequest(),
      CallableContext(voterUserId1, null, 'fakeInstanceId'),
    );
    await voteToKick.action(
      buildRequest(),
      CallableContext(voterUserId2, null, 'fakeInstanceId'),
    );

    final participantSnapshot = await firestore
        .document('${testEvent.fullPath}/event-participants/$targetUserId')
        .get();
    final participant = Participant.fromJson(
      firestoreUtils.fromFirestoreJson(participantSnapshot.data.toMap()),
    );

    expect(participant.status, equals(ParticipantStatus.banned));
    verify(
      () => mockAgoraUtils.kickParticipant(
        roomId: liveMeetingId,
        userId: targetUserId,
      ),
    ).called(1);
  });

  test(
      'Phantom participant (isPresent=false) does not inflate threshold — '
      'proposal still closes with remaining voters', () async {
    // Simulate a participant who disconnected abruptly: currentBreakoutRoomId
    // is still set but isPresent is false.  This is the root cause of the
    // "poll continues forever" bug.  The phantom must NOT count toward the
    // voting threshold, so the two genuinely-present voters should be
    // sufficient to close the proposal.
    await joinIntoRoom('phantomUser', isPresent: false);

    final voteToKick = VoteToKick(agoraUtils: mockAgoraUtils);

    await voteToKick.action(
      buildRequest(),
      CallableContext(voterUserId1, null, 'fakeInstanceId'),
    );
    await voteToKick.action(
      buildRequest(),
      CallableContext(voterUserId2, null, 'fakeInstanceId'),
    );

    final proposalsSnapshot = await firestore
        .collection(
          '${testEvent.fullPath}/live-meetings/$liveMeetingId/proposals',
        )
        .where('type', isEqualTo: 'kick')
        .where('targetUserId', isEqualTo: targetUserId)
        .get();

    final proposal = EventProposal.fromJson(
      firestoreUtils.fromFirestoreJson(
        proposalsSnapshot.documents.first.data.toMap(),
      ),
    );
    expect(
      proposal.status,
      isNot(equals(EventProposalStatus.open)),
      reason: 'Phantom (disconnected) participant should not block consensus',
    );
  });

  test('Throws unauthorized error when target user is a moderator', () async {
    await joinIntoRoom(
      targetUserId,
      membershipStatus: MembershipStatus.mod,
    );

    final voteToKick = VoteToKick(agoraUtils: mockAgoraUtils);

    expect(
      () => voteToKick.action(
        buildRequest(),
        CallableContext(voterUserId1, null, 'fakeInstanceId'),
      ),
      throwsA(
        predicate(
          (e) =>
              e is HttpsError &&
              e.code == HttpsError.failedPrecondition &&
              e.message == 'unauthorized',
        ),
      ),
    );
  });

  test('Proposal gets rejected when consensus is not reached', () async {
    final voteToKick = VoteToKick(agoraUtils: mockAgoraUtils);

    await voteToKick.action(
      buildRequest(inFavor: false, reason: 'Not necessary'),
      CallableContext(voterUserId1, null, 'fakeInstanceId'),
    );
    await voteToKick.action(
      buildRequest(inFavor: false, reason: 'Not necessary'),
      CallableContext(voterUserId2, null, 'fakeInstanceId'),
    );

    final proposalsSnapshot = await firestore
        .collection(
          '${testEvent.fullPath}/live-meetings/$liveMeetingId/proposals',
        )
        .where('type', isEqualTo: 'kick')
        .where('targetUserId', isEqualTo: targetUserId)
        .get();

    final proposal = EventProposal.fromJson(
      firestoreUtils.fromFirestoreJson(
        proposalsSnapshot.documents.first.data.toMap(),
      ),
    );

    expect(proposal.status, equals(EventProposalStatus.rejected));
    expect(proposal.closedAt, isNotNull);
  });
}
