#!/usr/bin/env node
/**
 * Show all recent registration emails to see what's actually being sent
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();

async function findRecentRegistrations(hours = 24) {
  console.log(`🔍 Finding all registration confirmation emails (last ${hours} hours)...\n`);
  
  // Get recent emails (can't filter by subject without index, so get all recent)
  const cutoffTime = new Date(Date.now() - hours * 60 * 60 * 1000);
  const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoffTime);
  
  // Query by delivery.startTime to get recent ones
  let emailsSnap;
  try {
    emailsSnap = await db.collection('sendgridmail')
      .where('delivery.startTime', '>', cutoffTimestamp)
      .limit(200)
      .get();
  } catch (e) {
    // If index doesn't exist, fall back to getting all and filtering
    console.log('Note: Using fallback query (no index for delivery.startTime)\n');
    emailsSnap = await db.collection('sendgridmail')
      .limit(200)
      .get();
  }
  
  console.log(`📊 Retrieved ${emailsSnap.size} recent email documents\n`);
  
  const registrationEmails = [];
  
  emailsSnap.docs.forEach(doc => {
    const data = doc.data();
    const subject = data.message?.subject || '';
    const delivery = data.delivery || {};
    const startTime = delivery.startTime?.toDate();
    
    // Filter to registration confirmations only
    if (subject.includes('Registration Confirmation')) {
      // Check if within time range
      if (!startTime || startTime < cutoffTime) return;
      
      const to = Array.isArray(data.to) ? data.to[0] : data.to;
      const state = delivery.state || 'PENDING';
      
      registrationEmails.push({
        to,
        subject,
        state,
        startTime,
        from: data.from,
        id: doc.id
      });
    }
  });
  
  console.log(`📧 Registration Confirmation Emails: ${registrationEmails.length}\n`);
  
  if (registrationEmails.length === 0) {
    console.log('❌ No registration confirmation emails found in this time period.');
    console.log('   Either no one registered, or emails are older than ' + hours + ' hours.');
    return;
  }
  
  // Sort by time (most recent first)
  registrationEmails.sort((a, b) => b.startTime - a.startTime);
  
  console.log('━'.repeat(80));
  console.log('Recent Registration Confirmations:');
  console.log('━'.repeat(80));
  
  registrationEmails.slice(0, 30).forEach((email, idx) => {
    const timeAgo = Math.round((Date.now() - email.startTime.getTime()) / 60000);
    const icon = email.state === 'SUCCESS' ? '✅' : 
                 email.state === 'ERROR' ? '❌' : '⏳';
    
    console.log(`${idx + 1}. ${icon} ${email.to}`);
    console.log(`   ${email.subject}`);
    console.log(`   Time: ${timeAgo} minutes ago`);
    console.log(`   Status: ${email.state}`);
    console.log('');
  });
  
  // Show unique email addresses
  const uniqueEmails = [...new Set(registrationEmails.map(e => e.to))];
  console.log('━'.repeat(80));
  console.log(`📊 Statistics:`);
  console.log(`   Total registration emails: ${registrationEmails.length}`);
  console.log(`   Unique recipients: ${uniqueEmails.length}`);
  console.log(`   Success rate: ${Math.round(registrationEmails.filter(e => e.state === 'SUCCESS').length / registrationEmails.length * 100)}%`);
  console.log('━'.repeat(80));
  
  // Check if julie@allsides.com is in the list
  const julieEmails = registrationEmails.filter(e => 
    e.to && e.to.toLowerCase().includes('julie')
  );
  
  if (julieEmails.length > 0) {
    console.log(`\n🎯 Found ${julieEmails.length} emails to Julie-related addresses:`);
    julieEmails.forEach(email => {
      console.log(`   - ${email.to} (${email.state})`);
    });
  } else {
    console.log(`\n⚠️  No emails found for julie@allsides.com`);
    console.log(`   This means Julie hasn't registered for any events recently,`);
    console.log(`   or is using a different email address.`);
  }
}

const hours = parseInt(process.argv[2]) || 24;

findRecentRegistrations(hours)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });

