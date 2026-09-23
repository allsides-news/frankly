/**
 * Check email logs and event data for troubleshooting
 */

const admin = require('firebase-admin');

// Initialize with default database
process.env.FIRESTORE_DATABASE_ID = '';

admin.initializeApp({
  projectId: 'allsides-roundtables'
});

const db = admin.firestore();

async function checkEventEmails() {
  const eventId = 'gbXhA6qrccAQocIGRURX';
  const communityId = 'gh6jl9ZPOsETSxSacFV7';
  const templateId = 'ZM41a1GZ0KuqF3dwpTyR';
  
  console.log('=== Checking SendGrid Email Queue ===\n');
  try {
    const sendgridSnap = await db.collection('sendgridmail').limit(10).get();
    console.log(`📧 Found ${sendgridSnap.size} emails in sendgridmail queue`);
    if (sendgridSnap.size > 0) {
      sendgridSnap.forEach(doc => {
        const data = doc.data();
        console.log(`  - To: ${data.to?.[0] || 'unknown'}`);
        console.log(`    Subject: ${data.message?.subject || 'none'}`);
        console.log('');
      });
    } else {
      console.log('  ✓ Queue is empty (good - emails were processed)\n');
    }
  } catch (error) {
    console.error('  ❌ Error:', error.message);
  }

  console.log('=== Checking Event Data ===\n');
  try {
    const eventPath = `community/${communityId}/templates/${templateId}/events/${eventId}`;
    const eventDoc = await db.doc(eventPath).get();
    
    if (eventDoc.exists) {
      const event = eventDoc.data();
      console.log(`📅 Event: ${event.name}`);
      console.log(`  Status: ${event.status}`);
      console.log(`  Reminder emails: ${event.eventSettings?.reminderEmails ?? 'undefined (defaults to true)'}`);
      console.log(`  Has pre-event CTA: ${!!event.preEventCardData}`);
      if (event.preEventCardData) {
        console.log(`  CTA Headline: ${event.preEventCardData.headline || '(empty)'}`);
        console.log(`  CTA Message: ${(event.preEventCardData.message || '(empty)').substring(0, 100)}...`);
      }
      console.log('');
    } else {
      console.log('  ❌ Event not found!\n');
    }
  } catch (error) {
    console.error('  ❌ Error:', error.message);
  }

  console.log('=== Checking Email Logs ===\n');
  try {
    const logsPath = `community/${communityId}/templates/${templateId}/events/${eventId}/email-logs`;
    const logsSnap = await db.collection(logsPath).get();
    console.log(`📨 Found ${logsSnap.size} email log entries`);
    
    if (logsSnap.size > 0) {
      logsSnap.forEach(doc => {
        const log = doc.data();
        console.log(`  - ${log.eventEmailType} sent to user ${log.userId}`);
        console.log(`    Send ID: ${log.sendId || 'none'}`);
      });
    } else {
      console.log('  ❌ No emails were sent for this event!');
    }
    console.log('');
  } catch (error) {
    console.error('  ❌ Error:', error.message);
  }

  console.log('=== Checking Participants ===\n');
  try {
    const partsPath = `community/${communityId}/templates/${templateId}/events/${eventId}/event-participants`;
    const partsSnap = await db.collection(partsPath).get();
    console.log(`👥 Found ${partsSnap.size} participants`);
    
    if (partsSnap.size > 0) {
      partsSnap.forEach(doc => {
        const part = doc.data();
        console.log(`  - User ${doc.id}: status=${part.status}`);
      });
    } else {
      console.log('  ⚠️  No participants found!');
    }
    console.log('');
  } catch (error) {
    console.error('  ❌ Error:', error.message);
  }

  console.log('=== Checking Community Settings ===\n');
  try {
    const communityDoc = await db.doc(`community/${communityId}`).get();
    if (communityDoc.exists) {
      const community = communityDoc.data();
      console.log(`🏢 Community: ${community.name}`);
      console.log(`  Event reminder emails (migration): ${community.eventSettingsMigration?.reminderEmails ?? 'undefined'}`);
      console.log('');
    }
  } catch (error) {
    console.error('  ❌ Error:', error.message);
  }
}

checkEventEmails()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('\n❌ Fatal Error:', error);
    process.exit(1);
  });
