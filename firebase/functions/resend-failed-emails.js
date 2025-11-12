/**
 * Script to resend emails that failed due to attachments validation error
 * 
 * This script finds emails with the error "ValidationError: Invalid message 
 * configuration: Field 'message.attachments' must be an array" and recreates
 * them so they can be processed with the fixed code.
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
process.env.FIRESTORE_DATABASE_ID = '';
admin.initializeApp({
  projectId: 'allsides-roundtables'
});

const db = admin.firestore();

async function resendFailedEmails() {
  console.log('🔍 Finding failed emails with attachments error...\n');
  
  // Get all emails from sendgridmail collection
  const snap = await db.collection('sendgridmail').get();
  console.log(`📊 Total emails in collection: ${snap.size}\n`);
  
  const failedEmails = [];
  
  snap.forEach(doc => {
    const data = doc.data();
    const delivery = data.delivery || {};
    
    // Check if it failed with attachments error
    if (delivery.state === 'ERROR' && delivery.error) {
      const errorMsg = delivery.error;
      if (typeof errorMsg === 'string' && 
          (errorMsg.includes('attachments') || 
           errorMsg.includes('ValidationError'))) {
        failedEmails.push({
          id: doc.id,
          to: data.to?.[0],
          subject: data.message?.subject,
          data: data,
          error: errorMsg
        });
      }
    }
  });
  
  console.log(`❌ Found ${failedEmails.length} failed emails\n`);
  
  if (failedEmails.length === 0) {
    console.log('✅ No failed emails to resend!');
    return;
  }
  
  // Show what we found
  console.log('Failed emails to resend:\n');
  failedEmails.forEach((email, idx) => {
    console.log(`${idx + 1}. To: ${email.to}`);
    console.log(`   Subject: ${email.subject}`);
    console.log(`   Error: ${email.error.substring(0, 80)}...`);
    console.log('');
  });
  
  console.log('\n🔧 Preparing to resend these emails...\n');
  
  let resent = 0;
  let errors = 0;
  
  // Resend each failed email
  for (const email of failedEmails) {
    try {
      // Create a new email document with fixed data
      const newEmailData = {
        to: email.data.to,
        from: email.data.from,
        message: {
          subject: email.data.message.subject,
          html: email.data.message.html,
          attachments: [] // Explicitly set empty attachments array
        }
      };
      
      // Create new document
      await db.collection('sendgridmail').add(newEmailData);
      console.log(`   ✅ Resent: ${email.subject} to ${email.to}`);
      resent++;
      
      // Optional: Delete the old failed document to clean up
      // Uncomment if you want to remove the failed emails
      // await db.collection('sendgridmail').doc(email.id).delete();
      
    } catch (error) {
      console.log(`   ❌ Failed to resend: ${email.subject} - ${error.message}`);
      errors++;
    }
  }
  
  console.log('\n' + '='.repeat(60));
  console.log('📊 Resend Summary:');
  console.log('='.repeat(60));
  console.log(`   ✅ Successfully resent: ${resent} emails`);
  console.log(`   ❌ Failed to resend: ${errors} emails`);
  console.log(`   📧 Total processed: ${failedEmails.length} emails`);
  console.log('='.repeat(60));
  
  if (resent > 0) {
    console.log('\n✨ Emails have been queued for sending!');
    console.log('📬 They should be delivered within seconds to minutes.');
    console.log('\n💡 Monitor delivery with:');
    console.log('   firebase ext:logs --instance-id firestore-send-email\n');
  }
}

// Run the script
resendFailedEmails()
  .then(() => {
    console.log('✅ Script complete!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Script failed:', error);
    process.exit(1);
  });

