// Quick script to delete a stuck recording job
const admin = require('firebase-admin');

// Initialize Firebase Admin
admin.initializeApp();

const eventId = process.argv[2];

if (!eventId) {
  console.error('Usage: node delete-recording-job.js <eventId>');
  console.error('Example: node delete-recording-job.js 6Fp0Xukyb0G6UqXhjyy5');
  process.exit(1);
}

async function deleteJob() {
  try {
    await admin.firestore().collection('recordingJobs').doc(eventId).delete();
    console.log(`✅ Deleted recording job for event: ${eventId}`);
    process.exit(0);
  } catch (err) {
    console.error('❌ Error deleting job:', err);
    process.exit(1);
  }
}

deleteJob();

