#!/usr/bin/env node
/**
 * Check if a user is registered for a specific event and whether email was sent
 * Usage: node check-event-participant.js EMAIL EVENT_ID
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();
const auth = admin.auth();

async function checkEventParticipant(emailAddress, eventId) {
  console.log(`🔍 Checking if ${emailAddress} is registered for event ${eventId}...\n`);
  
  // Find user by email
  let user;
  try {
    user = await auth.getUserByEmail(emailAddress);
    console.log(`✅ Found user: ${user.uid}`);
    console.log(`   Email: ${user.email}`);
    console.log(`   Display Name: ${user.displayName || 'Not set'}\n`);
  } catch (e) {
    console.log(`❌ No user found with email: ${emailAddress}`);
    console.log(`   This email is not registered in Firebase Auth.\n`);
    return;
  }
  
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
  console.log(`   Community: ${eventData.communityId}\n`);
  
  // Check if user is a participant
  const participantDoc = await db.doc(`${eventPath}/event-participants/${user.uid}`).get();
  
  if (!participantDoc.exists) {
    console.log(`❌ ${emailAddress} is NOT registered for this event.`);
    console.log(`   No participant document found.\n`);
    return;
  }
  
  const participantData = participantDoc.data();
  console.log(`✅ ${emailAddress} IS registered for this event!`);
  console.log(`   Status: ${participantData.status}`);
  console.log(`   Joined: ${participantData.createdDate?.toDate() || 'Unknown'}\n`);
  
  // Check event settings for email reminders
  const reminderEnabled = eventData.eventSettings?.reminderEmails;
  console.log(`📧 Email Settings:`);
  console.log(`   Reminder emails enabled: ${reminderEnabled !== false ? 'YES ✅' : 'NO ❌'}\n`);
  
  // Look for emails sent to this user for this event
  console.log(`🔎 Searching for emails sent to ${emailAddress}...`);
  
  const emailsSnap = await db.collection('sendgridmail')
    .where('to', 'array-contains', emailAddress)
    .limit(100)
    .get();
  
  console.log(`   Found ${emailsSnap.size} total emails to this address\n`);
  
  const eventTitle = eventData.title || '';
  const relatedEmails = [];
  
  emailsSnap.docs.forEach(doc => {
    const data = doc.data();
    const subject = data.message?.subject || '';
    
    // Check if subject mentions this event
    if (subject.includes(eventTitle) || 
        subject.includes('Registration Confirmation')) {
      const delivery = data.delivery || {};
      relatedEmails.push({
        subject,
        state: delivery.state || 'PENDING',
        startTime: delivery.startTime?.toDate(),
        id: doc.id
      });
    }
  });
  
  if (relatedEmails.length > 0) {
    console.log(`✅ Found ${relatedEmails.length} emails for this event:\n`);
    relatedEmails.forEach((email, idx) => {
      const icon = email.state === 'SUCCESS' ? '✅' : 
                   email.state === 'ERROR' ? '❌' : '⏳';
      console.log(`${idx + 1}. ${icon} ${email.subject}`);
      console.log(`   Status: ${email.state}`);
      console.log(`   Time: ${email.startTime || 'Unknown'}\n`);
    });
  } else {
    console.log(`❌ No emails found for this event!`);
    console.log(`\n🔍 Why no email was sent:`);
    
    if (participantData.status !== 'active') {
      console.log(`   ⚠️  Participant status is "${participantData.status}" (not "active")`);
      console.log(`      Emails only sent to active participants.`);
    } else if (reminderEnabled === false) {
      console.log(`   ⚠️  Email reminders are DISABLED for this event`);
      console.log(`      Event setting: reminderEmails = false`);
    } else {
      console.log(`   ⚠️  Unknown reason - check function logs for errors`);
      console.log(`      User is active, reminders enabled, but no email sent.`);
    }
  }
}

const emailAddress = process.argv[2];
const eventId = process.argv[3];

if (!emailAddress || !eventId) {
  console.error('Usage: node check-event-participant.js EMAIL EVENT_ID');
  console.error('Example: node check-event-participant.js emily@allsides.com 3tBC3hQbazfQoe8inQQS');
  process.exit(1);
}

checkEventParticipant(emailAddress, eventId)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });

