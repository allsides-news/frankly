#!/bin/bash
# Monitor Claim-Based Deduplication - Shows the atomic claim system working
# This shows when the deduplication fix is preventing duplicate recordings
# Refreshes every 10 seconds

PROJECT="allsides-roundtables"

echo "=================================================="
echo "🔒 Claim-Based Deduplication Monitor"
echo "=================================================="
echo "Monitoring project: $PROJECT"
echo "This shows the deduplication fix in action!"
echo ""
echo "✅ GOOD: 'Successfully claimed recording'"
echo "✅ GOOD: 'Another request won the claim race' (duplicate prevented!)"
echo "❌ BAD:  Multiple claims for same room ID"
echo ""
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "=================================================="
  echo "🔒 Claim-Based Deduplication Monitor"
  echo "=================================================="
  echo "Time: $(date)"
  echo "Showing last 5 minutes of claim activity..."
  echo ""
  
  gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=\"GetBreakoutRoomJoinInfo\" AND (textPayload:\"claim\" OR textPayload:\"Claim\")" \
    --limit=25 \
    --project=$PROJECT \
    --format="table(timestamp.date('%H:%M:%S'),textPayload.extract('.*').slice(:150))" \
    --freshness=5m
  
  echo ""
  echo "Last updated: $(date)"
  echo "Refreshing in 10 seconds... (Ctrl+C to stop)"
  sleep 10
done

