#!/usr/bin/env node
/**
 * Check event settings to see if reminder emails are enabled
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();

async function checkEventSettings(eventId) {
  console.log(`🔍 Checking settings for event: ${eventId}\n`);
  
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
  console.log(`   Path: ${eventPath}\n`);
  
  console.log('━'.repeat(80));
  console.log('📋 Event Data:\n');
  console.log(`   Community ID: ${eventData.communityId}`);
  console.log(`   Template ID: ${eventData.templateId}`);
  console.log(`   Status: ${eventData.status}`);
  console.log(`   Scheduled Time: ${eventData.scheduledTime?.toDate() || 'Not set'}\n`);
  
  console.log('━'.repeat(80));
  console.log('📧 Email Settings:\n');
  
  const eventSettings = eventData.eventSettings || {};
  const reminderEmails = eventSettings.reminderEmails;
  
  console.log(`   eventSettings.reminderEmails: ${reminderEmails}`);
  
  if (reminderEmails === false) {
    console.log('\n❌ REMINDER EMAILS ARE DISABLED!');
    console.log('   This is why no emails were sent.\n');
  } else if (reminderEmails === true || reminderEmails === undefined) {
    console.log('\n✅ Reminder emails are ENABLED (or not explicitly disabled)');
    console.log('   Emails should have been sent.\n');
  }
  
  // Get community settings
  try {
    const communityDoc = await db.doc(`community/${eventData.communityId}`).get();
    const communityData = communityDoc.data();
    
    console.log('━'.repeat(80));
    console.log('🏘️  Community Settings:\n');
    console.log(`   Community Name: ${communityData.name}`);
    
    const communityReminderEmails = communityData.eventSettingsMigration?.reminderEmails;
    console.log(`   Community default reminderEmails: ${communityReminderEmails}\n`);
    
    if (reminderEmails === undefined && communityReminderEmails === false) {
      console.log('⚠️  Event inherits community setting: Emails DISABLED');
    }
  } catch (e) {
    console.log(`   Could not fetch community settings: ${e.message}`);
  }
  
  console.log('━'.repeat(80));
  console.log('👥 Participants Summary:\n');
  
  const participantsSnap = await db.collection(`${eventPath}/event-participants`).get();
  const activeCount = participantsSnap.docs.filter(doc => 
    doc.data().status === 'active'
  ).length;
  
  console.log(`   Total participants: ${participantsSnap.size}`);
  console.log(`   Active participants: ${activeCount}`);
  console.log(`   Inactive: ${participantsSnap.size - activeCount}\n`);
  
  console.log('━'.repeat(80));
  console.log('💡 Diagnosis:\n');
  
  if (reminderEmails === false || (reminderEmails === undefined && eventData.eventSettingsMigration?.reminderEmails === false)) {
    console.log('   ❌ Emails are DISABLED by event/community settings');
    console.log('   Solution: Enable reminderEmails in event settings\n');
  } else if (activeCount === 0) {
    console.log('   ❌ No ACTIVE participants');
    console.log('   Solution: Check participant status\n');
  } else {
    console.log('   ⚠️  Settings look correct, but emails were not sent');
    console.log('   Possible causes:');
    console.log('   1. joinEvent function was not triggered');
    console.log('   2. joinEvent function encountered an error');
    console.log('   3. Check Cloud Functions logs for errors\n');
  }
}

const eventId = process.argv[2];

if (!eventId) {
  console.error('Usage: node check-event-settings.js EVENT_ID');
  console.error('Example: node check-event-settings.js ogAEK1GIW8l8bOnqFu5g');
  process.exit(1);
}

checkEventSettings(eventId)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
