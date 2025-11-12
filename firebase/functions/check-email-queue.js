#!/usr/bin/env node
/**
 * Check the sendgridmail queue for stuck/pending emails
 * Shows delivery status and identifies problems
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();

async function checkEmailQueue() {
  console.log('🔍 Checking sendgridmail email queue...\n');
  
  // Get all emails from last 3 hours
  const threeHoursAgo = new Date(Date.now() - 3 * 60 * 60 * 1000);
  
  const allEmailsSnap = await db.collection('sendgridmail')
    .where('delivery.startTime', '>=', admin.firestore.Timestamp.fromDate(threeHoursAgo))
    .orderBy('delivery.startTime', 'desc')
    .limit(100)
    .get();
  
  console.log(`📊 Found ${allEmailsSnap.size} emails in last 3 hours\n`);
  
  const stats = {
    pending: 0,
    processing: 0,
    success: 0,
    error: 0,
    total: allEmailsSnap.size
  };
  
  const recentEmails = [];
  
  allEmailsSnap.docs.forEach(doc => {
    const data = doc.data();
    const delivery = data.delivery || {};
    const state = delivery.state;
    const startTime = delivery.startTime?.toDate();
    const subject = data.message?.subject || 'No subject';
    const to = Array.isArray(data.to) ? data.to[0] : data.to || 'unknown';
    
    if (!state) {
      stats.pending++;
      recentEmails.push({ state: 'PENDING', startTime, subject, to, id: doc.id });
    } else if (state === 'PROCESSING') {
      stats.processing++;
      recentEmails.push({ state: 'PROCESSING', startTime, subject, to, id: doc.id });
    } else if (state === 'SUCCESS') {
      stats.success++;
    } else if (state === 'ERROR') {
      stats.error++;
      const error = delivery.error || 'Unknown error';
      recentEmails.push({ state: 'ERROR', startTime, subject, to, error, id: doc.id });
    }
  });
  
  console.log('📈 Queue Status:');
  console.log('━'.repeat(60));
  console.log(`   ✅ Delivered: ${stats.success}`);
  console.log(`   ⏳ Pending: ${stats.pending}`);
  console.log(`   🔄 Processing: ${stats.processing}`);
  console.log(`   ❌ Failed: ${stats.error}`);
  console.log(`   📧 Total: ${stats.total}`);
  console.log('━'.repeat(60));
  
  if (recentEmails.length > 0) {
    console.log(`\n📋 Recent non-delivered emails (last ${Math.min(15, recentEmails.length)}):\n`);
    recentEmails.slice(0, 15).forEach((email, idx) => {
      const timeAgo = email.startTime ? 
        `${Math.round((Date.now() - email.startTime.getTime()) / 60000)} min ago` : 
        'unknown';
      console.log(`${idx + 1}. [${email.state}] ${email.subject.substring(0, 50)}`);
      console.log(`   To: ${email.to}`);
      console.log(`   Time: ${timeAgo}`);
      if (email.error) {
        console.log(`   Error: ${email.error.substring(0, 80)}`);
      }
      console.log('');
    });
  }
  
  // Check for emails without delivery field at all (stuck)
  const stuckEmailsSnap = await db.collection('sendgridmail')
    .where('delivery', '==', null)
    .limit(20)
    .get();
  
  if (!stuckEmailsSnap.empty) {
    console.log(`\n⚠️  Found ${stuckEmailsSnap.size} emails without delivery tracking (STUCK!):\n`);
    stuckEmailsSnap.docs.slice(0, 5).forEach((doc, idx) => {
      const data = doc.data();
      const subject = data.message?.subject || 'No subject';
      const to = Array.isArray(data.to) ? data.to[0] : data.to || 'unknown';
      console.log(`${idx + 1}. ${subject.substring(0, 50)}`);
      console.log(`   To: ${to}`);
      console.log(`   ID: ${doc.id}`);
      console.log('');
    });
  }
  
  // Summary
  console.log('\n' + '='.repeat(60));
  if (stats.pending > 10 || stats.processing > 10) {
    console.log('⚠️  WARNING: Many emails pending/processing!');
    console.log('   The email extension may be overwhelmed or stuck.');
    console.log('   Consider checking the extension logs:');
    console.log('   gcloud functions describe ext-firestore-send-email-processqueue --region=us-central1');
  } else if (stats.error > 5) {
    console.log('⚠️  WARNING: Multiple failed emails!');
    console.log('   Check error messages above for details.');
  } else if (stats.success > 0 && stats.pending === 0) {
    console.log('✅ Email queue is healthy and processing normally!');
  } else if (stats.pending > 0) {
    console.log(`⏳ ${stats.pending} emails waiting to be processed...`);
    console.log('   This is normal if emails were just queued.');
  }
  console.log('='.repeat(60));
}

checkEmailQueue()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });

