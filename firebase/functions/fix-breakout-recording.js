#!/usr/bin/env node
/**
 * Emergency script to enable recording on all breakout rooms for a live event
 * Usage: node fix-breakout-recording.js EVENT_ID
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();

async function fixBreakoutRecording(eventId) {
  console.log(`🔍 Fixing breakout recording for event: ${eventId}`);
  
  // Use the known path from logs
  const eventPath = 'community/qXIP0FcTFBQbrYdmgeeI/templates/Xg1wS3qetUSuycm1bzAw/events/EZaxq3dlf7fb8tWhxkmC';
  console.log(`📍 Using event path: ${eventPath}`);
  
  // Get the live meeting
  const liveMeetingPath = `${eventPath}/live-meetings/${eventId}`;
  const liveMeetingDoc = await db.doc(liveMeetingPath).get();
  
  if (!liveMeetingDoc.exists) {
    console.error('❌ Live meeting not found!');
    process.exit(1);
  }
  
  const liveMeeting = liveMeetingDoc.data();
  const currentSession = liveMeeting.currentBreakoutSession;
  
  if (!currentSession) {
    console.error('❌ No current breakout session!');
    process.exit(1);
  }
  
  console.log(`✅ Current breakout session: ${currentSession.breakoutRoomSessionId}`);
  console.log(`   Status: ${currentSession.breakoutRoomStatus}`);
  
  // Get all breakout rooms in the current session
  const breakoutRoomsPath = `${liveMeetingPath}/breakout-room-sessions/${currentSession.breakoutRoomSessionId}/breakout-rooms`;
  const breakoutRoomsSnapshot = await db.collection(breakoutRoomsPath).get();
  
  console.log(`\n📊 Found ${breakoutRoomsSnapshot.size} breakout rooms\n`);
  
  let needsUpdate = 0;
  let alreadyRecording = 0;
  
  // Check each room
  for (const roomDoc of breakoutRoomsSnapshot.docs) {
    const roomData = roomDoc.data();
    const roomName = roomData.roomName || roomDoc.id;
    const isRecording = roomData.record === true;
    
    if (isRecording) {
      console.log(`✅ Room "${roomName}" (${roomDoc.id}): record = true`);
      alreadyRecording++;
    } else {
      console.log(`❌ Room "${roomName}" (${roomDoc.id}): record = ${roomData.record} ← NEEDS FIX`);
      needsUpdate++;
    }
  }
  
  console.log(`\n📈 Summary:`);
  console.log(`   Already recording: ${alreadyRecording}`);
  console.log(`   Need update: ${needsUpdate}`);
  
  if (needsUpdate === 0) {
    console.log('\n✅ All breakout rooms already have recording enabled!');
    process.exit(0);
  }
  
  // Ask for confirmation
  console.log(`\n⚠️  About to update ${needsUpdate} breakout rooms to enable recording.`);
  console.log(`   This will enable recordings when participants join these rooms.`);
  console.log(`\n   Press Ctrl+C to cancel, or wait 5 seconds to proceed...`);
  
  await new Promise(resolve => setTimeout(resolve, 5000));
  
  console.log(`\n🔧 Updating breakout rooms...`);
  
  // Update rooms that need it
  const batch = db.batch();
  let updated = 0;
  
  for (const roomDoc of breakoutRoomsSnapshot.docs) {
    const roomData = roomDoc.data();
    if (roomData.record !== true) {
      batch.update(roomDoc.ref, { record: true });
      updated++;
      console.log(`   Updating "${roomData.roomName || roomDoc.id}"...`);
    }
  }
  
  await batch.commit();
  
  console.log(`\n✅ SUCCESS! Updated ${updated} breakout rooms.`);
  console.log(`   Recordings will now start when participants join these rooms.`);
  console.log(`\n📝 NOTE: Participants who are already IN breakout rooms need to:`);
  console.log(`   - Leave and rejoin the room, OR`);
  console.log(`   - Wait for a new participant to join (which will trigger recording)`);
}

const eventId = process.argv[2];

if (!eventId) {
  console.error('Usage: node fix-breakout-recording.js EVENT_ID');
  console.error('Example: node fix-breakout-recording.js EZaxq3dlf7fb8tWhxkmC');
  process.exit(1);
}

fixBreakoutRecording(eventId)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });

