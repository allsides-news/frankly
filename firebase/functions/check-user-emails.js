#!/usr/bin/env node
/**
 * Check all emails sent to a specific user
 * Usage: node check-user-emails.js EMAIL_ADDRESS [HOURS_BACK]
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();

async function checkUserEmails(emailAddress, hoursBack = 48) {
  console.log(`🔍 Searching for emails to: ${emailAddress}`);
  console.log(`   Looking back: ${hoursBack} hours\n`);
  
  const cutoffTime = new Date(Date.now() - hoursBack * 60 * 60 * 1000);
  
  // Query emails sent to this address (no orderBy to avoid index requirement)
  const emailsSnap = await db.collection('sendgridmail')
    .where('to', 'array-contains', emailAddress)
    .limit(100)
    .get();
  
  console.log(`📊 Found ${emailsSnap.size} emails total to this address\n`);
  
  if (emailsSnap.empty) {
    console.log('❌ No emails found for this address.');
    console.log('   Possible reasons:');
    console.log('   - User never registered for any events');
    console.log('   - Email address is incorrect');
    console.log('   - Emails are older than the query limit');
    return;
  }
  
  const recentEmails = [];
  const stats = {
    total: emailsSnap.size,
    registration: 0,
    reminder: 0,
    other: 0,
    delivered: 0,
    pending: 0,
    failed: 0
  };
  
  emailsSnap.docs.forEach(doc => {
    const data = doc.data();
    const delivery = data.delivery || {};
    const subject = data.message?.subject || 'No subject';
    const startTime = delivery.startTime?.toDate();
    
    // Filter to emails within time range
    if (!startTime || startTime < cutoffTime) return;
    
    // Categorize by subject
    if (subject.includes('Registration Confirmation')) {
      stats.registration++;
    } else if (subject.includes('Starting in')) {
      stats.reminder++;
    } else {
      stats.other++;
    }
    
    // Track delivery status
    if (delivery.state === 'SUCCESS') {
      stats.delivered++;
    } else if (!delivery.state || delivery.state === 'PENDING') {
      stats.pending++;
    } else if (delivery.state === 'ERROR') {
      stats.failed++;
    }
    
    recentEmails.push({
      id: doc.id,
      subject,
      state: delivery.state || 'PENDING',
      startTime,
      endTime: delivery.endTime?.toDate(),
      error: delivery.error,
      from: data.from,
      messageId: delivery.info?.messageId
    });
  });
  
  console.log('📈 Email Summary (last ' + hoursBack + ' hours):');
  console.log('━'.repeat(60));
  console.log(`   📧 Registration Confirmations: ${stats.registration}`);
  console.log(`   ⏰ Event Reminders: ${stats.reminder}`);
  console.log(`   📨 Other: ${stats.other}`);
  console.log('');
  console.log(`   ✅ Delivered: ${stats.delivered}`);
  console.log(`   ⏳ Pending: ${stats.pending}`);
  console.log(`   ❌ Failed: ${stats.failed}`);
  console.log('━'.repeat(60));
  
  if (recentEmails.length > 0) {
    console.log(`\n📋 Recent Emails (showing ${Math.min(20, recentEmails.length)}):\n`);
    
    recentEmails.slice(0, 20).forEach((email, idx) => {
      const timeAgo = email.startTime ? 
        `${Math.round((Date.now() - email.startTime.getTime()) / 60000)} min ago` : 
        'unknown';
      
      const icon = email.state === 'SUCCESS' ? '✅' :
                   email.state === 'ERROR' ? '❌' :
                   email.state === 'PROCESSING' ? '🔄' : '⏳';
      
      console.log(`${idx + 1}. ${icon} ${email.subject}`);
      console.log(`   From: ${email.from || 'unknown'}`);
      console.log(`   Status: ${email.state}`);
      console.log(`   Time: ${timeAgo}`);
      if (email.messageId) {
        console.log(`   Message ID: ${email.messageId}`);
      }
      if (email.error) {
        console.log(`   ❌ Error: ${email.error.substring(0, 100)}`);
      }
      console.log('');
    });
  }
  
  // Specific filter for Registration Confirmations
  const registrationEmails = recentEmails.filter(e => 
    e.subject.includes('Registration Confirmation')
  );
  
  if (registrationEmails.length > 0) {
    console.log('━'.repeat(60));
    console.log(`🎫 Registration Confirmation Emails: ${registrationEmails.length}`);
    console.log('━'.repeat(60));
    registrationEmails.forEach((email, idx) => {
      const icon = email.state === 'SUCCESS' ? '✅' : '❌';
      const timeStr = email.startTime?.toLocaleString() || 'unknown';
      console.log(`${idx + 1}. ${icon} ${email.subject}`);
      console.log(`   Sent: ${timeStr}`);
      console.log(`   Status: ${email.state}`);
      console.log('');
    });
  } else {
    console.log('\n⚠️  No registration confirmation emails found!');
    console.log('   This could mean:');
    console.log('   - User never registered for events in this time period');
    console.log('   - Emails are older than ' + hoursBack + ' hours');
  }
}

const emailAddress = process.argv[2];
const hoursBack = parseInt(process.argv[3]) || 48;

if (!emailAddress) {
  console.error('Usage: node check-user-emails.js EMAIL_ADDRESS [HOURS_BACK]');
  console.error('Example: node check-user-emails.js julie@allsides.com 72');
  process.exit(1);
}

checkUserEmails(emailAddress, hoursBack)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });

