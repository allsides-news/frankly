/**
 * Script to trigger Firestore index creation by running all compound queries
 * This will generate index creation links in the Firebase console
 */

const admin = require('firebase-admin');

// Initialize Firebase Admin with your service account
admin.initializeApp({
  projectId: 'allsides-roundtables',
});

// Get reference to the named database
const db = admin.firestore();
db.settings({ databaseId: 'allsides-roundtables-db' });

async function triggerIndexes() {
  console.log('Starting index trigger process...\n');
  
  const queries = [
    // Breakout rooms queries
    () => db.collectionGroup('breakout-rooms')
      .where('flagStatus', '==', 'active')
      .orderBy('orderingPriority', 'asc')
      .limit(1).get(),
    
    () => db.collectionGroup('breakout-rooms')
      .where('flagStatus', '==', 'active')
      .orderBy('roomName', 'asc')
      .limit(1).get(),
    
    // Event participants queries
    () => db.collectionGroup('event-participants')
      .where('id', '==', 'dummy')
      .where('isPresent', '==', true)
      .limit(1).get(),
    
    () => db.collectionGroup('event-participants')
      .where('id', '==', 'dummy')
      .where('status', '==', 'active')
      .limit(1).get(),
    
    () => db.collectionGroup('event-participants')
      .where('id', '==', 'dummy')
      .where('status', '==', 'active')
      .orderBy('scheduledTime', 'asc')
      .limit(1).get(),
    
    () => db.collectionGroup('event-participants')
      .where('communityId', '==', 'dummy')
      .orderBy('lastUpdatedTime', 'asc')
      .limit(1).get(),
    
    // Events queries
    () => db.collectionGroup('events')
      .where('isPublic', '==', true)
      .where('communityId', '==', 'dummy')
      .limit(1).get(),
    
    () => db.collectionGroup('events')
      .where('isPublic', '==', true)
      .where('communityId', '==', 'dummy')
      .orderBy('scheduledTime', 'asc')
      .limit(1).get(),
    
    () => db.collectionGroup('events')
      .where('isPublic', '==', true)
      .orderBy('scheduledTime', 'asc')
      .limit(1).get(),
    
    () => db.collectionGroup('events')
      .where('communityId', '==', 'dummy')
      .orderBy('scheduledTime', 'asc')
      .limit(1).get(),
    
    () => db.collectionGroup('events')
      .where('communityId', '==', 'dummy')
      .orderBy('scheduledTime', 'desc')
      .limit(1).get(),
    
    () => db.collectionGroup('events')
      .where('eventType', '==', 'hosted')
      .orderBy('scheduledTime', 'asc')
      .limit(1).get(),
    
    // Community membership queries
    () => db.collectionGroup('community-membership')
      .where('communityId', '==', 'dummy')
      .orderBy('firstJoined', 'asc')
      .limit(1).get(),
    
    () => db.collectionGroup('community-membership')
      .where('communityId', '==', 'dummy')
      .where('status', '==', 'member')
      .limit(1).get(),
    
    // Community tags queries
    () => db.collectionGroup('community-tags')
      .where('communityId', '==', 'dummy')
      .where('taggedItemType', '==', 'event')
      .limit(1).get(),
    
    // Templates queries
    () => db.collectionGroup('templates')
      .where('status', '==', 'active')
      .orderBy('createdDate', 'desc')
      .limit(1).get(),
    
    // Discussion threads queries
    () => db.collectionGroup('discussion-threads')
      .where('isDeleted', '==', false)
      .orderBy('createdAt', 'desc')
      .limit(1).get(),
    
    () => db.collectionGroup('discussion-thread-comments')
      .where('isDeleted', '==', false)
      .orderBy('createdAt', 'desc')
      .limit(1).get(),
    
    // Community queries
    () => db.collection('community')
      .where('creatorId', '==', 'dummy')
      .orderBy('createdDate', 'asc')
      .limit(1).get(),
    
    // Subscriptions queries
    () => db.collectionGroup('subscriptions')
      .where('appliedCommunityId', '==', 'dummy')
      .orderBy('activeUntil', 'asc')
      .limit(1).get(),
  ];
  
  let successCount = 0;
  let errorCount = 0;
  
  for (let i = 0; i < queries.length; i++) {
    try {
      await queries[i]();
      successCount++;
      console.log(`✓ Query ${i + 1}/${queries.length} triggered successfully`);
    } catch (error) {
      errorCount++;
      if (error.message.includes('index')) {
        console.log(`✓ Query ${i + 1}/${queries.length} - Index creation needed (expected)`);
        console.log(`  Index URL: ${error.message.match(/https:\/\/[^\s]+/)}`);
      } else {
        console.log(`✗ Query ${i + 1}/${queries.length} failed: ${error.message}`);
      }
    }
  }
  
  console.log(`\n=== Summary ===`);
  console.log(`Queries executed: ${queries.length}`);
  console.log(`Successful: ${successCount}`);
  console.log(`Needs indexes: ${errorCount}`);
  console.log(`\nNext steps:`);
  console.log(`1. Check the Firebase console for index creation links`);
  console.log(`2. Or deploy indexes using: firebase deploy --only firestore:indexes`);
}

triggerIndexes()
  .then(() => {
    console.log('\nIndex trigger process completed!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('Error triggering indexes:', error);
    process.exit(1);
  });

