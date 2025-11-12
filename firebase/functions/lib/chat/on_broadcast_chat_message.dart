import 'dart:async';

import 'package:firebase_admin_interop/firebase_admin_interop.dart';
import 'package:firebase_functions_interop/firebase_functions_interop.dart'
    show EventContext, Change, RuntimeOptions;
import '../on_firestore_function.dart';
import '../utils/infra/firestore_event_function.dart';
import '../utils/infra/firestore_utils.dart';
import '../utils/infra/on_firestore_helper.dart';
import 'package:data_models/cloud_functions/requests.dart';

/// Firestore trigger for main meeting chat messages with broadcast: true
class OnBroadcastChatMessage extends OnFirestoreFunction<SerializeableRequest> {
  OnBroadcastChatMessage()
      : super(
          [
            AppFirestoreFunctionData(
              'ChatMessageOnCreate',
              FirestoreEventType.onCreate,
            ),
          ],
          (snapshot) => SerializeableRequest(),
        );

  @override
  String get documentPath =>
      'community/{communityId}/templates/{templateId}/events/{eventId}/chats/{chatId}/messages/{messageId}';

  @override
  Future<void> onCreate(
    DocumentSnapshot documentSnapshot,
    SerializeableRequest parsedData,
    DateTime updateTime,
    EventContext context,
  ) async {
    final messageData = documentSnapshot.data.toMap();
    
    // Only process broadcast messages
    final broadcast = messageData['broadcast'] as bool?;
    if (broadcast != true) {
      print('Message is not a broadcast, skipping replication');
      return;
    }

    // Skip if this is already a replicated message (to prevent infinite loops)
    final isReplicated = messageData['isReplicatedBroadcast'] as bool?;
    if (isReplicated == true) {
      print('Message is already a replicated broadcast, skipping to prevent duplicates');
      return;
    }

    print('Processing broadcast message: ${documentSnapshot.reference.path}');

    // Extract path parameters
    final params = context.params;
    final communityId = params['communityId'];
    final templateId = params['templateId'];
    final eventId = params['eventId'];

    print('Broadcast message from main meeting chat');

    // Find all active breakout rooms for this event
    final liveMeetingPath =
        'community/$communityId/templates/$templateId/events/$eventId/live-meetings';
    final liveMeetingSnapshot = await firestore.collection(liveMeetingPath).get();

    if (liveMeetingSnapshot.documents.isEmpty) {
      print('No active live meeting found');
      return;
    }

    final liveMeetingId = liveMeetingSnapshot.documents.first.documentID;
    final liveMeeting = liveMeetingSnapshot.documents.first;
    final currentBreakoutSession = liveMeeting.data.toMap()['currentBreakoutSession'];

    if (currentBreakoutSession == null || currentBreakoutSession is! Map) {
      print('No active breakout session found');
      return;
    }

    final breakoutSessionId = currentBreakoutSession['breakoutRoomSessionId'] as String?;
    if (breakoutSessionId == null) {
      print('No breakout session ID found');
      return;
    }

    // Query the breakout rooms collection
    final breakoutRoomsPath = '$liveMeetingPath/$liveMeetingId/breakout-room-sessions/$breakoutSessionId/breakout-rooms';
    print('Querying breakout rooms at: $breakoutRoomsPath');
    
    final breakoutRoomsSnapshot = await firestore.collection(breakoutRoomsPath).get();
    
    if (breakoutRoomsSnapshot.documents.isEmpty) {
      print('No active breakout rooms found');
      return;
    }

    print('Found ${breakoutRoomsSnapshot.documents.length} breakout rooms, replicating message...');

    // Create message data without the Firestore-generated ID
    final replicatedMessageData = DocumentData.fromMap({
      'message': messageData['message'],
      'creatorId': messageData['creatorId'],
      'messageStatus': messageData['messageStatus'],
      'broadcast': true,
      'isReplicatedBroadcast': true,  // Prevent infinite replication loops
      'messageType': messageData['messageType'],
      'membershipStatusSnapshot': messageData['membershipStatusSnapshot'],
    });

    // Set timestamp
    if (messageData['createdDate'] is Timestamp) {
      replicatedMessageData.setTimestamp(
        'createdDate',
        messageData['createdDate'] as Timestamp,
      );
    } else {
      replicatedMessageData.setTimestamp(
        'createdDate',
        Timestamp.fromDateTime(DateTime.now()),
      );
    }

    // Replicate to all breakout rooms
    for (final roomDoc in breakoutRoomsSnapshot.documents) {
      final breakoutRoomId = roomDoc.documentID;
      final breakoutChatPath =
          '$liveMeetingPath/$liveMeetingId/breakout-room-sessions/$breakoutSessionId/breakout-rooms/$breakoutRoomId/live-meetings/$breakoutRoomId/chats/community_chat/messages';

      try {
        await firestore.collection(breakoutChatPath).add(replicatedMessageData);
        print('Replicated broadcast message to breakout room: $breakoutRoomId');
      } catch (e) {
        print('Error replicating to breakout room $breakoutRoomId: $e');
      }
    }

    print('Completed replicating broadcast message to all breakout rooms');
  }

  @override
  Future<void> onUpdate(
    Change<DocumentSnapshot> changes,
    SerializeableRequest before,
    SerializeableRequest after,
    DateTime updateTime,
    EventContext context,
  ) async {
    // Not needed for broadcast messages
  }

  @override
  Future<void> onWrite(
    Change<DocumentSnapshot> changes,
    SerializeableRequest before,
    SerializeableRequest after,
    DateTime updateTime,
    EventContext context,
  ) async {
    // Not needed for broadcast messages
  }

