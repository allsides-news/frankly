#!/usr/bin/env node

/**
 * Verification script for recording deduplication fix
 * 
 * This script checks an event's recording state documents to verify:
 * 1. Each breakout room has exactly one recording
 * 2. Recording states are properly claimed and transitioned
 * 3. No duplicate Agora resource IDs or SIDs
 * 
 * Usage:
 *   node scripts/verify-recording-deduplication.js <eventId>
 * 
 * Example:
 *   node scripts/verify-recording-deduplication.js vE2yOWVQUXHfLqpZ7imP
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}

const firestore = admin.firestore();

async function verifyRecordingDeduplication(eventId) {
  console.log('🔍 Verifying Recording Deduplication');
  console.log('=' .repeat(60));
  console.log(`Event ID: ${eventId}`);
  console.log('');

  try {
    // Find the event document
    const eventsSnapshot = await firestore
      .collectionGroup('events')
      .where(admin.firestore.FieldPath.documentId(), '==', eventId)
      .get();

    if (eventsSnapshot.empty) {
      console.error('❌ Event not found');
      process.exit(1);
    }

    const eventDoc = eventsSnapshot.docs[0];
    const eventPath = eventDoc.ref.path;
    const liveMeetingPath = `${eventPath}/live-meetings/${eventId}`;
    
    console.log(`Event path: ${eventPath}`);
    console.log('');

    // Check main room recording
    console.log('📹 MAIN ROOM RECORDING');
    console.log('-'.repeat(60));
    const mainRoomStatePath = `${liveMeetingPath}/recording-state/current`;
    const mainRoomState = await firestore.doc(mainRoomStatePath).get();
    
    if (mainRoomState.exists) {
      displayRecordingState('Main Room', mainRoomState.data());
    } else {
      console.log('  No recording state found (may not have started yet)');
    }
    console.log('');

    // Check breakout room recordings
    console.log('📹 BREAKOUT ROOM RECORDINGS');
    console.log('-'.repeat(60));
    
    const sessionsSnapshot = await firestore
      .collection(`${liveMeetingPath}/breakout-room-sessions`)
      .get();

    if (sessionsSnapshot.empty) {
      console.log('  No breakout sessions found');
      console.log('');
      console.log('✅ Verification complete (no breakouts to check)');
      return;
    }

    let totalRooms = 0;
    let roomsWithRecording = 0;
    let roomsWithMultipleRecordings = 0;
    const recordingDetails = [];
    const resourceIds = new Set();
    const sids = new Set();
    const claimIds = new Set();

    for (const sessionDoc of sessionsSnapshot.docs) {
      console.log(`\n  Session: ${sessionDoc.id}`);
      
      const roomsSnapshot = await firestore
        .collection(`${liveMeetingPath}/breakout-room-sessions/${sessionDoc.id}/breakout-rooms`)
        .get();

      for (const roomDoc of roomsSnapshot.docs) {
        totalRooms++;
        const roomId = roomDoc.id;
        const roomData = roomDoc.data();
        const roomName = roomData.roomName || roomId;
        
        console.log(`\n    Room: ${roomName} (${roomId})`);
        
        // Check recording state
        const statePath = `${liveMeetingPath}/breakout-room-sessions/${sessionDoc.id}/breakout-rooms/${roomId}/live-meetings/${roomId}/recording-state/current`;
        const stateDoc = await firestore.doc(statePath).get();
        
        if (stateDoc.exists) {
          roomsWithRecording++;
          const state = stateDoc.data();
          displayRecordingState(`      ${roomName}`, state);
          
          // Track for duplicate detection
          recordingDetails.push({
            room: roomName,
            roomId: roomId,
            state: state,
          });
          
          if (state.resourceId) resourceIds.add(state.resourceId);
          if (state.sid) sids.add(state.sid);
          if (state.claimId) claimIds.add(state.claimId);
        } else {
          console.log('      No recording state found');
        }
      }
    }

    // Summary
    console.log('');
    console.log('📊 SUMMARY');
    console.log('=' .repeat(60));
    console.log(`Total breakout rooms: ${totalRooms}`);
    console.log(`Rooms with recording state: ${roomsWithRecording}`);
    console.log(`Unique resource IDs: ${resourceIds.size}`);
    console.log(`Unique SIDs: ${sids.size}`);
    console.log(`Unique claim IDs: ${claimIds.size}`);
    console.log('');

    // Duplicate detection
    console.log('🔍 DUPLICATE DETECTION');
    console.log('-'.repeat(60));
    
    // Check for duplicate resource IDs or SIDs (indicates duplicate recordings)
    const resourceIdMap = new Map();
    const sidMap = new Map();
    
    recordingDetails.forEach(detail => {
      if (detail.state.resourceId) {
        if (!resourceIdMap.has(detail.state.resourceId)) {
          resourceIdMap.set(detail.state.resourceId, []);
        }
        resourceIdMap.get(detail.state.resourceId).push(detail.room);
      }
      
      if (detail.state.sid) {
        if (!sidMap.has(detail.state.sid)) {
          sidMap.set(detail.state.sid, []);
        }
        sidMap.get(detail.state.sid).push(detail.room);
      }
    });

    let hasDuplicates = false;

    resourceIdMap.forEach((rooms, resourceId) => {
      if (rooms.length > 1) {
        console.log(`❌ Duplicate resource ID found: ${resourceId}`);
        console.log(`   Used by rooms: ${rooms.join(', ')}`);
        hasDuplicates = true;
      }
    });

    sidMap.forEach((rooms, sid) => {
      if (rooms.length > 1) {
        console.log(`❌ Duplicate SID found: ${sid}`);
        console.log(`   Used by rooms: ${rooms.join(', ')}`);
        hasDuplicates = true;
      }
    });

    if (!hasDuplicates) {
      console.log('✅ No duplicate recordings detected');
      console.log('   Each breakout room has a unique recording');
    }
    console.log('');

    // Claim analysis
    console.log('🎯 CLAIM ANALYSIS');
    console.log('-'.repeat(60));
    
    const claimingCount = recordingDetails.filter(d => d.state.status === 'claiming').length;
    const recordingCount = recordingDetails.filter(d => d.state.status === 'recording').length;
    const errorCount = recordingDetails.filter(d => d.state.status === 'error').length;
    const staleCount = recordingDetails.filter(d => {
      const claimedAt = d.state.claimedAt?.toDate();
      if (!claimedAt) return false;
      const ageMinutes = (Date.now() - claimedAt.getTime()) / 1000 / 60;
      return ageMinutes > 2 && d.state.status === 'claiming';
    }).length;

    console.log(`Claims by status:`);
    console.log(`  claiming: ${claimingCount}${staleCount > 0 ? ` (${staleCount} stale)` : ''}`);
    console.log(`  recording: ${recordingCount}`);
    console.log(`  error: ${errorCount}`);
    console.log('');

    if (claimingCount > 0) {
      console.log('⚠️  Some claims still in "claiming" state');
      if (staleCount > 0) {
        console.log('   Some claims are stale (> 2 minutes old) - may need cleanup');
      } else {
        console.log('   This is normal if recordings just started');
      }
    }

    if (errorCount > 0) {
      console.log('⚠️  Some recordings failed to start');
      console.log('   Check error details above for more info');
    }
    console.log('');

    // Final verdict
    console.log('🏁 FINAL VERDICT');
    console.log('=' .repeat(60));
    
    if (hasDuplicates) {
      console.log('❌ FAILED: Duplicate recordings detected');
      console.log('   The deduplication system may not be working correctly');
    } else if (roomsWithRecording === totalRooms && recordingCount === totalRooms) {
      console.log('✅ PASSED: All breakout rooms have exactly one unique recording');
      console.log('   The deduplication system is working correctly');
    } else if (roomsWithRecording < totalRooms) {
      console.log('⚠️  INCOMPLETE: Not all rooms have recordings yet');
      console.log('   Wait for more users to join or recordings to start');
    } else {
      console.log('⚠️  UNCERTAIN: System state is ambiguous');
      console.log('   Review the details above for more information');
    }
    console.log('');

  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error.stack);
    process.exit(1);
  }
}

function displayRecordingState(label, state) {
  console.log(`    ${label}:`);
  console.log(`      Status: ${state.status || 'unknown'}`);
  
  if (state.claimId) {
    console.log(`      Claim ID: ${state.claimId}`);
  }
  
  if (state.claimedBy) {
    console.log(`      Claimed by: ${state.claimedBy}`);
  }
  
  if (state.claimedAt) {
    const claimedAt = state.claimedAt.toDate();
    const ageSeconds = Math.floor((Date.now() - claimedAt.getTime()) / 1000);
    console.log(`      Claimed at: ${claimedAt.toISOString()} (${ageSeconds}s ago)`);
  }
  
  if (state.startedAt) {
    const startedAt = state.startedAt.toDate();
    const ageSeconds = Math.floor((Date.now() - startedAt.getTime()) / 1000);
    console.log(`      Started at: ${startedAt.toISOString()} (${ageSeconds}s ago)`);
  }
  
  if (state.resourceId) {
    console.log(`      Resource ID: ${state.resourceId}`);
  }
  
  if (state.sid) {
    console.log(`      SID: ${state.sid}`);
  }
  
  if (state.filePrefix) {
    console.log(`      File prefix: ${state.filePrefix}`);
  }
  
  if (state.error) {
    console.log(`      Error: ${state.error}`);
  }
  
  if (state.previousError) {
    console.log(`      Previous error: ${state.previousError}`);
  }
}

// Main execution
const eventId = process.argv[2];

if (!eventId) {
  console.error('Usage: node verify-recording-deduplication.js <eventId>');
  console.error('');
  console.error('Example:');
  console.error('  node verify-recording-deduplication.js vE2yOWVQUXHfLqpZ7imP');
  process.exit(1);
}

verifyRecordingDeduplication(eventId);

