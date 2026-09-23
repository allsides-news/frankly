#!/usr/bin/env node

/**
 * Check if breakout rooms have recording enabled
 * 
 * Usage: 
 *   cd firebase/functions
 *   node ../../scripts/check-breakout-recording.js <eventPath>
 * 
 * Example:
 *   cd firebase/functions
 *   node ../../scripts/check-breakout-recording.js communities/abc/templates/xyz/events/123
 */

const admin = require('firebase-admin');

// Check if running from firebase/functions directory
const path = require('path');
const cwd = process.cwd();
if (!cwd.includes('firebase/functions')) {
  console.error('❌ Please run this script from the firebase/functions directory:');
  console.error('   cd firebase/functions');
  console.error('   node ../../scripts/check-breakout-recording.js <eventPath>');
  process.exit(1);
}

if (!admin.apps.length) {
  admin.initializeApp();
}

const firestore = admin.firestore();

async function checkBreakoutRecording() {
  const eventPath = process.argv[2];
  
  if (!eventPath) {
    console.error('Usage: node scripts/check-breakout-recording.js <eventPath>');
    console.error('Example: node scripts/check-breakout-recording.js communities/abc/templates/xyz/events/123');
    process.exit(1);
  }

  try {
    // Get event
    const eventDoc = await firestore.doc(eventPath).get();
    const event = eventDoc.data();
    const eventId = eventDoc.id;
    
    console.log('========================================');
    console.log('EVENT:', event.title || 'Untitled');
    console.log('========================================');
    console.log('Event ID:', eventId);
    console.log('Event Type:', event.eventType);
    console.log('alwaysRecord:', event.eventSettings?.alwaysRecord ?? false);
    console.log('');

    // Get main live meeting
    const liveMeetingPath = `${eventPath}/live-meetings/${eventId}`;
    const liveMeetingDoc = await firestore.doc(liveMeetingPath).get();
    
    console.log('========================================');
    console.log('MAIN ROOM');
    console.log('========================================');
    
    if (liveMeetingDoc.exists) {
      const liveMeeting = liveMeetingDoc.data();
      console.log('Meeting ID:', liveMeeting.meetingId);
      console.log('Record:', liveMeeting.record ?? false);
      console.log('');
    } else {
      console.log('No main room live meeting found');
      console.log('');
    }

    // Get breakout sessions
    const sessionsSnapshot = await firestore
      .collection(`${liveMeetingPath}/breakout-room-sessions`)
      .orderBy('breakoutRoomSessionId', 'desc')
      .get();

    if (sessionsSnapshot.empty) {
      console.log('No breakout sessions found');
      process.exit(0);
    }

    console.log('========================================');
    console.log('BREAKOUT ROOMS');
    console.log('========================================');

    for (const sessionDoc of sessionsSnapshot.docs) {
      const sessionId = sessionDoc.id;
      const session = sessionDoc.data();
      
      console.log(`\nSession: ${sessionId}`);
      console.log(`Status: ${session.breakoutRoomStatus}`);
      
      // Get rooms in this session
      const roomsSnapshot = await firestore
        .collection(`${liveMeetingPath}/breakout-room-sessions/${sessionId}/breakout-rooms`)
        .orderBy('orderingPriority')
        .get();

      console.log(`Found ${roomsSnapshot.size} rooms:\n`);

      for (const roomDoc of roomsSnapshot.docs) {
        const room = roomDoc.data();
        const recordIcon = room.record ? '✅' : '❌';
        
        console.log(`  ${recordIcon} Room ${room.roomName}`);
        console.log(`     ID: ${room.roomId}`);
        console.log(`     Record: ${room.record}`);
        console.log(`     Participants: ${room.participantIds?.length || 0}`);
        
        // Check if recording state exists
        const recordingStatePath = `${liveMeetingPath}/breakout-room-sessions/${sessionId}/breakout-rooms/${roomDoc.id}/live-meetings/${room.roomId}/recording-state/current`;
        const recordingStateDoc = await firestore.doc(recordingStatePath).get();
        
        if (recordingStateDoc.exists) {
          const state = recordingStateDoc.data();
          console.log(`     Recording State: ${state.status}`);
          console.log(`     File Prefix: ${state.filePrefix}`);
          console.log(`     Resource ID: ${state.resourceId}`);
          console.log(`     SID: ${state.sid}`);
        } else {
          console.log(`     Recording State: Not started`);
        }
        console.log('');
      }
    }

    // Summary
    console.log('\n========================================');
    console.log('DIAGNOSIS');
    console.log('========================================\n');

    const alwaysRecord = event.eventSettings?.alwaysRecord ?? false;
    
    if (!alwaysRecord) {
      console.log('❌ PROBLEM: Event has recording DISABLED');
      console.log('   Fix: Enable "Record" toggle in event settings\n');
    } else {
      console.log('✅ Event has recording ENABLED');
      
      // Check if any breakout rooms exist and their record status
      let hasBreakoutRooms = false;
      let allRoomsHaveRecord = true;
      
      for (const sessionDoc of sessionsSnapshot.docs) {
        const sessionId = sessionDoc.id;
        const roomsSnapshot = await firestore
          .collection(`${liveMeetingPath}/breakout-room-sessions/${sessionId}/breakout-rooms`)
          .get();
        
        if (roomsSnapshot.size > 0) {
          hasBreakoutRooms = true;
          roomsSnapshot.docs.forEach(roomDoc => {
            if (!roomDoc.data().record) {
              allRoomsHaveRecord = false;
            }
          });
        }
      }
      
      if (!hasBreakoutRooms) {
        console.log('   ℹ️  No breakout rooms created yet\n');
      } else if (!allRoomsHaveRecord) {
        console.log('❌ PROBLEM: Some breakout rooms have record: false');
        console.log('   This means they were created when recording was disabled');
        console.log('   or the functions have old code.\n');
        console.log('   Fix Option 1: Deploy the updated functions');
        console.log('     cd firebase/functions');
        console.log('     rm -rf build/');
        console.log('     npm run build');
        console.log('     firebase deploy --only functions\n');
        console.log('   Fix Option 2: Create new breakout session');
        console.log('     End current session and create a new one\n');
      } else {
        console.log('✅ All breakout rooms have recording enabled');
        console.log('   ℹ️  Check Firebase Function logs to see if recording started\n');
      }
    }

  } catch (error) {
    console.error('Error:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

checkBreakoutRecording();