  @override
  Future<void> onDelete(
    DocumentSnapshot documentSnapshot,
    SerializeableRequest parsedData,
    DateTime updateTime,
    EventContext context,
  ) async {
    // Not needed for broadcast messages
  }
}

/// Firestore trigger for breakout room chat messages with broadcast: true
class OnBreakoutBroadcastChatMessage extends OnFirestoreFunction<SerializeableRequest> {
  OnBreakoutBroadcastChatMessage()
      : super(
          [
            AppFirestoreFunctionData(
              'BreakoutChatMessageOnCreate',
              FirestoreEventType.onCreate,
            ),
          ],
          (snapshot) => SerializeableRequest(),
        );

  @override
  String get documentPath =>
      'community/{communityId}/templates/{templateId}/events/{eventId}/live-meetings/{liveMeetingId}/breakout-room-sessions/{breakoutSessionId}/breakout-rooms/{breakoutRoomId}/live-meetings/{liveMeetingId2}/chats/{chatId}/messages/{messageId}';

  @override
  Future<void> onCreate(
    DocumentSnapshot documentSnapshot,
    SerializeableRequest parsedData,
    DateTime updateTime,
    EventContext context,
  ) async {
    print('OnBreakoutBroadcastChatMessage triggered! Path: ${documentSnapshot.reference.path}');
    
    final messageData = documentSnapshot.data.toMap();
    print('Message data keys: ${messageData.keys.toList()}');
    print('Broadcast value: ${messageData['broadcast']}');
    
    // Only process broadcast messages
    final broadcast = messageData['broadcast'] as bool?;
    if (broadcast != true) {
      print('Message is not a broadcast, skipping replication');
      return;
    }

    // Skip if this is already a replicated message (to prevent infinite loops)
    final isReplicated = messageData['isReplicatedBroadcast'] as bool?;
    if (isReplicated == true) {
      print('Message is already a replicated broadcast, skipping to prevent duplicates');
      return;
    }

    print('Processing broadcast message from breakout room: ${documentSnapshot.reference.path}');

    // Extract path parameters
    final params = context.params;
    final communityId = params['communityId'];
    final templateId = params['templateId'];
    final eventId = params['eventId'];
    final liveMeetingId = params['liveMeetingId'];
    final breakoutSessionId = params['breakoutSessionId'];
    final sourceBreakoutRoomId = params['breakoutRoomId'];

    print('Broadcast message from breakout room: $sourceBreakoutRoomId');

    final liveMeetingPath =
        'community/$communityId/templates/$templateId/events/$eventId/live-meetings';

    // Create message data
    final replicatedMessageData = DocumentData.fromMap({
      'message': messageData['message'],
      'creatorId': messageData['creatorId'],
      'messageStatus': messageData['messageStatus'],
      'broadcast': true,
      'isReplicatedBroadcast': true,  // Prevent infinite replication loops
      'messageType': messageData['messageType'],
      'membershipStatusSnapshot': messageData['membershipStatusSnapshot'],
    });

    if (messageData['createdDate'] is Timestamp) {
      replicatedMessageData.setTimestamp(
        'createdDate',
        messageData['createdDate'] as Timestamp,
      );
    } else {
      replicatedMessageData.setTimestamp(
        'createdDate',
        Timestamp.fromDateTime(DateTime.now()),
      );
    }

    // 1. Replicate to main meeting chat
    final eventChatPath = 'community/$communityId/templates/$templateId/events/$eventId/chats/community_chat/messages';
    try {
      await firestore.collection(eventChatPath).add(replicatedMessageData);
      print('Replicated broadcast message to main meeting chat');
    } catch (e) {
      print('Error replicating to main meeting: $e');
    }

    // 2. Replicate to all OTHER breakout rooms (not the source room)
    // Query the breakout rooms collection
    final breakoutRoomsPath = '$liveMeetingPath/$liveMeetingId/breakout-room-sessions/$breakoutSessionId/breakout-rooms';
    print('Querying breakout rooms at: $breakoutRoomsPath');
    
    final breakoutRoomsSnapshot = await firestore.collection(breakoutRoomsPath).get();
    print('Found ${breakoutRoomsSnapshot.documents.length} breakout rooms');
    
    for (final roomDoc in breakoutRoomsSnapshot.documents) {
      final breakoutRoomId = roomDoc.documentID;
      
      // Skip the source room
      if (breakoutRoomId == sourceBreakoutRoomId) {
        print('Skipping source breakout room: $breakoutRoomId');
        continue;
      }
      
      final breakoutChatPath = '$liveMeetingPath/$liveMeetingId/breakout-room-sessions/$breakoutSessionId/breakout-rooms/$breakoutRoomId/live-meetings/$breakoutRoomId/chats/community_chat/messages';
      
      try {
        await firestore.collection(breakoutChatPath).add(replicatedMessageData);
        print('Replicated broadcast message to breakout room: $breakoutRoomId');
      } catch (e) {
        print('Error replicating to breakout room $breakoutRoomId: $e');
      }
    }

    print('Completed replicating breakout broadcast message to all rooms');
  }

  @override
  Future<void> onUpdate(
    Change<DocumentSnapshot> changes,
    SerializeableRequest before,
    SerializeableRequest after,
    DateTime updateTime,
    EventContext context,
  ) async {
    // Not needed
  }

  @override
  Future<void> onWrite(
    Change<DocumentSnapshot> changes,
    SerializeableRequest before,
    SerializeableRequest after,
    DateTime updateTime,
    EventContext context,
  ) async {
    // Not needed
  }

  @override
  Future<void> onDelete(
    DocumentSnapshot documentSnapshot,
    SerializeableRequest parsedData,
    DateTime updateTime,
    EventContext context,
  ) async {
    // Not needed
  }
}

