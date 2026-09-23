import 'package:enum_to_string/enum_to_string.dart';
import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart';
import '../../on_call_function.dart';
import 'agora_api.dart';
import '../../utils/infra/firestore_utils.dart';
import '../../utils/utils.dart';
import 'package:data_models/cloud_functions/requests.dart';
import 'package:data_models/events/event.dart';
import 'package:data_models/events/event_proposal.dart';
import 'package:data_models/events/live_meetings/live_meeting.dart';
import 'package:data_models/community/membership.dart';
import 'package:data_models/utils/utils.dart';

/// Cast a vote for or against kicking a user from a hostless meeting
class VoteToKick extends OnCallMethod<VoteToKickRequest> {
  AgoraUtils agoraUtils;
  VoteToKick({AgoraUtils? agoraUtils})
      : agoraUtils = agoraUtils ?? AgoraUtils(),
        super('VoteToKick', (json) => VoteToKickRequest.fromJson(json));

  @override
  Future<void> action(
    VoteToKickRequest request,
    CallableContext context,
  ) async {
    orElseUnauthorized(
      (request.liveMeetingPath).startsWith(request.eventPath),
      logMessage: 'Event and live meeting path don\'t match',
    );

    final liveMeetingId = request.liveMeetingPath.split('/').last;

    final participantPath =
        '${request.eventPath}/event-participants/${request.targetUserId}';
    final participantSnapshot = await firestore.document(participantPath).get();
    orElseNotFound(participantSnapshot.exists);
    final participant = Participant.fromJson(
      firestoreUtils.fromFirestoreJson(participantSnapshot.data.toMap()),
    );
    orElseUnauthorized(
      participant.status == ParticipantStatus.active,
      logMessage: 'User does not have active status: ${participant.status}',
    );
    final modStatuses = [
      MembershipStatus.mod,
      MembershipStatus.owner,
      MembershipStatus.admin,
    ];
    orElseUnauthorized(!modStatuses.contains(participant.membershipStatus));

    final proposalsCollection =
        firestore.collection('${request.liveMeetingPath}/proposals');

    final existingProposalSnapshot = await proposalsCollection
        .where(
          EventProposal.kFieldType,
          isEqualTo: EnumToString.convertToString(EventProposalType.kick),
        )
        .where(
          EventProposal.kFieldTargetUserId,
          isEqualTo: request.targetUserId,
        )
        .where(
          EventProposal.kFieldStatus,
          isEqualTo: EnumToString.convertToString(EventProposalStatus.open),
        )
        .limit(1)
        .get();

    final participantsSnapshot = await firestore
        .collection('${request.eventPath}/event-participants')
        .where("currentBreakoutRoomId", isEqualTo: liveMeetingId)
        .where(
          Participant.kFieldIsPresent,
          isEqualTo: true,
        )
        .where(
          Participant.kFieldStatus,
          isEqualTo: EnumToString.convertToString(ParticipantStatus.active),
        )
        .get();
    final participants = participantsSnapshot.documents
        .map(
          (d) => Participant.fromJson(
            firestoreUtils.fromFirestoreJson(d.data.toMap()),
          ),
        )
        .toList();
    final votingParticipants =
        participants.where((p) => p.id != request.targetUserId);

    final shouldKickUser = await firestore.runTransaction((transaction) async {
      bool shouldKickUser = false;
      if (existingProposalSnapshot.documents.isNotEmpty) {
        final reference = existingProposalSnapshot.documents[0].reference;
        final txProposalSnapshot = await transaction.get(reference);
        EventProposal txProposal = EventProposal.fromJson(
          firestoreUtils.fromFirestoreJson(txProposalSnapshot.data.toMap()),
        );
        txProposal.votes
            ?.removeWhere((vote) => vote.voterUserId == context.authUid);
        txProposal.votes?.add(
          EventProposalVote(
            voterUserId: context.authUid,
            inFavor: request.inFavor,
            reason: request.reason,
          ),
        );

        final inFavorCount =
            txProposal.votes?.where((vote) => vote.inFavor == true).length ?? 0;
        final againstCount =
            txProposal.votes?.where((vote) => vote.inFavor == false).length ??
                0;
        if (inFavorCount > 1 && inFavorCount >= votingParticipants.length) {
          shouldKickUser = true;
          final bannedParticipant =
              participant.copyWith(status: ParticipantStatus.banned);
          transaction.update(
            participantSnapshot.reference,
            UpdateData.fromMap(
              jsonSubset(
                [Participant.kFieldStatus, Participant.kFieldLastUpdatedTime],
                firestoreUtils.toFirestoreJson(bannedParticipant.toJson()),
              ),
            ),
          );
          txProposal = txProposal.copyWith(
            status: EventProposalStatus.accepted,
            closedAt: DateTime.now(),
          );
          print('Kicking user ${request.targetUserId} from convo.');
        } else if (inFavorCount + againstCount >= votingParticipants.length) {
          print(
            'Not kicking user ${request.targetUserId} from convo due to no consensus',
          );
          txProposal = txProposal.copyWith(
            status: EventProposalStatus.rejected,
            closedAt: DateTime.now(),
          );
        }

        print('Updating kick proposal to ${txProposal.toJson()}');
        transaction.update(
          reference,
          UpdateData.fromMap(
            jsonSubset(
              [
                EventProposal.kFieldVotes,
                EventProposal.kFieldStatus,
                EventProposal.kFieldClosedAt,
              ],
              firestoreUtils.toFirestoreJson(txProposal.toJson()),
            ),
          ),
        );
      } else {
        final newDoc = proposalsCollection.document();
        final txProposal = EventProposal(
          id: newDoc.documentID,
          initiatingUserId: context.authUid,
          targetUserId: request.targetUserId,
          type: EventProposalType.kick,
          status: EventProposalStatus.open,
          createdAt: DateTime.now(),
          votes: [
            EventProposalVote(
              voterUserId: context.authUid,
              inFavor: request.inFavor,
              reason: request.reason,
            ),
          ],
        );

        print('creating proposal ${txProposal.toJson()}');
        final newData = DocumentData.fromMap(
          firestoreUtils.toFirestoreJson(txProposal.toJson()),
        );
        transaction.create(newDoc, newData);
      }

      return shouldKickUser;
    });

    if (shouldKickUser) {
      print('Current user location is: ${participant.currentBreakoutRoomId}');
      // Kick participant
      final roomId = participant.currentBreakoutRoomId ?? liveMeetingId;
      await agoraUtils.kickParticipant(
        roomId: roomId,
        userId: request.targetUserId,
      );

      // Remove the kicked user from their current BreakoutRoom.participantIds
      // so they don't leave a ghost entry in the waiting room (or any breakout
      // room) that the admin presence indicator reads.
      //
      // Use an atomic arrayRemove rather than a read-modify-write to avoid the
      // TOCTOU race that would exist against concurrent ReassignBreakoutRoom
      // or simultaneous VoteToKick completions.
      final pathParts = request.liveMeetingPath.split('/');
      final breakoutRoomsIdx = pathParts.indexOf('breakout-rooms');
      final currentRoomId = participant.currentBreakoutRoomId;
      if (breakoutRoomsIdx >= 0 && !isNullOrEmpty(currentRoomId)) {
        final breakoutRoomsCollPath =
            pathParts.take(breakoutRoomsIdx + 1).join('/');
        final kickedRoomPath = '$breakoutRoomsCollPath/$currentRoomId';
        await firestore.document(kickedRoomPath).updateData(
          UpdateData.fromMap({
            BreakoutRoom.kFieldParticipantIds:
                Firestore.fieldValues.arrayRemove([request.targetUserId]),
          }),
        );
        print(
          'Removed ${request.targetUserId} from participantIds of room $currentRoomId',
        );
      }
    }
  }
}
