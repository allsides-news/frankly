#!/usr/bin/env node

/**
 * Diagnostic script to check if recording is properly configured for an event
 * 
 * Usage: node scripts/check-recording-config.js <eventPath>
 * Example: node scripts/check-recording-config.js communities/abc123/templates/xyz789/events/event456
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp();
}

const firestore = admin.firestore();

async function checkRecordingConfig() {
  const eventPath = process.argv[2];
  
  if (!eventPath) {
    console.error('❌ Error: Please provide event path');
    console.error('Usage: node scripts/check-recording-config.js <eventPath>');
    console.error('Example: node scripts/check-recording-config.js communities/abc123/templates/xyz789/events/event456');
    process.exit(1);
  }

  console.log('🔍 Checking recording configuration for:', eventPath);
  console.log('');

  try {
    // 1. Check event document
    console.log('📄 Step 1: Checking event document...');
    const eventDoc = await firestore.doc(eventPath).get();
    
    if (!eventDoc.exists) {
      console.error('❌ Event not found at path:', eventPath);
      process.exit(1);
    }

    const event = eventDoc.data();
    console.log('✅ Event found:', event.title || 'Untitled');
    console.log('   Event Type:', event.eventType);
    console.log('   Event ID:', eventDoc.id);
    console.log('');

    // 2. Check eventSettings.alwaysRecord
    console.log('📹 Step 2: Checking recording settings...');
    const alwaysRecord = event.eventSettings?.alwaysRecord ?? false;
    
    if (alwaysRecord) {
      console.log('✅ Recording is ENABLED (alwaysRecord: true)');
    } else {
      console.log('❌ Recording is DISABLED (alwaysRecord: false)');
      console.log('   ⚠️  This is why recording isn\'t working!');
      console.log('');
      console.log('   Fix: In the event settings UI, toggle "Record" to ON and save.');
      console.log('');
    }

    // 3. Check live meeting
    console.log('📡 Step 3: Checking live meeting...');
    const liveMeetingPath = `${eventPath}/live-meetings/${eventDoc.id}`;
    const liveMeetingDoc = await firestore.doc(liveMeetingPath).get();
    
    if (liveMeetingDoc.exists) {
      const liveMeeting = liveMeetingDoc.data();
      console.log('✅ Live meeting exists');
      console.log('   Meeting ID:', liveMeeting.meetingId);
      console.log('   Record field:', liveMeeting.record ?? false);
      console.log('');
    } else {
      console.log('   ℹ️  No live meeting yet (event hasn\'t started)');
      console.log('');
    }

    // 4. Check breakout rooms
    console.log('🚪 Step 4: Checking breakout rooms...');
    const breakoutSessionsSnapshot = await firestore
      .collection(`${liveMeetingPath}/breakout-room-sessions`)
      .orderBy('breakoutRoomSessionId', 'desc')
      .limit(1)
      .get();

    if (breakoutSessionsSnapshot.empty) {
      console.log('   ℹ️  No breakout sessions yet');
      console.log('');
    } else {
      const sessionDoc = breakoutSessionsSnapshot.docs[0];
      const sessionId = sessionDoc.id;
      console.log('✅ Found breakout session:', sessionId);
      
      const breakoutRoomsSnapshot = await firestore
        .collection(`${liveMeetingPath}/breakout-room-sessions/${sessionId}/breakout-rooms`)
        .get();

      console.log(`   Found ${breakoutRoomsSnapshot.size} breakout room(s)`);
      console.log('');

      breakoutRoomsSnapshot.docs.forEach((roomDoc, index) => {
        const room = roomDoc.data();
        const recordStatus = room.record ? '✅ TRUE' : '❌ FALSE';
        console.log(`   Room ${index + 1}: ${room.roomName}`);
        console.log(`     Room ID: ${room.roomId}`);
        console.log(`     Record: ${recordStatus}`);
        console.log(`     Participants: ${room.participantIds?.length || 0}`);
        
        if (!room.record) {
          console.log(`     ⚠️  This room won't be recorded!`);
        }
        console.log('');
      });

      // Check recording states
      console.log('📊 Step 5: Checking recording states...');
      for (const roomDoc of breakoutRoomsSnapshot.docs) {
        const room = roomDoc.data();
        const recordingStatePath = `${liveMeetingPath}/breakout-room-sessions/${sessionId}/breakout-rooms/${roomDoc.id}/live-meetings/${room.roomId}/recording-state/current`;
        
        const recordingStateDoc = await firestore.doc(recordingStatePath).get();
        
        if (recordingStateDoc.exists) {
          const state = recordingStateDoc.data();
          console.log(`   Room ${room.roomName} recording state:`);
          console.log(`     Status: ${state.status}`);
          console.log(`     File Prefix: ${state.filePrefix}`);
          console.log(`     Started: ${state.startedAt?.toDate()}`);
          if (state.status === 'recording') {
            console.log(`     ✅ Recording in progress`);
          } else if (state.status === 'error') {
            console.log(`     ❌ Recording error: ${state.error}`);
          }
          console.log('');
        } else {
          console.log(`   Room ${room.roomName}: No recording state (not started yet)`);
        }
      }
    }

    // 5. Summary
    console.log('');
    console.log('=' .repeat(60));
    console.log('📋 SUMMARY');
    console.log('=' .repeat(60));
    
    if (!alwaysRecord) {
      console.log('❌ ISSUE FOUND: Recording is disabled on this event');
      console.log('');
      console.log('   Action Required:');
      console.log('   1. Open event settings in the UI');
      console.log('   2. Toggle "Record" to ON');
      console.log('   3. Click "Save Settings"');
      console.log('   4. If breakouts already exist, end session and create new one');
      console.log('');
    } else {
      console.log('✅ Event recording is enabled');
      
      if (breakoutSessionsSnapshot.empty) {
        console.log('   ℹ️  Create breakout rooms to test');
      } else {
        const allRoomsHaveRecord = breakoutSessionsSnapshot.docs.every(doc => {
          return doc.data().record === true;
        });
        
        if (allRoomsHaveRecord) {
          console.log('✅ All breakout rooms have recording enabled');
          console.log('   ℹ️  Recording should work when users join');
        } else {
          console.log('❌ Some breakout rooms have recording disabled');
          console.log('   Action: End session and create new breakout rooms');
        }
      }
    }
    
    console.log('');

  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

checkRecordingConfig();

