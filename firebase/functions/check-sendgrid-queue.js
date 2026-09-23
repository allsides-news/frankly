#!/usr/bin/env node
/**
 * Check sendgridmail collection for emails related to specific events
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();

async function checkSendgridQueue(eventIds) {
  console.log(`🔍 Checking sendgridmail for events: ${eventIds.join(', ')}\n`);
  
  // Get recent emails from sendgridmail
  const emailsSnap = await db.collection('sendgridmail')
    .limit(500)
    .get();
  
  console.log(`📊 Total emails in sendgridmail: ${emailsSnap.size}\n`);
  
  const emailsByEvent = {};
  eventIds.forEach(id => {
    emailsByEvent[id] = [];
  });
  
  emailsSnap.docs.forEach(doc => {
    const data = doc.data();
    const subject = data.message?.subject || '';
    const html = data.message?.html || '';
    
    // Check if email is for one of our events
    eventIds.forEach(eventId => {
      if (html.includes(eventId) || subject.includes('Carmel')) {
        const delivery = data.delivery || {};
        const to = Array.isArray(data.to) ? data.to : [data.to];
        
        emailsByEvent[eventId].push({
          id: doc.id,
          to: to[0],
          subject,
          state: delivery.state || 'PENDING',
          startTime: delivery.startTime?.toDate(),
          error: delivery.error
        });
      }
    });
  });
  
  // Show results
  eventIds.forEach(eventId => {
    const emails = emailsByEvent[eventId];
    console.log('━'.repeat(80));
    console.log(`📧 Event: ${eventId}`);
    console.log(`   Emails found: ${emails.length}\n`);
    
    if (emails.length === 0) {
      console.log('❌ No emails found for this event in sendgridmail collection!');
      console.log('   This means the joinEvent function never created email documents.\n');
    } else {
      emails.forEach((email, idx) => {
        const icon = email.state === 'SUCCESS' ? '✅' : 
                     email.state === 'ERROR' ? '❌' : 
                     email.state === 'PROCESSING' ? '🔄' : '⏳';
        
        console.log(`${idx + 1}. ${icon} To: ${email.to}`);
        console.log(`   Subject: ${email.subject}`);
        console.log(`   Status: ${email.state}`);
        if (email.startTime) {
          console.log(`   Time: ${email.startTime.toLocaleString()}`);
        }
        if (email.error) {
          console.log(`   Error: ${email.error.substring(0, 100)}`);
        }
        console.log('');
      });
    }
  });
  
  console.log('━'.repeat(80));
  console.log('\n💡 Summary:\n');
  
  eventIds.forEach(eventId => {
    const emails = emailsByEvent[eventId];
    const successCount = emails.filter(e => e.state === 'SUCCESS').length;
    const errorCount = emails.filter(e => e.state === 'ERROR').length;
    const pendingCount = emails.filter(e => !e.state || e.state === 'PENDING').length;
    
    console.log(`Event ${eventId}:`);
    console.log(`  Total emails: ${emails.length}`);
    console.log(`  ✅ Delivered: ${successCount}`);
    console.log(`  ❌ Failed: ${errorCount}`);
    console.log(`  ⏳ Pending: ${pendingCount}\n`);
  });
  
  // Check if joinEvent function exists
  console.log('━'.repeat(80));
  console.log('🔍 Diagnostics:\n');
  
  eventIds.forEach(eventId => {
    const emails = emailsByEvent[eventId];
    if (emails.length === 0) {
      console.log(`⚠️  Event ${eventId}: NO emails in queue`);
      console.log('   Possible causes:');
      console.log('   1. joinEvent cloud function is not being triggered');
      console.log('   2. joinEvent function is failing silently');
      console.log('   3. Email reminders are disabled for this event');
      console.log('   4. Users are not marked as "active" participants\n');
    }
  });
}

const eventIds = process.argv.slice(2);

if (eventIds.length === 0) {
  console.error('Usage: node check-sendgrid-queue.js EVENT_ID [EVENT_ID2 ...]');
  console.error('Example: node check-sendgrid-queue.js ogAEK1GIW8l8bOnqFu5g iKfOOvm1UuLLSUcDLPF6');
  process.exit(1);
}

checkSendgridQueue(eventIds)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
