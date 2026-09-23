# Presence Detection in Events

How presence detection works for users in event waiting rooms and breakout rooms.

## Architecture Overview

The app uses a **two-layer presence system** combining Firebase Realtime Database (for connection state) and Firestore (for meeting presence and room assignments).

---

## Layer 1: Connection Detection (Firebase Realtime Database)

**Client setup:** `client/lib/features/user/data/services/user_data_service.dart`

When a user logs in, the app writes their status to Realtime Database at `/status/{userId}`. Firebase's `.info/connected` path detects the real connection state, and an `onDisconnect()` handler is registered so Firebase automatically marks the user offline if they lose their connection for any reason.

**Possible states:** `online` / `offline`, each with a `last_changed` server timestamp.

**Backend handler:** `firebase/functions/lib/events/live_meetings/update_presence_status.dart`

- Listens for changes at `/status/{uid}`
- When a user goes offline, queries all active `event-participants` docs for that user and sets `isPresent: false`
- Also clears `currentBreakoutRoomId` on disconnect

---

## Layer 2: Meeting Presence Heartbeat (Firestore)

**Location:** `client/lib/features/events/features/live_meeting/data/providers/live_meeting_provider.dart`

While a participant is in a meeting, the client sends a heartbeat **every 5 seconds**:

```dart
_presenceUpdater = Timer.periodic(Duration(seconds: 5), (_) {
  final currentBreakoutRoomId = eventProvider.selfParticipant?.currentBreakoutRoomId;

  firestoreLiveMeetingService.updateMeetingPresence(
    event: eventProvider.event,
    currentBreakoutRoomId: currentBreakoutRoomId,
    isPresent: true,
  );
});
```

**What each heartbeat writes to the participant's `event-participants` doc:**

| Field | Value |
|---|---|
| `isPresent` | `true` |
| `currentBreakoutRoomId` | Current room ID, or `null` if in main meeting |
| `membershipStatus` | User's community membership role |
| `lastUpdatedTime` | Server timestamp |
| `mostRecentPresentTime` | Server timestamp |

**Implementation:** `FirestoreLiveMeetingService.updateMeetingPresence()` in `client/lib/features/events/features/live_meeting/data/services/firestore_live_meeting_service.dart`

---

## Participant Count Aggregation (Cloud Function)

**Location:** `firebase/functions/lib/events/live_meetings/update_live_stream_participant_count.dart`

A scheduled Cloud Function runs **every minute** and internally performs **4 sub-runs spaced 15 seconds apart**, giving an effective resolution of every ~15 seconds.

Each run:
1. Checks for active/upcoming livestream events in the next 24 hours
2. Finds participants with `lastUpdatedTime` in the last ~19 seconds (15s interval + 4s buffer)
3. Counts all active participants and those with `isPresent: true`
4. Writes `presentParticipantCountEstimate` and `participantCountEstimate` back to the event document

The ~19-second window ensures no heartbeats are missed since clients write every 5 seconds.

---

## Breakout Room Tracking

### Participant assignment

When a breakout session starts, the `AssignToBreakouts` cloud function creates `BreakoutRoom` documents and populates their `participantIds` array. This array represents **original assignment** — who was placed in this room when the session started.

### Tracking current location (source of truth for admin UI)

Each participant's `currentBreakoutRoomId` field, updated every 5 seconds by the heartbeat, reflects which room they are **actively present** in. This field is cleared to `null`/`''` whenever someone leaves a room or disconnects:

- **Voluntary leave** — `leaveBreakoutRoom()` calls `updateMeetingPresence(isPresent: true)` with no `currentBreakoutRoomId` → clears the field
- **RTDB disconnect** — `UpdatePresenceStatus` cloud function sets `currentBreakoutRoomId: ''` when the Firebase connection drops

The admin panel uses `breakoutRoomParticipantsStream()` (which queries by `currentBreakoutRoomId`) as the source of truth for displaying who is in a room:

```dart
// FirestoreLiveMeetingService.breakoutRoomParticipantsStream()
.where('currentBreakoutRoomId', isEqualTo: breakoutRoomId)
```

> **Why not `participantIds`?** `BreakoutRoom.participantIds` is never automatically cleaned up when a user leaves or disconnects — it is only updated by explicit `ReassignBreakoutRoom` calls. Using it directly in the UI produces "ghost participants" who are listed in a room even after they have left or lost their connection.

### Moving between rooms

Moves are handled by the `ReassignBreakoutRoom` cloud function, which updates the `participantIds` arrays on the relevant `BreakoutRoom` documents transactionally.

---

## Waiting Room Monitoring

**Service:** `client/lib/features/events/features/live_meeting/data/services/waiting_room_notification_service.dart`

The waiting room is a special breakout room (`breakoutsWaitingRoomId`). The service subscribes to its Firestore document as a real-time stream and watches the `participantIds` array for changes. No polling is used — updates arrive via Firestore listener.

When the meeting has started and users are in the waiting room, admins (hosts and facilitators) receive a persistent toast notification.

---

## Breakout Room Help Requests

**Service:** `client/lib/features/events/features/live_meeting/data/services/breakout_room_help_notification_service.dart`

Subscribes to a real-time Firestore stream filtered by `flagStatus == needsHelp`. When any breakout room sets this flag, admins receive a persistent toast notification. No polling.

---

## Summary of Polling Frequencies

| Mechanism | Frequency | Purpose |
|---|---|---|
| **Client heartbeat** | Every **5 seconds** | Updates `isPresent` and `currentBreakoutRoomId` |
| **Participant count aggregation** | Every **~15 seconds** | Counts present participants for event documents |
| **Waiting room monitoring** | **Real-time** (Firestore stream) | Notifies admins when users enter the waiting room |
| **Breakout help requests** | **Real-time** (Firestore stream) | Notifies admins when a room flags for help |
| **Connection status** | **Event-driven** | Firebase Realtime Database `onDisconnect()` handler |
| **Event end check** | Every **10 seconds** | Auto-leaves meeting when event time expires |

---

## Key Files

### Client

| File | Role |
|---|---|
| `client/lib/features/events/features/live_meeting/data/providers/live_meeting_provider.dart` | Sets up presence heartbeat timer and notification services |
| `client/lib/features/events/features/live_meeting/data/services/firestore_live_meeting_service.dart` | Writes presence/room data to Firestore; provides room streams |
| `client/lib/features/user/data/services/user_data_service.dart` | Sets up Realtime Database connection monitoring on login |
| `client/lib/features/events/features/live_meeting/data/services/waiting_room_notification_service.dart` | Streams waiting room participant list; notifies admins |
| `client/lib/features/events/features/live_meeting/data/services/breakout_room_help_notification_service.dart` | Streams help-flagged breakout rooms; notifies admins |

### Cloud Functions

| File | Role |
|---|---|
| `firebase/functions/lib/events/live_meetings/update_presence_status.dart` | Marks participants offline on Realtime Database disconnect |
| `firebase/functions/lib/events/live_meetings/update_live_stream_participant_count.dart` | Aggregates present participant counts every ~15 seconds |
| `firebase/functions/lib/events/live_meetings/breakouts/assign_to_breakouts.dart` | Creates breakout rooms and assigns participants |
| `firebase/functions/lib/events/live_meetings/breakouts/reassign_breakout_room.dart` | Moves a participant between breakout rooms |
