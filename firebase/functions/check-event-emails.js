#!/usr/bin/env node
/**
 * Check all participants for an event to see if they received registration emails
 * Usage: node check-event-emails.js EVENT_ID
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();
const auth = admin.auth();

async function checkEventEmails(eventId) {
  console.log(`🔍 Checking emails for event: ${eventId}\n`);
  
  // Find the event
  const eventsQuery = await db.collectionGroup('events')
    .limit(500)
    .get();
  
  let eventDoc = null;
  let eventPath = null;
  
  for (const doc of eventsQuery.docs) {
    if (doc.id === eventId) {
      eventDoc = doc;
      eventPath = doc.ref.path;
      break;
    }
  }
  
  if (!eventDoc) {
    console.log(`❌ Event ${eventId} not found!`);
    return;
  }
  
  const eventData = eventDoc.data();
  console.log(`✅ Found event: ${eventData.title || 'Untitled'}`);
  console.log(`   Path: ${eventPath}`);
  console.log(`   Community: ${eventData.communityId}`);
  console.log(`   Scheduled: ${eventData.scheduledTime?.toDate() || 'Not scheduled'}\n`);
  
  // Get all participants
  const participantsSnap = await db.collection(`${eventPath}/event-participants`).get();
  console.log(`👥 Total participants: ${participantsSnap.size}\n`);
  
  if (participantsSnap.empty) {
    console.log('❌ No participants found for this event.');
    return;
  }
  
  // Get all email logs for this event
  const emailLogsSnap = await db.collection(`${eventPath}/email-logs`).get();
  const emailLogs = new Map();
  
  emailLogsSnap.docs.forEach(doc => {
    const data = doc.data();
    if (data.eventEmailType === 'initialSignUp') {
      emailLogs.set(data.userId, {
        type: data.eventEmailType,
        createdDate: data.createdDate?.toDate()
      });
    }
  });
  
  console.log(`📧 Email logs found: ${emailLogs.size}\n`);
  console.log('━'.repeat(80));
  console.log('Participant Email Status:\n');
  
  const stats = {
    total: 0,
    active: 0,
    emailSent: 0,
    emailMissing: 0,
    noEmail: 0
  };
  
  const missingEmails = [];
  
  for (const participantDoc of participantsSnap.docs) {
    const participantData = participantDoc.data();
    const userId = participantDoc.id;
    stats.total++;
    
    if (participantData.status === 'active') {
      stats.active++;
    }
    
    // Get user details
    let userEmail = 'unknown';
    try {
      const user = await auth.getUser(userId);
      userEmail = user.email || 'no-email';
    } catch (e) {
      userEmail = 'user-not-found';
    }
    
    if (userEmail === 'no-email') {
      stats.noEmail++;
    }
    
    // Check if email log exists
    const hasEmailLog = emailLogs.has(userId);
    
    if (hasEmailLog) {
      stats.emailSent++;
      const log = emailLogs.get(userId);
      console.log(`✅ ${userEmail}`);
      console.log(`   Status: ${participantData.status}`);
      console.log(`   Email sent: ${log.createdDate || 'Unknown'}\n`);
    } else {
      stats.emailMissing++;
      console.log(`❌ ${userEmail}`);
      console.log(`   Status: ${participantData.status}`);
      console.log(`   Email sent: NO - Missing email log!\n`);
      
      if (participantData.status === 'active' && userEmail !== 'no-email' && userEmail !== 'user-not-found') {
        missingEmails.push({
          userId,
          email: userEmail,
          status: participantData.status,
          joinedDate: participantData.createdDate?.toDate()
        });
      }
    }
  }
  
  console.log('━'.repeat(80));
  console.log('📊 Summary:\n');
  console.log(`   Total participants: ${stats.total}`);
  console.log(`   Active participants: ${stats.active}`);
  console.log(`   Registration emails sent: ${stats.emailSent}`);
  console.log(`   Missing registration emails: ${stats.emailMissing}`);
  console.log(`   Users without email address: ${stats.noEmail}`);
  console.log('━'.repeat(80));
  
  if (missingEmails.length > 0) {
    console.log('\n⚠️  USERS MISSING REGISTRATION EMAILS:\n');
    missingEmails.forEach((user, idx) => {
      console.log(`${idx + 1}. ${user.email}`);
      console.log(`   User ID: ${user.userId}`);
      console.log(`   Status: ${user.status}`);
      console.log(`   Joined: ${user.joinedDate || 'Unknown'}\n`);
    });
    
    console.log('💡 Recommendation:');
    console.log('   These users should receive registration confirmation emails.');
    console.log('   You can use the resend-event-emails.js script to send them.\n');
  } else {
    console.log('\n✅ All active participants have received registration emails!\n');
  }
}

const eventId = process.argv[2];

if (!eventId) {
  console.error('Usage: node check-event-emails.js EVENT_ID');
  console.error('Example: node check-event-emails.js ogAEK1GIW8l8bOnqFu5g');
  process.exit(1);
}

checkEventEmails(eventId)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
