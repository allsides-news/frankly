#!/usr/bin/env node
/**
 * Inspect Smart Match survey structure and participant data for two events.
 * 
 * Usage:
 *   cd firebase/functions
 *   node ../../scripts/inspect-smart-match-events.js <eventId1> <eventId2>
 * 
 * Example:
 *   cd firebase/functions
 *   node ../../scripts/inspect-smart-match-events.js iKfOOvm1UuLLSUcDLPF6 ogAEK1GIW8l8bOnqFu5g
 */

const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: 'allsides-roundtables',
  databaseURL: 'https://allsides-roundtables-default-rtdb.firebaseio.com',
});

const db = admin.firestore();

const EVENT_IDS = ['iKfOOvm1UuLLSUcDLPF6', 'ogAEK1GIW8l8bOnqFu5g'];

async function inspectEvent(eventId) {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`Event: ${eventId}`);
  console.log('='.repeat(60));

  let eventDoc = null;
  let eventPath = null;

  // Scan all templates under allsides-roundtables to find the event
  const templatesSnap = await db
    .collection('community')
    .doc('allsides-roundtables')
    .collection('templates')
    .get();

  for (const templateDoc of templatesSnap.docs) {
    const eventRef = templateDoc.ref.collection('events').doc(eventId);
    const eventSnap = await eventRef.get();
    if (eventSnap.exists) {
      eventDoc = eventSnap.data();
      eventPath = eventSnap.ref.path;
      break;
    }
  }

  if (!eventDoc) {
    console.log('  ❌ Event not found');
    return;
  }

  console.log(`  Path: ${eventPath}`);
  console.log(`  Title: ${eventDoc.title ?? '(no title)'}`);
  console.log(`  Assignment method: ${eventDoc.breakoutRoomDefinition?.assignmentMethod ?? 'none'}`);

  const questions = eventDoc.breakoutRoomDefinition?.breakoutQuestions ?? [];
  console.log(`\n  Survey questions (${questions.length} total):`);
  questions.forEach((q, i) => {
    const numGroups = q.answers?.length ?? 0;
    console.log(`\n  Q${i + 1}: "${q.title}"`);
    console.log(`       Answer groups: ${numGroups}`);
    (q.answers ?? []).forEach((answer, gi) => {
      const optionTitles = (answer.options ?? []).map((o) => `"${o.title}"`).join(', ');
      console.log(`       Group ${gi}: [${optionTitles}]`);
    });
  });

  // Sample up to 5 participants
  const participantsSnap = await db
    .doc(eventPath)
    .collection('event-participants')
    .limit(5)
    .get();

  console.log(`\n  Participants sample (${participantsSnap.size} shown):`);
  participantsSnap.forEach((p) => {
    const data = p.data();
    const surveyQs = data.breakoutRoomSurveyQuestions ?? [];
    const jp = data.joinParameters ?? {};
    const hasAnsweredSurvey = surveyQs.length > 0 && surveyQs.every((q) => q.answerOptionId);
    const hasMask = !!jp.am;

    console.log(`\n  Participant: ${p.id}`);
    console.log(`    breakoutRoomSurveyQuestions: ${surveyQs.length} questions, fully answered: ${hasAnsweredSurvey}`);
    if (surveyQs.length > 0) {
      surveyQs.forEach((q, i) => {
        // Find the selected answer option title
        let selectedTitle = '?';
        for (const answer of q.answers ?? []) {
          const opt = (answer.options ?? []).find((o) => o.id === q.answerOptionId);
          if (opt) { selectedTitle = opt.title; break; }
        }
        console.log(`      Q${i + 1} "${q.title}" → "${selectedTitle}" (answerOptionId: ${q.answerOptionId ?? 'none'})`);
      });
    }
    console.log(`    joinParameters.am: ${jp.am ?? '(none)'}`);
    console.log(`    joinParameters.eventId: ${jp.eventId ?? '(none)'}`);
  });
}

(async () => {
  for (const id of EVENT_IDS) {
    await inspectEvent(id);
  }
  process.exit(0);
})();
