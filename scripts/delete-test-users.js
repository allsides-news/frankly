#!/usr/bin/env node

/**
 * Delete Test Users Script
 * 
 * Deletes user authentication and all associated Firestore data for specified email addresses.
 * This allows re-testing new user flows with the same email addresses.
 * 
 * Usage:
 *   cd firebase/functions
 *   node ../../scripts/delete-test-users.js
 */

const admin = require('firebase-admin');
const readline = require('readline');

// Emails to delete
const EMAILS_TO_DELETE = [
  'otomoto2000@hotmail.com',
  'otomoto2000@gmail.com',
  'scott@allsides.com',
  'smcdonald@allsides.com',
];

// Initialize Firebase Admin
admin.initializeApp({
  projectId: 'allsides-roundtables',
});

const auth = admin.auth();
const db = admin.firestore();

async function confirm(question) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes');
    });
  });
}

async function getUserByEmail(email) {
  try {
    return await auth.getUserByEmail(email);
  } catch (error) {
    if (error.code === 'auth/user-not-found') {
      return null;
    }
    throw error;
  }
}

async function deleteUserAuth(uid, email) {
  try {
    await auth.deleteUser(uid);
    console.log(`✅ Deleted auth for: ${email} (${uid})`);
  } catch (error) {
    console.error(`❌ Error deleting auth for ${email}:`, error.message);
  }
}

async function deleteCollection(collectionRef, batchSize = 100) {
  const query = collectionRef.limit(batchSize);
  
  return new Promise((resolve, reject) => {
    deleteQueryBatch(query, resolve).catch(reject);
  });
}

async function deleteQueryBatch(query, resolve) {
  const snapshot = await query.get();

  const batchSize = snapshot.size;
  if (batchSize === 0) {
    resolve();
    return;
  }

  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
  });
  await batch.commit();

  process.nextTick(() => {
    deleteQueryBatch(query, resolve);
  });
}

async function deleteUserData(uid, email) {
  console.log(`\n🗑️  Deleting Firestore data for: ${email} (${uid})`);
  
  try {
    // 1. Delete public user profile
    const publicUserRef = db.doc(`publicUser/${uid}`);
    const publicUserDoc = await publicUserRef.get();
    if (publicUserDoc.exists) {
      await publicUserRef.delete();
      console.log(`  ✅ Deleted publicUser/${uid}`);
    }
    
    // 2. Delete user memberships (collection group)
    // Membership docs use `userId`, not `id` (see data_models membership.g.dart).
    const membershipsQuery = db.collectionGroup('community-membership')
      .where('userId', '==', uid);
    const memberships = await membershipsQuery.get();
    console.log(`  Found ${memberships.size} memberships`);
    for (const doc of memberships.docs) {
      await doc.ref.delete();
      console.log(`  ✅ Deleted membership: ${doc.ref.path}`);
    }
    
    // 3. Delete communities created by this user
    const communitiesQuery = db.collection('community')
      .where('creatorId', '==', uid);
    const communities = await communitiesQuery.get();
    console.log(`  Found ${communities.size} communities created by user`);
    for (const communityDoc of communities.docs) {
      const communityId = communityDoc.id;
      console.log(`  🗑️  Deleting community: ${communityId}`);
      
      // Delete templates subcollection
      await deleteCollection(communityDoc.ref.collection('templates'));
      
      // Delete community-membership subcollection
      await deleteCollection(communityDoc.ref.collection('community-membership'));
      
      // Delete discussion-threads subcollection
      await deleteCollection(communityDoc.ref.collection('discussion-threads'));
      
      // Delete the community document itself
      await communityDoc.ref.delete();
      console.log(`  ✅ Deleted community/${communityId} and subcollections`);
    }
    
    // 4. Delete event participants where user is participant
    const participantsQuery = db.collectionGroup('event-participants')
      .where('id', '==', uid);
    const participants = await participantsQuery.get();
    console.log(`  Found ${participants.size} event participations`);
    for (const doc of participants.docs) {
      await doc.ref.delete();
      console.log(`  ✅ Deleted participant: ${doc.ref.path}`);
    }
    
    // 5. Delete events created by user
    const eventsQuery = db.collectionGroup('events')
      .where('creatorId', '==', uid);
    const events = await eventsQuery.get();
    console.log(`  Found ${events.size} events created by user`);
    for (const eventDoc of events.docs) {
      // Delete event-participants subcollection
      await deleteCollection(eventDoc.ref.collection('event-participants'));
      
      // Delete the event itself
      await eventDoc.ref.delete();
      console.log(`  ✅ Deleted event: ${eventDoc.ref.path}`);
    }
    
    // 6. Delete user's private data collection
    const membershipsCollectionRef = db.collection(`memberships/${uid}/community-membership`);
    await deleteCollection(membershipsCollectionRef);
    console.log(`  ✅ Deleted memberships/${uid}/community-membership`);
    
    console.log(`✅ Completed Firestore cleanup for: ${email}`);
    
  } catch (error) {
    console.error(`❌ Error deleting Firestore data for ${email}:`, error.message);
  }
}

async function main() {
  console.log('🧹 Test User Cleanup Script');
  console.log('=============================\n');
  console.log('This will delete ALL data for the following users:');
  EMAILS_TO_DELETE.forEach(email => console.log(`  - ${email}`));
  console.log('\n⚠️  WARNING: This action cannot be undone!\n');
  
  const confirmed = await confirm('Are you sure you want to proceed? (y/n): ');
  
  if (!confirmed) {
    console.log('\n❌ Aborted. No changes made.');
    process.exit(0);
  }
  
  console.log('\n🚀 Starting cleanup...\n');
  
  for (const email of EMAILS_TO_DELETE) {
    console.log(`\n📧 Processing: ${email}`);
    console.log('='.repeat(50));
    
    const user = await getUserByEmail(email);
    
    if (!user) {
      console.log(`⚠️  No user found for: ${email}`);
      continue;
    }
    
    const uid = user.uid;
    console.log(`Found user: ${uid}`);
    
    // Delete Firestore data first
    await deleteUserData(uid, email);
    
    // Then delete auth account
    await deleteUserAuth(uid, email);
  }
  
  console.log('\n\n✅ Cleanup complete!');
  console.log('\n📝 Summary:');
  console.log('  - User auth accounts deleted');
  console.log('  - Public user profiles deleted');
  console.log('  - Community memberships deleted');
  console.log('  - Communities created by users deleted');
  console.log('  - Event participations deleted');
  console.log('  - Events created by users deleted');
  console.log('\n🎯 You can now re-register with these emails to test new user flows.\n');
  
  process.exit(0);
}

main().catch((error) => {
  console.error('\n❌ Fatal error:', error);
  process.exit(1);
});


