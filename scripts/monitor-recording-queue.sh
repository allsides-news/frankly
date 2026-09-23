#!/bin/bash
# Monitor Recording Queue - Shows the queue processing breakout room recordings
# This shows batch processing, retries, and queue management
# Refreshes every 10 seconds

PROJECT="allsides-roundtables"

echo "=================================================="
echo "📋 Recording Queue Monitor"
echo "=================================================="
echo "Monitoring project: $PROJECT"
echo "Shows queue processing for multiple breakout rooms"
echo ""
echo "Look for:"
echo "  - 'RecordingQueue' messages"
echo "  - 'Successfully queued and started recording'"
echo "  - 'attempt X/3' (retry logic)"
echo "  - 'Rate limit' (429 errors)"
echo ""
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "=================================================="
  echo "📋 Recording Queue Monitor"
  echo "=================================================="
  echo "Time: $(date)"
  echo "Showing last 5 minutes of queue activity..."
  echo ""
  
  gcloud logging read "resource.type=cloud_function AND (textPayload:\"RecordingQueue\" OR textPayload:\"queued and started recording\" OR textPayload:\"Queuing recording\")" \
    --limit=25 \
    --project=$PROJECT \
    --format="table(timestamp.date('%H:%M:%S'),textPayload.extract('.*').slice(:150))" \
    --freshness=5m
  
  echo ""
  echo "Last updated: $(date)"
  echo "Refreshing in 10 seconds... (Ctrl+C to stop)"
  sleep 10
done

