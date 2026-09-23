#!/usr/bin/env node
/**
 * Lists all pre/post event CTA survey responses across all events.
 *
 * Usage: node check-prepost-survey-responses.js [userId]
 */

const admin = require('firebase-admin');

try {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'allsides-roundtables',
  });
} catch (error) {
  console.error('Failed to initialize Firebase Admin:', error.message);
  process.exit(1);
}

const db = admin.firestore();

function formatAnswers(label, answers, answeredDate) {
  if (!answers || answers.length === 0) return;
  const date = answeredDate ? answeredDate.toDate().toISOString() : 'n/a';
  console.log(`  ${label} (answered ${date}):`);
  for (const a of answers) {
    if (a.questionType === 'multipleChoice' || a.questionType === 'residence') {
      console.log(`    [MC] "${a.questionText}" -> "${a.optionText}" (optionId=${a.optionId})`);
    } else {
      console.log(`    [A/D] "${a.questionText}" -> ${a.agreement}`);
    }
  }
}

async function main() {
  const filterUserId = process.argv[2];

  const snapshot = await db.collectionGroup('pre-post-survey-responses').get();
  console.log(`Found ${snapshot.size} response doc(s) total\n`);

  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (filterUserId && data.userId !== filterUserId) continue;

    // Path: community/{c}/templates/{t}/events/{e}/pre-post-survey-responses/{uid}
    const parts = doc.ref.path.split('/');
    const eventId = parts[5];
    const communityId = parts[1];

    console.log(`Event ${eventId} (community ${communityId})`);
    console.log(`  docId=${doc.id} userId=${data.userId} match=${doc.id === data.userId}`);
    formatAnswers('PRE', data.preEventAnswers, data.preEventAnsweredDate);
    formatAnswers('POST', data.postEventAnswers, data.postEventAnsweredDate);
    console.log('');
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('Query failed:', e);
    process.exit(1);
  });
