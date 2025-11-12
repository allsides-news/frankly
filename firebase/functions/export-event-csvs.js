#!/usr/bin/env node
/**
 * Export CSV files for an event without using Cloud Functions
 * Usage: node export-event-csvs.js <eventId>
 * 
 * Bypasses rate-limited Cloud Functions by directly querying Firestore
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialize Firebase Admin
// Try to use Application Default Credentials or service account
try {
  // First try Application Default Credentials (gcloud)
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: 'allsides-roundtables'
  });
  console.log('✅ Using Application Default Credentials');
} catch (error) {
  console.error('❌ Could not initialize Firebase Admin');
  console.error('');
  console.error('Run this command first:');
  console.error('  gcloud auth application-default login --project=allsides-roundtables');
  console.error('');
  console.error('Or download a service account key:');
  console.error('  https://console.cloud.google.com/iam-admin/serviceaccounts?project=allsides-roundtables');
  console.error('');
  process.exit(1);
}

const db = admin.firestore();

// Event details from URL: https://roundtables.allsides.com/space/qXIP0FcTFBQbrYdmgeeI/discuss/Xg1wS3qetUSuycm1bzAw/3tBC3hQbazfQoe8inQQS
const COMMUNITY_ID = 'qXIP0FcTFBQbrYdmgeeI';
const TEMPLATE_ID = 'Xg1wS3qetUSuycm1bzAw';
const EVENT_ID = process.argv[2] || '3tBC3hQbazfQoe8inQQS';

const EVENT_PATH = `community/${COMMUNITY_ID}/templates/${TEMPLATE_ID}/events/${EVENT_ID}`;
const LIVE_MEETING_PATH = `${EVENT_PATH}/live-meetings/${EVENT_ID}`;

console.log('🔍 Exporting CSV data for event:');
console.log(`   Community: ${COMMUNITY_ID}`);
console.log(`   Template: ${TEMPLATE_ID}`);
console.log(`   Event: ${EVENT_ID}`);
console.log('');

// CSV helper functions
function escapeCSVValue(value) {
  if (value == null) return '';
  const str = String(value);
  if (str.includes(',') || str.includes('"') || str.includes('\n')) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

function arrayToCSV(rows) {
  return rows.map(row => row.map(escapeCSVValue).join(',')).join('\n');
}

// Get user info from Firestore publicUser (bypasses rate-limited Auth API)
async function getUserInfo(userId) {
  try {
    // Try publicUser collection first (not rate-limited)
    const publicUserDoc = await db.doc(`publicUser/${userId}`).get();
    if (publicUserDoc.exists) {
      const data = publicUserDoc.data();
      return {
        uid: userId,
        email: data.email || 'unknown',
        displayName: data.displayName || 'Unknown User'
      };
    }
    
    // Fallback: try Firebase Auth (will fail if rate-limited)
    const userRecord = await admin.auth().getUser(userId);
    return {
      uid: userRecord.uid,
      email: userRecord.email || 'unknown',
      displayName: userRecord.displayName || 'Unknown User'
    };
  } catch (error) {
    // Rate limit or user not found - return minimal info
    return {
      uid: userId,
      email: 'unknown',
      displayName: 'Unknown User'
    };
  }
}

// Format date
function formatDate(timestamp) {
  if (!timestamp) return '';
  const date = timestamp.toDate ? timestamp.toDate() : new Date(timestamp);
  return date.toISOString().replace('T', ' ').replace('Z', '');
}

// Get all breakout room paths
async function getBreakoutRoomPaths() {
  const breakoutSessionsPath = `${LIVE_MEETING_PATH}/breakout-room-sessions`;
  console.log('📂 Fetching breakout room sessions...');
  
  const sessionDocs = await db.collection(breakoutSessionsPath).get();
  console.log(`   Found ${sessionDocs.size} breakout session(s)`);
  
  const roomPaths = [];
  
  for (const sessionDoc of sessionDocs.docs) {
    const roomsPath = `${sessionDoc.ref.path}/breakout-rooms`;
    const roomDocs = await db.collection(roomsPath).get();
    
    for (const roomDoc of roomDocs.docs) {
      const roomPath = `${roomDoc.ref.path}/live-meetings/${roomDoc.id}`;
      roomPaths.push({ path: roomPath, roomId: roomDoc.id });
    }
  }
  
  console.log(`   Found ${roomPaths.length} breakout room(s)`);
  return roomPaths;
}

// Get chats from a path
async function getChatsFromPath(meetingPath, roomId) {
  const chatsPath = `${meetingPath}/chats/community_chat/messages`;
  const chatDocs = await db.collection(chatsPath).orderBy('createdDate').get();
  
  const chats = [];
  for (const doc of chatDocs.docs) {
    const data = doc.data();
    try {
      const userInfo = await getUserInfo(data.creatorId);
      chats.push({
        type: 'Chat',
        id: doc.id,
        createdDate: data.createdDate,
        creatorName: userInfo.displayName,
        creatorEmail: userInfo.email,
        message: data.message || (data.emotionType ? `[Emotion: ${data.emotionType}]` : ''),
        roomId: roomId,
        deleted: data.messageStatus === 'removed'
      });
    } catch (error) {
      console.error(`Error processing chat ${doc.id}:`, error.message);
    }
  }
  
  return chats;
}

// Get suggestions from a path
async function getSuggestionsFromPath(meetingPath, roomId) {
  const suggestionsPath = `${meetingPath}/user-suggestions`;
  const suggestionDocs = await db.collection(suggestionsPath).orderBy('createdDate').get();
  
  const suggestions = [];
  for (const doc of suggestionDocs.docs) {
    const data = doc.data();
    try {
      const userInfo = await getUserInfo(data.creatorId);
      suggestions.push({
        type: 'Suggestion',
        id: doc.id,
        createdDate: data.createdDate,
        creatorName: userInfo.displayName,
        creatorEmail: userInfo.email,
        message: data.content || '',
        roomId: roomId,
        deleted: false,
        upvotes: (data.upvotedUserIds || []).length,
        downvotes: (data.downvotedUserIds || []).length,
        agendaItemId: ''
      });
    } catch (error) {
      console.error(`Error processing suggestion ${doc.id}:`, error.message);
    }
  }
  
  return suggestions;
}

// Get registration data
async function getRegistrationData() {
  console.log('');
  console.log('👥 Fetching registration data...');
  
  const eventDoc = await db.doc(EVENT_PATH).get();
  if (!eventDoc.exists) {
    throw new Error(`Event not found: ${EVENT_PATH}`);
  }
  
  const event = eventDoc.data();
  // Fix: Registrations are stored in 'event-participants', not 'registration'
  const participantsPath = `${EVENT_PATH}/event-participants`;
  const participantDocs = await db.collection(participantsPath).get();
  
  console.log(`   Found ${participantDocs.size} registration(s)`);
  
  const rows = [['#', 'Name', 'Email', 'Registration Status', 'Registered At', 'User ID']];
  
  let index = 1;
  for (const doc of participantDocs.docs) {
    const data = doc.data();
    try {
      const userInfo = await getUserInfo(doc.id); // Use doc.id as the userId
      rows.push([
        index++,
        userInfo.displayName,
        userInfo.email,
        data.status || 'registered',
        formatDate(data.createdDate),
        doc.id
      ]);
    } catch (error) {
      console.error(`Error processing participant ${doc.id}:`, error.message);
      // Add row with unknown user but keep the record
      rows.push([
        index++,
        'Unknown User',
        'unknown',
        data.status || 'registered',
        formatDate(data.createdDate),
        doc.id
      ]);
    }
  }
  
  return rows;
}

// Main export function
async function exportCSVs() {
  try {
    console.log('');
    console.log('💬 Fetching chats and suggestions...');
    
    // Get all meeting paths
    const breakoutRooms = await getBreakoutRoomPaths();
    const allMeetingPaths = [
      { path: EVENT_PATH, roomId: EVENT_ID },
      ...breakoutRooms
    ];
    
    console.log(`   Processing ${allMeetingPaths.length} meeting path(s)...`);
    
    // Collect all chats and suggestions
    let allChats = [];
    let allSuggestions = [];
    
    for (const { path, roomId } of allMeetingPaths) {
      console.log(`   - Processing: ${roomId}`);
      const chats = await getChatsFromPath(path, roomId);
      const suggestions = await getSuggestionsFromPath(path, roomId);
      allChats = allChats.concat(chats);
      allSuggestions = allSuggestions.concat(suggestions);
    }
    
    console.log(`   Found ${allChats.length} chat(s) and ${allSuggestions.length} suggestion(s)`);
    
    // Generate chats and suggestions CSV
    const chatSuggestionsRows = [
      ['Type', '#', 'Created', 'Name', 'Email', 'Message', 'RoomId', 'Deleted', 'Upvotes', 'Downvotes', 'AgendaItemId']
    ];
    
    let chatIndex = 1;
    for (const chat of allChats) {
      chatSuggestionsRows.push([
        chat.type,
        chatIndex++,
        formatDate(chat.createdDate),
        chat.creatorName,
        chat.creatorEmail,
        chat.message,
        chat.roomId,
        chat.deleted,
        '', '', '' // No upvotes/downvotes/agendaItemId for chats
      ]);
    }
    
    let suggestionIndex = 1;
    for (const suggestion of allSuggestions) {
      chatSuggestionsRows.push([
        suggestion.type,
        suggestionIndex++,
        formatDate(suggestion.createdDate),
        suggestion.creatorName,
        suggestion.creatorEmail,
        suggestion.message,
        suggestion.roomId,
        suggestion.deleted,
        suggestion.upvotes,
        suggestion.downvotes,
        suggestion.agendaItemId
      ]);
    }
    
    // Generate registration CSV
    const registrationRows = await getRegistrationData();
    
    // Save CSVs
    const outputDir = path.join(__dirname, '../event-csvs');
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    
    const chatSuggestionsCSV = arrayToCSV(chatSuggestionsRows);
    const chatSuggestionsFile = path.join(outputDir, `chats-suggestions-${EVENT_ID}.csv`);
    fs.writeFileSync(chatSuggestionsFile, chatSuggestionsCSV);
    
    const registrationCSV = arrayToCSV(registrationRows);
    const registrationFile = path.join(outputDir, `registration-${EVENT_ID}.csv`);
    fs.writeFileSync(registrationFile, registrationCSV);
    
    console.log('');
    console.log('✅ Export complete!');
    console.log('');
    console.log('📄 Files created:');
    console.log(`   ${chatSuggestionsFile}`);
    console.log(`   ${registrationFile}`);
    console.log('');
    
    process.exit(0);
  } catch (error) {
    console.error('');
    console.error('❌ Error exporting CSVs:', error);
    console.error(error.stack);
    process.exit(1);
  }
}

// Run export
exportCSVs();

