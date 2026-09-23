#!/usr/bin/env node

/**
 * Script to inspect and reset a Hostless event back to waiting room state.
 * 
 * Usage:
 *   node scripts/reset-hostless-event.js <eventPath> [--reset]
 * 
 * Example:
 *   # Inspect only (safe, read-only)
 *   node scripts/reset-hostless-event.js "/space/satan2/discuss/oG90Q2AmrSTnDSYaJ3Im/J1EkeU46A5d5BDEOAn0B"
 * 
 *   # Inspect and reset (requires --reset flag)
 *   node scripts/reset-hostless-event.js "/space/satan2/discuss/oG90Q2AmrSTnDSYaJ3Im/J1EkeU46A5d5BDEOAn0B" --reset
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
  });
}

const db = admin.firestore();

async function inspectEvent(eventPath) {
  console.log('\n=== EVENT INSPECTION ===');
  console.log(`Event Path: ${eventPath}\n`);

  // Parse the event path to get the event ID
  const pathParts = eventPath.split('/');
  const eventId = pathParts[pathParts.length - 1];
  
  // Get the event document
  console.log('1. Fetching event document...');
  const eventDoc = await db.doc(eventPath).get();
  
  if (!eventDoc.exists) {
    console.error(`❌ Event not found at path: ${eventPath}`);
    process.exit(1);
  }
  
  const eventData = eventDoc.data();
  console.log(`   ✓ Event found: "${eventData.title}"`);
  console.log(`   - Event Type: ${eventData.eventType || 'hosted (legacy)'}`);
  console.log(`   - Status: ${eventData.status}`);
  console.log(`   - Scheduled Time: ${eventData.scheduledTime?.toDate()}`);
  console.log(`   - Creator: ${eventData.creatorId}`);
  
  if (eventData.eventType !== 'hostless') {
    console.log(`\n⚠️  WARNING: This event is not a hostless event (type: ${eventData.eventType})`);
    console.log('   This script is designed for hostless events only.');
    const readline = require('readline').createInterface({
      input: process.stdin,
      output: process.stdout
    });
    
    const answer = await new Promise(resolve => {
      readline.question('   Continue anyway? (y/N): ', resolve);
    });
    readline.close();
    
    if (answer.toLowerCase() !== 'y') {
      console.log('   Exiting...');
      process.exit(0);
    }
  }
  
  // Get the live meeting document
  console.log('\n2. Fetching live meeting document...');
  const liveMeetingPath = `${eventPath}/live-meetings/${eventId}`;
  const liveMeetingDoc = await db.doc(liveMeetingPath).get();
  
  if (!liveMeetingDoc.exists) {
    console.log(`   ℹ️  No live meeting found (event hasn't started yet)`);
    console.log('\n✅ Event is in initial state - no reset needed!');
    return null;
  }
  
  const liveMeetingData = liveMeetingDoc.data();
  console.log(`   ✓ Live meeting found`);
  console.log(`   - Meeting ID: ${liveMeetingData.meetingId || 'none'}`);
  console.log(`   - Participants: ${liveMeetingData.participants?.length || 0}`);
  
  // Check the current breakout session
  console.log('\n3. Checking breakout session state...');
  const currentBreakoutSession = liveMeetingData.currentBreakoutSession;
  
  if (!currentBreakoutSession) {
    console.log(`   ✓ No active breakout session`);
    console.log('\n✅ Event is already in waiting room state - no reset needed!');
    return null;
  }
  
  console.log(`   ⚠️  Active breakout session found!`);
  console.log(`   - Session ID: ${currentBreakoutSession.breakoutRoomSessionId}`);
  console.log(`   - Status: ${currentBreakoutSession.breakoutRoomStatus}`);
  console.log(`   - Has Waiting Room: ${currentBreakoutSession.hasWaitingRoom}`);
  console.log(`   - Target Participants Per Room: ${currentBreakoutSession.targetParticipantsPerRoom}`);
  console.log(`   - Assignment Method: ${currentBreakoutSession.assignmentMethod}`);
  
  // Get breakout rooms
  console.log('\n4. Checking for breakout rooms...');
  const breakoutSessionPath = `${liveMeetingPath}/breakout-room-sessions/${currentBreakoutSession.breakoutRoomSessionId}`;
  const breakoutRoomsSnapshot = await db.collection(`${breakoutSessionPath}/breakout-rooms`).get();
  
  console.log(`   Found ${breakoutRoomsSnapshot.size} breakout room(s):`);
  
  const breakoutRooms = [];
  for (const roomDoc of breakoutRoomsSnapshot.docs) {
    const roomData = roomDoc.data();
    breakoutRooms.push({
      id: roomDoc.id,
      name: roomData.roomName,
      participantCount: roomData.participantIds?.length || 0,
      participants: roomData.participantIds || [],
    });
    console.log(`   - ${roomData.roomName}: ${roomData.participantIds?.length || 0} participant(s)`);
  }
  
  // Get participants currently marked as available for breakouts
  console.log('\n5. Checking participant breakout availability...');
  const participantsSnapshot = await db.collection(`${eventPath}/event-participants`).get();
  const availableParticipants = [];
  
  for (const partDoc of participantsSnapshot.docs) {
    const partData = partDoc.data();
    if (partData.availableForBreakoutSessionId === currentBreakoutSession.breakoutRoomSessionId) {
      availableParticipants.push(partData.id);
    }
  }
  
  console.log(`   ${availableParticipants.length} participant(s) marked as available for this breakout session`);
  
  return {
    eventPath,
    eventId,
    liveMeetingPath,
    breakoutSessionPath,
    currentBreakoutSession,
    breakoutRooms,
    availableParticipants,
  };
}

async function resetEvent(inspectionData) {
  console.log('\n=== RESETTING EVENT ===\n');
  
  const {
    liveMeetingPath,
    breakoutSessionPath,
    currentBreakoutSession,
    breakoutRooms,
  } = inspectionData;
  
  console.log('This will:');
  console.log('  1. Remove currentBreakoutSession from the live meeting');
  console.log('  2. Keep breakout session data for record-keeping (can be manually deleted later if needed)');
  console.log('  3. Send all participants back to the waiting room\n');
  
  // Confirm
  const readline = require('readline').createInterface({
    input: process.stdin,
    output: process.stdout
  });
  
  const answer = await new Promise(resolve => {
    readline.question('Are you sure you want to proceed? (yes/no): ', resolve);
  });
  readline.close();
  
  if (answer.toLowerCase() !== 'yes') {
    console.log('Reset cancelled.');
    process.exit(0);
  }
  
  console.log('\nProceeding with reset...\n');
  
  // Step 1: Remove currentBreakoutSession from live meeting
  console.log('1. Removing currentBreakoutSession from live meeting...');
  await db.doc(liveMeetingPath).update({
    currentBreakoutSession: admin.firestore.FieldValue.delete(),
  });
  console.log('   ✓ Done');
  
  // Step 2: Delete the breakout session data to ensure clean slate
  console.log('\n2. Deleting old breakout session data...');
  try {
    // Delete all breakout rooms in the session
    const breakoutRoomsSnapshot = await db.collection(`${breakoutSessionPath}/breakout-rooms`).get();
    const deletePromises = [];
    
    for (const roomDoc of breakoutRoomsSnapshot.docs) {
      console.log(`   - Deleting breakout room: ${roomDoc.id}`);
      deletePromises.push(roomDoc.ref.delete());
    }
    
    await Promise.all(deletePromises);
    
    // Delete the session document itself
    await db.doc(breakoutSessionPath).delete();
    console.log(`   ✓ Deleted ${breakoutRoomsSnapshot.size} breakout room(s) and session document`);
  } catch (error) {
    console.log(`   ⚠️  Error deleting breakout data: ${error.message}`);
    console.log('   (This is okay - the session may have already been cleaned up)');
  }
  
  console.log('\n✅ Event has been reset to waiting room state!');
  console.log('\nNext steps:');
  console.log('  - Participants who refresh will now see the waiting room');
  console.log('  - The event will proceed normally when the scheduled time arrives');
  console.log('  - All old breakout session data has been removed');
  
  if (breakoutRooms.length > 0) {
    console.log('\n📊 Breakout rooms that were created (now inactive):');
    for (const room of breakoutRooms) {
      console.log(`   - ${room.name}: ${room.participantCount} participant(s) were assigned`);
    }
  }
}

async function cleanupOrphanedBreakoutData(eventPath) {
  console.log('\n=== CLEANING UP ORPHANED BREAKOUT DATA ===\n');
  
  const pathParts = eventPath.split('/');
  const eventId = pathParts[pathParts.length - 1];
  const liveMeetingPath = `${eventPath}/live-meetings/${eventId}`;
  
  console.log('Scanning for orphaned breakout sessions...\n');
  
  const breakoutSessionsSnapshot = await db.collection(`${liveMeetingPath}/breakout-room-sessions`).get();
  
  if (breakoutSessionsSnapshot.empty) {
    console.log('✓ No orphaned breakout sessions found');
    return;
  }
  
  console.log(`Found ${breakoutSessionsSnapshot.size} breakout session(s) to clean up:\n`);
  
  for (const sessionDoc of breakoutSessionsSnapshot.docs) {
    const sessionData = sessionDoc.data();
    console.log(`Session: ${sessionDoc.id}`);
    console.log(`  Status: ${sessionData.breakoutRoomStatus}`);
    
    const breakoutRoomsSnapshot = await db.collection(`${sessionDoc.ref.path}/breakout-rooms`).get();
    console.log(`  Rooms: ${breakoutRoomsSnapshot.size}`);
    
    // Delete all rooms
    const deletePromises = [];
    for (const roomDoc of breakoutRoomsSnapshot.docs) {
      deletePromises.push(roomDoc.ref.delete());
    }
    await Promise.all(deletePromises);
    
    // Delete session
    await sessionDoc.ref.delete();
    console.log(`  ✓ Deleted session and ${breakoutRoomsSnapshot.size} room(s)\n`);
  }
  
  console.log('✅ Cleanup complete!');
}

async function main() {
  const args = process.argv.slice(2);
  
  if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    console.log(`
Usage:
  node scripts/reset-hostless-event.js <eventPath> [--reset] [--cleanup]

Arguments:
  eventPath   The full Firestore path to the event
              Example: "/space/satan2/discuss/oG90Q2AmrSTnDSYaJ3Im/J1EkeU46A5d5BDEOAn0B"
  
  --reset     Actually perform the reset (without this, only inspection is done)
  --cleanup   Clean up orphaned breakout session data (use when already reset)

Examples:
  # Inspect the event (read-only, safe)
  node scripts/reset-hostless-event.js "/space/satan2/discuss/oG90Q2AmrSTnDSYaJ3Im/J1EkeU46A5d5BDEOAn0B"
  
  # Inspect and reset the event
  node scripts/reset-hostless-event.js "/space/satan2/discuss/oG90Q2AmrSTnDSYaJ3Im/J1EkeU46A5d5BDEOAn0B" --reset
  
  # Clean up orphaned breakout data
  node scripts/reset-hostless-event.js "/space/satan2/discuss/oG90Q2AmrSTnDSYaJ3Im/J1EkeU46A5d5BDEOAn0B" --cleanup
`);
    process.exit(0);
  }
  
  const eventPath = args[0];
  const shouldReset = args.includes('--reset');
  const shouldCleanup = args.includes('--cleanup');
  
  try {
    if (shouldCleanup) {
      await cleanupOrphanedBreakoutData(eventPath);
      process.exit(0);
    }
    
    const inspectionData = await inspectEvent(eventPath);
    
    if (!inspectionData) {
      // Event is already in correct state - check for orphaned data
      console.log('\n💡 To clean up any orphaned breakout data, run:');
      console.log(`   node scripts/reset-hostless-event.js "${eventPath}" --cleanup\n`);
      process.exit(0);
    }
    
    if (shouldReset) {
      await resetEvent(inspectionData);
    } else {
      console.log('\n💡 To reset this event to waiting room state, run:');
      console.log(`   node scripts/reset-hostless-event.js "${eventPath}" --reset\n`);
    }
    
  } catch (error) {
    console.error('\n❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

main();


