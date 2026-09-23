#!/bin/bash
# Quick hostless breakout configuration checker
# Usage: ./scripts/check-hostless-config.sh <eventPath>
# Example: ./scripts/check-hostless-config.sh "events/roundtables-standup/abc123/def456"

if [ -z "$1" ]; then
    echo "Usage: $0 <eventPath>"
    echo "Example: $0 'events/roundtables-standup/abc123/def456'"
    exit 1
fi

EVENT_PATH="$1"
PROJECT_ID="${2:-allsides-roundtables}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 HOSTLESS BREAKOUT CONFIGURATION CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Event Path: $EVENT_PATH"
echo "Project: $PROJECT_ID"
echo ""

# Check event configuration
echo "📋 EVENT CONFIGURATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
firebase firestore:get "$EVENT_PATH" --project "$PROJECT_ID" 2>/dev/null | tee /tmp/event_data.json

# Extract event ID from path
EVENT_ID=$(basename "$EVENT_PATH")

# Check live meeting
echo ""
echo "🎥 LIVE MEETING STATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
firebase firestore:get "$EVENT_PATH/live-meetings/$EVENT_ID" --project "$PROJECT_ID" 2>/dev/null

# Check participants
echo ""
echo "👥 PARTICIPANTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Querying participants..."
firebase firestore:get "$EVENT_PATH/event-participants" --project "$PROJECT_ID" --limit 10 2>/dev/null

# Check breakout rooms
echo ""
echo "🚪 BREAKOUT ROOMS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
firebase firestore:get "$EVENT_PATH/breakout-rooms" --project "$PROJECT_ID" --limit 5 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 QUICK CHECKS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if grep -q '"eventType": "hostless"' /tmp/event_data.json 2>/dev/null; then
    echo "✅ Event type is HOSTLESS"
else
    echo "❌ Event type is NOT hostless (check eventType field)"
fi

if grep -q '"breakoutRoomDefinition"' /tmp/event_data.json 2>/dev/null; then
    echo "✅ Breakout definition exists"
    TARGET=$(grep -o '"targetParticipants":[^,}]*' /tmp/event_data.json | cut -d: -f2 | tr -d ' ')
    if [ -n "$TARGET" ]; then
        echo "   Target participants per room: $TARGET"
    fi
else
    echo "⚠️  No breakout definition (will use default: 8 participants)"
fi

if grep -q '"status": "active"' /tmp/event_data.json 2>/dev/null; then
    echo "✅ Event status is ACTIVE"
else
    echo "⚠️  Event status might not be active"
fi

echo ""
echo "📊 For detailed Firebase Functions logs, run:"
echo "   firebase functions:log --only CheckHostlessGoToBreakouts --project $PROJECT_ID"
echo "   firebase functions:log --only InitiateBreakouts --project $PROJECT_ID"
echo ""

