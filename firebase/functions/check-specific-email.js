#!/usr/bin/env node
/**
 * Check a specific email document by ID
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com'
});

const db = admin.firestore();

async function checkEmail(emailId) {
  console.log(`🔍 Checking email: ${emailId}\n`);
  
  const emailDoc = await db.collection('sendgridmail').doc(emailId).get();
  
  if (!emailDoc.exists) {
    console.log('❌ Email document not found!');
    return;
  }
  
  const data = emailDoc.data();
  const delivery = data.delivery || {};
  
  console.log('📧 Email Details:');
  console.log('━'.repeat(60));
  console.log(`   To: ${Array.isArray(data.to) ? data.to.join(', ') : data.to}`);
  console.log(`   From: ${data.from}`);
  console.log(`   Subject: ${data.message?.subject}`);
  console.log('');
  console.log('📬 Delivery Status:');
  console.log('━'.repeat(60));
  console.log(`   State: ${delivery.state || 'PENDING (not processed yet)'}`);
  console.log(`   Start Time: ${delivery.startTime?.toDate() || 'Not started'}`);
  console.log(`   End Time: ${delivery.endTime?.toDate() || 'Not finished'}`);
  console.log(`   Attempts: ${delivery.attempts || 0}`);
  
  if (delivery.error) {
    console.log(`\n❌ Error: ${delivery.error}`);
  }
  
  if (delivery.info) {
    console.log(`\nℹ️  Info: ${JSON.stringify(delivery.info, null, 2)}`);
  }
  
  console.log('\n' + '='.repeat(60));
  
  if (!delivery.state) {
    console.log('⚠️  Email is PENDING - not processed by extension yet');
    console.log('   This could mean:');
    console.log('   - Extension is processing it now (wait 30 seconds)');
    console.log('   - Extension is not running');
    console.log('   - Database permissions issue');
  } else if (delivery.state === 'SUCCESS') {
    console.log('✅ Email delivered successfully!');
    const deliveryTime = delivery.endTime?.toDate() || delivery.startTime?.toDate();
    if (deliveryTime) {
      const minsAgo = Math.round((Date.now() - deliveryTime.getTime()) / 60000);
      console.log(`   Delivered ${minsAgo} minutes ago`);
    }
  } else if (delivery.state === 'ERROR') {
    console.log('❌ Email delivery FAILED');
    console.log('   Check the error message above');
  }
  console.log('='.repeat(60));
}

const emailId = process.argv[2] || 'oiL5RbZrWTS2w1nruE2Q';

checkEmail(emailId)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });

