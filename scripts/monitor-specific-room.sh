#!/bin/bash
# Monitor Specific Room - Track all activity for a specific breakout room
# Usage: ./monitor-specific-room.sh ROOM_ID

PROJECT="allsides-roundtables"

if [ -z "$1" ]; then
  echo "=================================================="
  echo "🔍 Monitor Specific Breakout Room"
  echo "=================================================="
  echo ""
  echo "Usage: $0 <ROOM_ID>"
  echo ""
  echo "Example:"
  echo "  $0 abc123xyz456"
  echo ""
  echo "This will show all logs related to that specific room,"
  echo "including recording start, claims, and any errors."
  echo ""
  exit 1
fi

ROOM_ID="$1"

echo "=================================================="
echo "🔍 Monitoring Breakout Room: $ROOM_ID"
echo "=================================================="
echo "Project: $PROJECT"
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "=================================================="
  echo "🔍 Monitoring Breakout Room: $ROOM_ID"
  echo "=================================================="
  echo "Time: $(date)"
  echo "Showing last 10 minutes of activity..."
  echo ""
  
  gcloud logging read "resource.type=cloud_function AND textPayload:\"$ROOM_ID\"" \
    --limit=30 \
    --project=$PROJECT \
    --format="table(timestamp.date('%H:%M:%S'),resource.labels.function_name,textPayload.extract('.*').slice(:120))" \
    --freshness=10m
  
  echo ""
  echo "Last updated: $(date)"
  echo "Refreshing in 10 seconds... (Ctrl+C to stop)"
  sleep 10
done

