const admin = require('firebase-admin');

admin.initializeApp({
  credential: admin.credential.applicationDefault()
});

const db = admin.firestore();

async function checkMessages() {
  try {
    const eventPath = 'community/gh6jl9ZPOsETSxSacFV7/templates/iQHvlViTYWMjtzfHaod7/events/lwJHOIotfHwlz4Wr7SvN';
    
    // Check event's main chat (NEW PATH)
    console.log('=== CHECKING EVENT MAIN CHAT ===');
    const eventChatPath = `${eventPath}/chats/community_chat/messages`;
    console.log(`Path: ${eventChatPath}`);
    
    const eventChatSnapshot = await db.collection(eventChatPath)
      .orderBy('createdDate', 'desc')
      .limit(10)
      .get();
    
    console.log(`\nFound ${eventChatSnapshot.docs.length} messages in event chat:`);
    
    eventChatSnapshot.docs.forEach((doc, index) => {
      const data = doc.data();
      console.log(`\n${index + 1}. Message ID: ${doc.id}`);
      console.log(`   Text: ${data.message}`);
      console.log(`   Broadcast: ${data.broadcast}`);
      console.log(`   MessageType: ${data.messageType}`);
      console.log(`   MembershipStatusSnapshot: ${data.membershipStatusSnapshot}`);
      console.log(`   CreatorId: ${data.creatorId}`);
      console.log(`   MessageStatus: ${data.messageStatus}`);
    });
    
    // Also check live-meeting chat (OLD PATH)
    console.log('\n\n=== CHECKING LIVE MEETING CHAT (OLD PATH) ===');
    const liveMeetingsSnapshot = await db.collection(`${eventPath}/live-meetings`).get();
    
    if (liveMeetingsSnapshot.empty) {
      console.log('No live meetings found');
      return;
    }
    
    console.log(`Found ${liveMeetingsSnapshot.docs.length} live meeting(s)`);
    
    for (const liveMeetingDoc of liveMeetingsSnapshot.docs) {
      const liveMeetingId = liveMeetingDoc.id;
      console.log(`\nLive Meeting ID: ${liveMeetingId}`);
      
      const messagesPath = `${eventPath}/live-meetings/${liveMeetingId}/chats/community_chat/messages`;
      console.log(`Path: ${messagesPath}`);
      
      const messagesSnapshot = await db.collection(messagesPath)
        .orderBy('createdDate', 'desc')
        .limit(10)
        .get();
      
      console.log(`Found ${messagesSnapshot.docs.length} messages in live meeting chat`);
      
      if (messagesSnapshot.docs.length > 0) {
        messagesSnapshot.docs.forEach((doc, index) => {
          const data = doc.data();
          console.log(`\n${index + 1}. Message ID: ${doc.id}`);
          console.log(`   Text: ${data.message}`);
        });
      }
    }
    
  } catch (error) {
    console.error('Error:', error);
  } finally {
    process.exit(0);
  }
}

checkMessages();

