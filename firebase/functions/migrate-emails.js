/**
 * Migration Script: Move emails from 'mail' to 'sendgridmail' collection
 * 
 * This script migrates all emails that were stuck in the old 'mail' collection
 * to the new 'sendgridmail' collection so they can be processed and sent.
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin
process.env.FIRESTORE_DATABASE_ID = '';
admin.initializeApp({
  projectId: 'allsides-roundtables'
});

const db = admin.firestore();

async function migrateEmails() {
  console.log('🚀 Starting email migration...\n');
  
  // Get all emails from old 'mail' collection
  console.log('📥 Fetching emails from OLD "mail" collection...');
  const oldMailSnap = await db.collection('mail').get();
  console.log(`   Found ${oldMailSnap.size} emails to migrate\n`);
  
  if (oldMailSnap.size === 0) {
    console.log('✅ No emails to migrate. Exiting.');
    return;
  }
  
  // Check what's already in sendgridmail to avoid duplicates
  console.log('🔍 Checking NEW "sendgridmail" collection for duplicates...');
  const existingMailSnap = await db.collection('sendgridmail').get();
  const existingEmails = new Set();
  existingMailSnap.forEach(doc => {
    const data = doc.data();
    // Create a unique key based on recipient and subject
    const key = `${data.to?.[0]}_${data.message?.subject}`;
    existingEmails.add(key);
  });
  console.log(`   Found ${existingEmails.size} existing emails in sendgridmail\n`);
  
  // Migrate emails in batches
  let migratedCount = 0;
  let skippedCount = 0;
  let errorCount = 0;
  const batchSize = 500;
  
  console.log('📤 Starting migration...\n');
  
  for (let i = 0; i < oldMailSnap.docs.length; i += batchSize) {
    const batch = db.batch();
    const batchDocs = oldMailSnap.docs.slice(i, i + batchSize);
    
    for (const doc of batchDocs) {
      const data = doc.data();
      const key = `${data.to?.[0]}_${data.message?.subject}`;
      
      // Skip if already exists in sendgridmail
      if (existingEmails.has(key)) {
        skippedCount++;
        console.log(`   ⏭️  Skipping duplicate: ${data.message?.subject?.substring(0, 50)}... to ${data.to?.[0]}`);
        continue;
      }
      
      // Create new document in sendgridmail
      const newDocRef = db.collection('sendgridmail').doc();
      batch.set(newDocRef, data);
      migratedCount++;
      
      console.log(`   ✅ Queuing: ${data.message?.subject?.substring(0, 50)}... to ${data.to?.[0]}`);
    }
    
    // Commit the batch
    try {
      await batch.commit();
      console.log(`\n   💾 Committed batch ${Math.floor(i / batchSize) + 1}\n`);
    } catch (error) {
      console.error(`\n   ❌ Error committing batch: ${error.message}\n`);
      errorCount += batchDocs.length;
    }
  }
  
  console.log('\n' + '='.repeat(60));
  console.log('📊 Migration Summary:');
  console.log('='.repeat(60));
  console.log(`   ✅ Migrated: ${migratedCount} emails`);
  console.log(`   ⏭️  Skipped (duplicates): ${skippedCount} emails`);
  console.log(`   ❌ Errors: ${errorCount} emails`);
  console.log(`   📧 Total processed: ${oldMailSnap.size} emails`);
  console.log('='.repeat(60));
  
  if (migratedCount > 0) {
    console.log('\n✨ Success! Emails have been migrated to "sendgridmail" collection.');
    console.log('📬 The SendGrid extension will now process and send them.');
    console.log('⏱️  This typically happens within seconds to minutes.');
    console.log('\n💡 Tip: Monitor the extension logs with:');
    console.log('   firebase functions:log --only ext-firestore-send-email-processQueue\n');
  }
  
  console.log('\n🗑️  Note: The old "mail" collection emails are still there.');
  console.log('   You can delete them later once you verify emails were sent.\n');
}

// Run the migration
migrateEmails()
  .then(() => {
    console.log('✅ Migration complete!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Migration failed:', error);
    process.exit(1);
  });

