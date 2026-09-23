#!/usr/bin/env node
/**
 * Resend registration emails to ALL users with the PROPER AllSides template
 */

const admin = require('firebase-admin');
const fs = require('fs');

admin.initializeApp({
  projectId: 'allsides-roundtables'
});

const db = admin.firestore();

// Load auth export
const authExportPath = '/tmp/auth-export.json';
if (!fs.existsSync(authExportPath)) {
  console.error('❌ Auth export not found. Run: firebase auth:export /tmp/auth-export.json --project=allsides-roundtables');
  process.exit(1);
}

const authData = JSON.parse(fs.readFileSync(authExportPath, 'utf8'));
const userMap = new Map(authData.users.map(u => [u.localId, u]));

async function resendAllEmails(eventIds) {
  console.log(`📧 Resending registration emails with PROPER TEMPLATE\n`);
  console.log(`   Events: ${eventIds.join(', ')}\n`);
  
  let totalSent = 0;
  
  for (const eventId of eventIds) {
    console.log(`\n${'='.repeat(80)}`);
    console.log(`Processing event: ${eventId}`);
    console.log('='.repeat(80) + '\n');
    
    // Find the event
    const eventsQuery = await db.collectionGroup('events').limit(500).get();
    let eventDoc = null;
    let eventPath = null;
    
    for (const doc of eventsQuery.docs) {
      if (doc.id === eventId) {
        eventDoc = doc;
        eventPath = doc.ref.path;
        break;
      }
    }
    
    if (!eventDoc) {
      console.log(`❌ Event ${eventId} not found! Skipping...\n`);
      continue;
    }
    
    const event = eventDoc.data();
    console.log(`✅ Event: ${event.title}\n`);
    
    // Get community and template
    const communityDoc = await db.doc(`community/${event.communityId}`).get();
    const community = communityDoc.data();
    
    const templateDoc = await db.doc(`community/${event.communityId}/templates/${event.templateId}`).get();
    const template = templateDoc.data();
    
    // Get participants
    const participantsSnap = await db.collection(`${eventPath}/event-participants`).get();
    const emailLogsSnap = await db.collection(`${eventPath}/email-logs`).get();
    
    // Find users who got the manual email
    const manualEmailLogs = [];
    emailLogsSnap.docs.forEach(doc => {
      const data = doc.data();
      if (data.manualSend === true) {
        manualEmailLogs.push({id: doc.id, userId: data.userId});
      }
    });
    
    console.log(`Found ${manualEmailLogs.length} users who got the wrong email\n`);
    
    // Delete the manual logs
    if (manualEmailLogs.length > 0) {
      console.log('🗑️  Deleting old manual email logs...');
      const batch = db.batch();
      manualEmailLogs.forEach(log => {
        batch.delete(db.doc(`${eventPath}/email-logs/${log.id}`));
      });
      await batch.commit();
      console.log('✅ Deleted\n');
    }
    
    // Get users to resend
    const usersToResend = [];
    participantsSnap.docs.forEach(doc => {
      const data = doc.data();
      const hadManualLog = manualEmailLogs.some(log => log.userId === doc.id);
      
      if (data.status === 'active' && hadManualLog) {
        const authUser = userMap.get(doc.id);
        if (authUser && authUser.email) {
          usersToResend.push({
            userId: doc.id,
            email: authUser.email,
            displayName: authUser.displayName || 'User'
          });
        }
      }
    });
    
    console.log(`📬 Sending proper emails to ${usersToResend.length} users...\n`);
    
    // Format date
    const scheduledDate = new Date(event.scheduledTime._seconds * 1000);
    const dateOptions = { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZoneName: 'short' };
    const eventDateDisplay = scheduledDate.toLocaleString('en-US', dateOptions);
    
    const participantCount = participantsSnap.size;
    const participantsText = participantCount === 1 ? 'is 1 participant' : `are ${participantCount} participants`;
    
    const eventTitle = event.title || template.title || 'Event';
    const eventImage = event.image || template.image || '';
    const communityName = community.name;
    const communityImage = community.profileImageUrl || '';
    const eventUrl = `https://roundtables.allsides.com/space/${event.communityId}/discuss/${event.templateId}/${event.id}`;
    const communityUrl = `https://roundtables.allsides.com/space/${event.communityId}`;
    
    let sent = 0;
    
    for (const user of usersToResend) {
      try {
        const cancelUrl = `${eventUrl}?cancel=true`;
        const detailsUrl = `${eventUrl}?uid=${user.userId}`;
        const settingsUrl = `https://roundtables.allsides.com/settings?initialSection=notifications&communityId=${event.communityId}`;
        
        const html = generateProperEmailTemplate({
          actionTitle: 'Registration',
          eventTitle,
          eventDateDisplay,
          eventImage,
          communityName,
          communityImage,
          communityUrl,
          cancelUrl,
          detailsUrl,
          participantsText,
          header: 'You are registered for an upcoming event!',
          communityId: event.communityId,
          settingsUrl
        });
        
        // Create email document with proper template
        const emailDoc = {
          to: [user.email],
          from: `${communityName} <no-reply@allsides.com>`,
          message: {
            subject: `Registration Confirmation for ${eventTitle}`,
            html: html
          }
        };
        
        await db.collection('sendgridmail').add(emailDoc);
        
        // Create proper email log
        await db.collection(`${eventPath}/email-logs`).add({
          userId: user.userId,
          eventEmailType: 'initialSignUp',
          createdDate: admin.firestore.FieldValue.serverTimestamp(),
          sendId: '',
        });
        
        console.log(`  ✅ ${user.email}`);
        sent++;
      } catch (e) {
        console.log(`  ❌ ${user.email}: ${e.message}`);
      }
    }
    
    console.log(`\n✅ Sent ${sent}/${usersToResend.length} emails for this event\n`);
    totalSent += sent;
  }
  
  console.log('\n' + '='.repeat(80));
  console.log(`🎉 COMPLETE! Total emails sent: ${totalSent}`);
  console.log('='.repeat(80) + '\n');
  console.log('📬 Users will receive properly branded AllSides registration emails within seconds.\n');
}

