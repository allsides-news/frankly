import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:client/core/data/services/logging_service.dart';
import 'package:client/core/utils/firestore_utils.dart';
import 'package:client/services.dart';
import 'package:data_models/community/membership.dart';

class FirestoreMembershipService {
  CollectionReference<Map<String, dynamic>> _userMembershipsCollection(
    String userId,
  ) =>
      firestoreDatabase.firestore
          .collection('memberships')
          .doc(userId)
          .collection('community-membership');

  DocumentReference<Map<String, dynamic>> membershipsReference({
    required String userId,
    required String communityId,
  }) =>
      firestoreDatabase.firestore
          .doc('memberships/$userId/community-membership/$communityId');

  BehaviorSubjectWrapper<List<Membership>> userMembershipsStream(
    String userId,
  ) =>
      wrapInBehaviorSubject(
        _userMembershipsCollection(userId)
            .snapshots()
            .map((s) => s.docs)
            .asyncMap(_convertMembershipListAsync),
      );

  BehaviorSubjectWrapper<List<Membership>> communityMembershipsStream({
    required String communityId,
  }) {
    return wrapInBehaviorSubject(
      firestoreDatabase.firestore
          .collectionGroup('community-membership')
          .where(Membership.kFieldCommunityId, isEqualTo: communityId)
          .orderBy(Membership.kFieldFirstJoined)
          .snapshots()
          .map((s) => s.docs)
          .asyncMap(_convertMembershipListAsync),
    );
  }

  Stream<Membership?> getMembershipForUser({
    required String communityId,
    required String userId,
  }) {
    return membershipsReference(userId: userId, communityId: communityId)
        .snapshots()
        .map((s) => s)
        .asyncMap(_convertMembershipAsync);
  }

  Future<Membership> getMembership({required String communityId}) async {
    final doc = await membershipsReference(
      userId: userService.currentUserId!,
      communityId: communityId,
    ).get();

    return _convertMembership(doc.data() ?? {}).copyWith(communityId: doc.id);
  }

  static Future<List<Membership>> _convertMembershipListAsync(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final memberships = <Membership>[];
    for (final doc in docs) {
      try {
        // Web runs [compute] on the main isolate anyway; parsing here avoids
        // edge-case failures with isolate / transfer of Firestore map payloads.
        // Subcollection path is `.../community-membership/{communityDocId}` — that
        // id is canonical; the `communityId` field in the map can drift.
        if (kIsWeb) {
          memberships.add(
            _convertMembership(doc.data()).copyWith(communityId: doc.id),
          );
        } else {
          final m = await compute(_convertMembership, doc.data());
          memberships.add(m.copyWith(communityId: doc.id));
        }
      } catch (e, st) {
        loggingService.log(
          'FirestoreMembershipService: skipped invalid membership doc ${doc.id}',
          logType: LogType.warning,
          error: e,
          stackTrace: st,
        );
      }
    }
    return memberships;
  }

  static Future<Membership?> _convertMembershipAsync(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final docData = doc.data();
    if (docData == null) return null;

    final membership = await compute<Map<String, dynamic>, Membership>(
      _convertMembership,
      docData,
    );
    return membership.copyWith(communityId: doc.id);
  }

  static Membership _convertMembership(Map<String, dynamic> data) {
    return Membership.fromJson(fromFirestoreJson(data));
  }
}
