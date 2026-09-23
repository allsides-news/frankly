# 🎯 Monitoring Scripts for AllSides Roundtables

This directory contains real-time monitoring scripts for tracking your production events, breakout rooms, and recording system.

## 📋 Quick Start

### **Best Script to Run During Events**
```bash
./scripts/monitor-all-dashboard.sh
```
This gives you a quick health snapshot. Run it periodically to check system status.

### **For Continuous Monitoring During Events**
```bash
./scripts/monitor-claim-deduplication.sh
```
This shows the deduplication fix working in real-time and is the most important during high-traffic events.

---

## 📚 All Available Scripts

### 1. **monitor-all-dashboard.sh** 
**Quick health snapshot - Run this first!**

```bash
./scripts/monitor-all-dashboard.sh
```

**What it shows:**
- Recent recording activity
- Number of duplicates prevented
- Errors and warnings (excluding known ShareLink issues)
- Breakout room activity
- System status summary

**Best for:** Quick checks before, during, and after events

---

### 2. **monitor-recording-activity.sh** ⭐
**Auto-refreshing recording activity monitor**

```bash
./scripts/monitor-recording-activity.sh
```

**What it shows:**
- All recording-related logs
- Recording starts and stops
- Room IDs being recorded
- Updates every 10 seconds

**Best for:** Watching overall recording system activity

---

### 3. **monitor-claim-deduplication.sh** ⭐⭐⭐
**Watch the deduplication fix in action (MOST IMPORTANT)**

```bash
./scripts/monitor-claim-deduplication.sh
```

**What it shows:**
- "Successfully claimed recording" messages (good!)
- "Another request won the claim race" (duplicate prevented - good!)
- Claim IDs and verification
- Updates every 10 seconds

**Best for:** Confirming the deduplication fix is working during events with many simultaneous joins

**What to look for:**
- ✅ Each room should have exactly ONE "Successfully claimed" message
- ✅ Multiple "won the claim race" messages are GOOD (duplicates prevented)
- ❌ Multiple "Successfully claimed" for the SAME room ID is BAD

---

### 4. **monitor-function-errors.sh**
**Watch for any errors or warnings**

```bash
./scripts/monitor-function-errors.sh
```

**What it shows:**
- All ERROR and WARNING level logs
- Function names with errors
- Error timestamps
- Updates every 15 seconds

**Best for:** Troubleshooting when something goes wrong

**Note:** ShareLink errors are common and not critical for events

---

### 5. **monitor-recording-queue.sh**
**Watch the queue processing breakout rooms**

```bash
./scripts/monitor-recording-queue.sh
```

**What it shows:**
- Recording queue processing
- Batch operations
- Retry attempts
- Rate limit handling
- Updates every 10 seconds

**Best for:** Understanding how 80 breakout rooms are processed

**What to look for:**
- "Successfully queued and started recording"
- "attempt 1/3" (first try)
- Any "attempt 2/3" or "attempt 3/3" (retries - not ideal but OK)
- "429" or "rate limit" (problematic if frequent)

---

### 6. **monitor-specific-room.sh**
**Track everything about one specific room**

```bash
./scripts/monitor-specific-room.sh ROOM_ID_HERE
```

**Example:**
```bash
./scripts/monitor-specific-room.sh abc123xyz456
```

**What it shows:**
- All logs mentioning that specific room ID
- Recording start, claim, queue, and completion
- Any errors for that room
- Updates every 10 seconds

**Best for:** Deep-diving into a specific breakout room if users report issues

---

## 🎬 Recommended Monitoring Workflow

### **Before Event Starts:**
```bash
# Quick health check
./scripts/monitor-all-dashboard.sh
```
✅ Should show: No recent errors, system ready

---

### **During Event (Small - <20 breakout rooms):**
```bash
# Run this in a terminal window
./scripts/monitor-recording-activity.sh
```
Watch for recordings starting as breakouts are created

---

### **During Event (Large - 80 breakout rooms):** ⭐⭐⭐
```bash
# Terminal 1: Watch deduplication
./scripts/monitor-claim-deduplication.sh

# Terminal 2 (optional): Watch for errors
./scripts/monitor-function-errors.sh
```

**What success looks like:**
- Terminal 1: See lots of "Successfully claimed" and "won the claim race" messages
- Terminal 2: No new errors (ShareLink errors OK)

---

### **After Event:**
```bash
# Final health check
./scripts/monitor-all-dashboard.sh
```

Check for:
- Number of duplicates prevented
- Any errors during the event
- Verify recordings completed

---

## 🆘 Troubleshooting

### **Script says "command not found"**
Make sure you're in the project root:
```bash
cd /Users/oto/Sites/allsides-frankly
./scripts/monitor-all-dashboard.sh
```

### **Script shows "ERROR: Permission denied"**
Scripts should already be executable, but if not:
```bash
chmod +x ./scripts/monitor-*.sh
```

### **No logs appearing**
- Check if events are actually running
- Verify you're looking at the right time window (scripts show last 5-10 minutes)
- Try the dashboard: `./scripts/monitor-all-dashboard.sh`

### **Too many errors showing**
- ShareLink errors are known and not critical
- Look for errors in: GetBreakoutRoomJoinInfo, InitiateBreakouts, CheckAssignToBreakouts
- Those are the critical functions for breakout rooms

---

## 📊 What "Good" Looks Like

### **Successful Event with 80 Breakout Rooms:**

**monitor-claim-deduplication.sh output:**
```
✅ Successfully claimed recording start for room abc123 (claim ID: 1699...)
✅ Another request won the claim race for room abc123
✅ Another request won the claim race for room abc123
✅ Successfully claimed recording start for room xyz789 (claim ID: 1699...)
✅ Another request won the claim race for room xyz789
... (repeat for all 80 rooms)
```

**Interpretation:**
- Each room has 1 successful claim
- Multiple "won the race" messages = duplicates prevented! ✅
- This is PERFECT behavior

---

**monitor-recording-queue.sh output:**
```
✅ Queuing recording for breakout room: abc123 (claim confirmed)
✅ [RecordingQueue] Successfully started recording for room abc123 (attempt 1)
✅ Queuing recording for breakout room: xyz789 (claim confirmed)
✅ [RecordingQueue] Successfully started recording for room xyz789 (attempt 1)
... (repeat for all 80 rooms)
```

**Interpretation:**
- All rooms queued successfully
- All started on attempt 1 (no retries needed)
- This is PERFECT behavior

---

## 🎯 Key Metrics to Track

| Metric | Good | Concerning |
|--------|------|------------|
| **Claims per room** | 1 successful | 2+ successful for same room |
| **Race wins per room** | 0-5 "won the race" | N/A (more is fine) |
| **Recording start attempts** | Attempt 1/3 | Attempt 3/3 |
| **Rate limit errors** | 0 | 5+ per minute |
| **Recording failures** | 0 | Any |
| **Duplicates prevented** | 10-50 per event | N/A (more is better) |

---

## 📞 Quick Reference

```bash
# Quick health check
./scripts/monitor-all-dashboard.sh

# During event - watch deduplication
./scripts/monitor-claim-deduplication.sh

# During event - watch for problems  
./scripts/monitor-function-errors.sh

# Deep dive on specific room
./scripts/monitor-specific-room.sh ROOM_ID

# Watch recording system
./scripts/monitor-recording-activity.sh

# Watch queue processing
./scripts/monitor-recording-queue.sh
```

---

## 🚀 You're Ready!

Your deduplication fix is deployed and these scripts will help you monitor it working.

**Remember:** Seeing "Another request won the claim race" is GOOD - it means duplicates are being prevented! 🎉

