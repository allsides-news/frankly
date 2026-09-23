#!/usr/bin/env node
/**
 * Comprehensive test of all email types in the system
 */

const admin = require('firebase-admin');

admin.initializeApp({
  projectId: 'allsides-roundtables'
});

const db = admin.firestore();

async function testAllEmailTypes() {
  console.log('📧 COMPREHENSIVE EMAIL SYSTEM AUDIT\n');
  console.log('='.repeat(80) + '\n');
  
  // Check last 7 days
  const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  
  const emailsSnap = await db.collection('sendgridmail')
    .limit(500)
    .get();
  
  const emailTypes = {
    'Registration Confirmation': { success: 0, error: 0, pending: 0, subjects: [] },
    'Starting in 1 day': { success: 0, error: 0, pending: 0, subjects: [] },
    'Starting in 1 hour': { success: 0, error: 0, pending: 0, subjects: [] },
    'Schedule Change': { success: 0, error: 0, pending: 0, subjects: [] },
    'Event Cancelled': { success: 0, error: 0, pending: 0, subjects: [] },
    'Thanks for joining': { success: 0, error: 0, pending: 0, subjects: [] },
    'New Announcement': { success: 0, error: 0, pending: 0, subjects: [] },
    'New Message': { success: 0, error: 0, pending: 0, subjects: [] },
    'Join Request Approved': { success: 0, error: 0, pending: 0, subjects: [] },
    'Weekly Digest': { success: 0, error: 0, pending: 0, subjects: [] },
  };
  
  const recentErrors = [];
  
  emailsSnap.docs.forEach(doc => {
    const data = doc.data();
    const subject = data.message?.subject || 'No subject';
    const state = data.delivery?.state || 'PENDING';
    const startTime = data.delivery?.startTime?.toDate();
    const error = data.delivery?.error;
    
    // Only count recent ones
    if (!startTime || startTime < cutoff) return;
    
    // Categorize by subject
    let type = 'Other';
    for (const emailType of Object.keys(emailTypes)) {
      if (subject.includes(emailType)) {
        type = emailType;
        break;
      }
    }
    
    if (!emailTypes[type]) {
      emailTypes[type] = { success: 0, error: 0, pending: 0, subjects: [] };
    }
    
    if (state === 'SUCCESS') {
      emailTypes[type].success++;
    } else if (state === 'ERROR') {
      emailTypes[type].error++;
      if (recentErrors.length < 10) {
        recentErrors.push({
          type,
          to: data.to?.[0],
          subject: subject.substring(0, 50),
          error: error?.substring(0, 80),
          time: startTime
        });
      }
    } else {
      emailTypes[type].pending++;
    }
    
    // Track unique subjects
    if (!emailTypes[type].subjects.includes(subject)) {
      emailTypes[type].subjects.push(subject);
    }
  });
  
  console.log('📊 EMAIL TYPES (Last 7 Days):\n');
  
  Object.entries(emailTypes).forEach(([type, stats]) => {
    const total = stats.success + stats.error + stats.pending;
    if (total === 0) return;
    
    const successRate = total > 0 ? Math.round((stats.success / total) * 100) : 0;
    const icon = successRate === 100 ? '✅' : successRate >= 90 ? '⚠️' : '❌';
    
    console.log(`${icon} ${type}`);
    console.log(`   Total: ${total} | Success: ${stats.success} | Error: ${stats.error} | Pending: ${stats.pending}`);
    console.log(`   Success Rate: ${successRate}%`);
    
    if (stats.error > 0) {
      console.log(`   WARNING: Has failures!`);
    }
    console.log();
  });
  
  if (recentErrors.length > 0) {
    console.log('='.repeat(80));
    console.log('❌ RECENT ERRORS:\n');
    
    recentErrors.forEach((err, idx) => {
      console.log(`${idx + 1}. [${err.type}] ${err.to}`);
      console.log(`   Subject: ${err.subject}`);
      console.log(`   Error: ${err.error}`);
      console.log(`   Time: ${err.time.toLocaleString()}\n`);
    });
  }
  
  console.log('='.repeat(80));
  console.log('✅ AUDIT COMPLETE\n');
  
  // Check if registration emails are working
  const regStats = emailTypes['Registration Confirmation'];
  if (regStats && regStats.success > 0 && regStats.error === 0) {
    console.log('✅ Registration emails: WORKING PERFECTLY');
  } else if (regStats && regStats.error > 0) {
    console.log('⚠️  Registration emails: HAS ERRORS - needs attention');
  } else {
    console.log('ℹ️  Registration emails: No recent activity (no new registrations)');
  }
}

testAllEmailTypes()
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
