# Email System Health Report

**Last Updated:** May 13, 2026
**Investigated By:** Agent
**Firebase Project:** `allsides-roundtables`

---

## User Report: jackhuntercohen@gmail.com

**Complaint:** User did not receive an event registration email.
**Firebase UID:** `YDmvoFsshdRzxV5UNknVZ8Kg1LN2`

### Findings

**Emails were delivered.** The `sendgridmail` collection contains 3 documents addressed to this user, all with `delivery.state: SUCCESS`:

| Subject | Sent | Status | Message ID |
|---------|------|--------|-----------|
| Registration Confirmation for Bridging the Gap Screening | May 10 @ 9:13 PM | SUCCESS | `ee5eaaa8…` |
| Registration Confirmation for Bridging the Gap Screening | May 10 @ 5:16 PM | SUCCESS | `74852e45…` |
| Upcoming Events for AllSides Roundtables (5/13/2026) | May 13 @ 12:01 AM | SUCCESS | `5dc92848…` |

**Event Registrations Found:**

| Event ID | Title | Status | Joined | Scheduled |
|----------|-------|--------|--------|-----------|
| `WPGHuSqKYhcL3tA0SKii` | Bridging the Gap Screening | active | May 10, 9:13 PM | May 23, 2026 |
| `8jkir1KOVMp38EHaHkm5` | Bridging the Gap Screening | active | May 10, 5:16 PM | May 24, 2026 |

Both events are in community `qXIP0FcTFBQbrYdmgeeI` (AllSides Roundtables), template `misc`.

### Resolution

Tell the user to **check their spam/junk folder**. Both emails were sent from `AllSides Roundtables <no-reply@allsides.com>` and confirmed delivered by SendGrid.

### Anomaly: Missing email-logs

Both events have populated `email-logs` subcollections (29 and 24 entries respectively), but **no entry exists for this user's UID**. All other participants have log entries. This creates a deduplication gap — if `joinEvent` is called again for this user, they could receive a duplicate confirmation.

**Fix:** Manually write email-log documents for both events:

```
Path: community/qXIP0FcTFBQbrYdmgeeI/templates/misc/events/WPGHuSqKYhcL3tA0SKii/email-logs/{auto-id}
Path: community/qXIP0FcTFBQbrYdmgeeI/templates/misc/events/8jkir1KOVMp38EHaHkm5/email-logs/{auto-id}

Document data:
{
  "userId": "YDmvoFsshdRzxV5UNknVZ8Kg1LN2",
  "eventEmailType": "initialSignUp",
  "sendId": "",
  "createdDate": <Firestore server timestamp>
}
```

---

## Email System Health (as of May 13, 2026)

### sendgridmail Collection (Primary — Active)

- **100% delivery rate** across the last 500 documents (7-day window)
- No errors or stuck docs
- All email types confirmed working

| Type | Count (7 days) | Status |
|------|---------------|--------|
| digest | 368 | Working |
| registration | 80 | Working |
| ended | 48 | Working |
| reminder_1h | 2 | Working |
| updated | 2 | Working |

### mail Collection (Legacy — NOT Monitored)

The Firebase "Trigger Email" extension watches `sendgridmail`, **not** `mail`. Documents in `mail` are never processed.

| Status | Count |
|--------|-------|
| SUCCESS (processed before collection rename) | 97 |
| Stuck — no delivery state | **167** |
| Total | 264 |

Of the 167 stuck docs, approximately **101 have real (non-test) recipient addresses**. Most are for old events ("Roundtable on Political Violence" era).

**This is the most significant email system health issue.** Affected recipients include:
- `raynesherman77@gmail.com` — Registration Confirmation
- `deballerton@gmail.com` — Registration Confirmation
- `rittmuellerjoanne@gmail.com` — Registration Confirmation
- `billboardjim@gmail.com` — 1-day reminder
- `scott@allsides.com`, `tatiana@allsides.com` — Thanks for joining
- And ~95 others

**Options:**
1. **Migrate to sendgridmail** — Run `firebase/functions/migrate-emails.js`. This triggers the extension to send them. Only do this if the events are upcoming/recent and sending is still appropriate.
2. **Delete** — If events are past, just delete the stuck docs.
3. **Do nothing** — Docs sit indefinitely; no user impact beyond already-missed emails.