function generateProperEmailTemplate({
  actionTitle,
  eventTitle,
  eventDateDisplay,
  eventImage,
  communityName,
  communityImage,
  communityUrl,
  cancelUrl,
  detailsUrl,
  participantsText,
  header,
  communityId,
  settingsUrl
}) {
  const eventTitleSanitized = eventTitle.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const communityNameSanitized = communityName.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const actionTitleSanitized = actionTitle.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const eventImageSanitized = eventImage.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const communityImageSanitized = communityImage.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  
  const imageHtml = communityImage ? `
    <span class="title-community-image">
      <img width="48" src="${communityImageSanitized}"/>
    </span>
  ` : '';
  
  const calendarGoogleLink = '#';
  const calendarOffice365Link = '#';
  const calendarOutlookLink = '#';
  
  return `<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
    <meta name="viewport" content="width=device-width"/>
    <title>Email Title</title>
    <style type="text/css">
        body {
            font-size: 16px;
            font-family: Helvetica, Arial, sans-serif;
        }
        td {
            padding: 6px;
        }
        .email-body {
            max-width: 640px;
        }
        .title {
            color: #3d4868;
            font-size: 24px;
            text-align: center;
            margin: 20px;
        }
        .title-community-image {
            vertical-align: -16px;
            margin-right: 8px;
            height: 48px;
            width: 48px;
            display: inline-block;
            border-radius: 8px;
            overflow: hidden;
        }
        .title-community-name {
            font-weight: bold;
        }
        .title-separator {
            margin-left: 4px;
            margin-right: 4px;
            color: #9efac3;
            font-weight: bolder;
            font-size: 32px;
            vertical-align: -3px;
        }
        .title-label {
            display: inline-block;
        }
        .subtitle {
            font-size: 16px;
            text-align: center;
            margin-top: 24px;
            margin-bottom: 12px;
            font-weight: bold;
            color: #3d4868;
        }
        .header {
            margin-top: 24px;
            margin-bottom: 24px;
            text-align: center;
            font-size: 18px;
            font-weight: bold;
            color: #3d4868;
        }
        .section {
            padding-bottom: 20px;
            max-width: 520px;
            margin-left: auto;
            margin-right: auto;
        }
        .center {
            text-align: center;
            margin: 5px;
        }
        .event-box {
            background: #f2f2f2;
            padding: 4px;
            margin: 8px 4px;
        }
        .event-info-cell {
            width: 100%;
        }
        .event-info {

        }
        .event-name {
            font-size: 16px;
            font-weight: bold;
        }
        .event-date {
            font-size: 14px;
        }
        .event-more {
        }
        .more-button {
            display: block;
            background: #3d4868;
            padding: 8px;
            border-radius: 8px;
            width: 96px;
            height: 20px;
            line-height: 20px;
            text-align: center;
            text-decoration: none;
        }
        .supplement-text {
            padding: 25px;
            font-weight: lighter;
        }
        .text-button {
            color: black;
            font-weight: bold;
            text-decoration: underline;
        }
        .footer {
            padding: 8px;
            background: #3d4868;
            text-align: center;
        }
        .footer-copyright {
            font-size: 14px;
            color: #ffffff;

        }
        .footer-copyright a:link{
            color:#a1abcf;
        }
    </style>
</head>
<body>
    <div class="email-body">
        <div class="title">
            ${imageHtml}
            <span class="title-community-name">${communityNameSanitized}</span>
            <span class="title-separator">//</span>
            <span class="title-label">${actionTitleSanitized}</span>
        </div>
        <hr/>
        <div class="header">${header}</div>
        <br/>
        <div class="section">
            <div class="event-box">
                <table>
                    <tr>
                        <td><img src="${eventImageSanitized}" width="52"/></td>
                        <td class="event-info-cell">
                            <div class="event-info">
                                <div class="event-name">${eventTitleSanitized}</div>
                                <div class="event-date">${eventDateDisplay}</div>
                            </div>
                        </td>
                        <td>
                            <div class="event-more">
                                <a style="color: #9efac3; font-size: 14px;" href="${detailsUrl}" class="more-button">
                                    Go To Event
                                </a>
                            </div>
                        </td>
                    </tr>
                </table>
            </div>
        </div>
        <div class="section">
            <div class="center">Add to calendar:</div>
            <div class="center">
              <a href="${calendarGoogleLink}" style="color:#303B5F;"><b>Google</b></a>
              ·
              <a href="${calendarOffice365Link}" style="color:#303B5F;"><b>Office 365</b></a>
              ·
              <a href="${calendarOutlookLink}" style="color:#303B5F;"><b>Outlook</b></a>
            </div>
        </div>
        <hr/>
        <div class="section supplement-text">
            No-shows ruin the fun for everyone. If you can no longer attend,
            <a href="${cancelUrl}" class="text-button">click here</a>
            to cancel and let the other participants know.
        </div>
        <div class="footer">
            <div class="footer-copyright">AllSides Roundtables is operated by AllSides.</div><br/>
            <div style="color:#ffffff; font-size: 12px;">1220 L Street NW, Suite 100-513, Washington, DC 20005</div>
            <a style="color:#a1abcf; font-size: 12px;" href="${settingsUrl}">Notification Settings</a><br/>
            <a style="color:#a1abcf; font-size: 12px;" href="https://www.allsides.com/unbiased-balanced-news/privacy-policy">Privacy Statement</a><br/><br/>
            <div style="color:#ffffff; font-size: 10px;">© AllSides</div>
        </div>
    </div>
</body>
</html>`;
}

const eventIds = process.argv.slice(2);

if (eventIds.length === 0) {
  console.error('Usage: node resend-all-with-proper-template.js EVENT_ID1 EVENT_ID2 ...');
  console.error('Example: node resend-all-with-proper-template.js ogAEK1GIW8l8bOnqFu5g iKfOOvm1UuLLSUcDLPF6');
  process.exit(1);
}

resendAllEmails(eventIds)
  .then(() => process.exit(0))
  .catch(err => {
    console.error('❌ Error:', err);
    process.exit(1);
  });
