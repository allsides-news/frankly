/**
 * Test script for Trigger Email extension
 * Creates a document in the mail collection to trigger email sending
 */

const admin = require('firebase-admin');

// Initialize with the named database
process.env.FIRESTORE_DATABASE_ID = 'allsides-roundtables-db';

admin.initializeApp({
  projectId: 'allsides-roundtables'
});

const db = admin.firestore();

async function sendTestEmail() {
  console.log('Creating email document in allsides-roundtables-db/mail collection...\n');
  
  const emailData = {
    to: 'scott@allsides.com',
    message: {
      subject: 'Test Email from Trigger Email Extension',
      text: 'This is a test email sent from the newly configured allsides-roundtables-db database. If you receive this, the Trigger Email extension is working correctly!',
      html: `
        <h1>✅ Test Email Success!</h1>
        <p>This is a test email sent from the newly configured <strong>allsides-roundtables-db</strong> database.</p>
        <p>If you receive this, the Trigger Email extension is working correctly!</p>
        <hr>
        <p><small>Sent from: allsides-roundtables-db on ${new Date().toISOString()}</small></p>
      `
    }
  };
  
  try {
    const docRef = await db.collection('sendgridmail').add(emailData);
    console.log('✅ Email document created successfully!');
    console.log('Document ID:', docRef.id);
    console.log('Collection: mail');
    console.log('Database: allsides-roundtables-db');
    console.log('\nThe Trigger Email extension should process this document and send the email within a few seconds.');
    console.log('Check the document in Firebase Console to see delivery status updates.');
    console.log('\nConsole link:');
    console.log(`https://console.firebase.google.com/project/allsides-roundtables/firestore/databases/allsides-roundtables-db/data/~2Fmail~2F${docRef.id}`);
  } catch (error) {
    console.error('❌ Error creating email document:', error);
  }
}

sendTestEmail()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error:', error);
    process.exit(1);
  });