### emails Collection

Empty. Not referenced by any active code. No action needed.

---

## Issue: Email-Log Deduplication Format Mismatch

### Background

`event_emails.dart` writes `email-logs` documents with **deterministic UID-prefixed IDs**:
```
{uid}_initialSignUp___empty__
```
This enables transactional deduplication — the function reads the doc inside a Firestore transaction and skips sending if it already exists.

### Problem

All existing email-log documents in Firestore use **auto-generated document IDs** — this is the format written by the previously deployed version of the cloud functions. The source code has been updated (commits `fix: resolve sendId sentinel collision`, `fix: prevent duplicate registration confirmation emails`, etc.) but the functions have **not been rebuilt and redeployed**.

Until deployed:
- The transactional deduplication check always returns "not found" (can't find auto-ID logs by UID-prefixed key)
- The non-transactional pre-filter (which scans all logs by `userId` field) still works and prevents most duplicates
- The full fix is not active

### Resolution

**Rebuild and deploy the cloud functions.** The build script is at `firebase/functions/build.sh`. Several important email fixes are in the current source but not yet in production:

```
44e58a86 fix: resolve sendId sentinel collision and tighten logDocRefs type
5ec5834e fix: address PR review — reads-before-writes and CF retry on failure
8bf121d8 fix: prevent duplicate registration confirmation emails
19cff2b9 Handle concurrent template creation within transaction
8c71d7a6 Create template within email transaction to fix snapshot isolation
```

---

## Historical Investigation (February 24, 2026)

### Events Investigated

1. **Event ID:** `ogAEK1GIW8l8bOnqFu5g` — Roundtable on Carmel's Housing Challenges (March 5, 4 PM PST)
2. **Event ID:** `iKfOOvm1UuLLSUcDLPF6` — Roundtable on Carmel's Housing Challenges (March 5, 11 AM PST)

Both events: `community/qXIP0FcTFBQbrYdmgeeI/templates/misc/events/...`

### Root Cause

No emails were ever queued for these events — `sendgridmail` contained no documents for either event. The `joinEvent` cloud function was wrapped in `unawaited` + `catchError`, silently discarding any errors.

The code has since been updated. Current version of `event_page_provider.dart`:

```dart
if (!_joinEventCFCalled) {
  _joinEventCFCalled = true;
  unawaited(
    cloudFunctionsEventService.joinEvent(eventProvider.event).catchError((e) {
      loggingService.log('Error calling joinEvent function: $e');
      _joinEventCFCalled = false;
    }),
  );
}
```

The `_joinEventCFCalled` guard was added to prevent duplicate calls. Errors are logged (not swallowed) and the flag resets on failure to allow retry.

---

## Diagnostic Scripts

Located in `firebase/functions/`:

| Script | Purpose |
|--------|---------|
| `check-user-emails.js EMAIL [HOURS]` | All emails sent to a specific address |
| `find-recent-registrations.js [HOURS]` | Recent registration confirmation emails |
| `check-event-emails.js` | Emails for a specific event |
| `check-sendgrid-queue.js` | Inspect sendgridmail collection |
| `migrate-emails.js` | Move stuck `mail` docs to `sendgridmail` |
| `resend-registration-emails.js` | Manual resend for specific event |
| `send-missing-registration-emails.js` | Resend for participants with no email-log |
| `resend-failed-emails.js` | Resend ERROR-state sendgridmail docs |

**Usage (requires GOOGLE_CLOUD_PROJECT env var):**
```bash
GOOGLE_CLOUD_PROJECT=allsides-roundtables GCLOUD_PROJECT=allsides-roundtables \
  node check-user-emails.js user@example.com 720
```

---

## Action Items

| Priority | Action | Owner |
|----------|--------|-------|
| **High** | Rebuild and deploy cloud functions | Engineering |
| **High** | Audit `mail` collection — decide send/delete for 101 stuck real emails | Engineering |
| **Medium** | Write missing email-log for jackhuntercohen (2 events) | Engineering |
| **Low** | Tell jackhuntercohen to check spam folder | Support |
