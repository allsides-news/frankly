#!/bin/bash
# Monitor Recording Activity - Shows recent recording-related logs
# Refreshes every 10 seconds

PROJECT="allsides-roundtables"

echo "=================================================="
echo "🎥 Recording Activity Monitor"
echo "=================================================="
echo "Monitoring project: $PROJECT"
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "=================================================="
  echo "🎥 Recording Activity Monitor"
  echo "=================================================="
  echo "Time: $(date)"
  echo "Showing last 1 hour of activity..."
  echo ""
  
  gcloud logging read "resource.type=cloud_function AND (textPayload:\"recording\" OR textPayload:\"Recording\")" \
    --limit=20 \
    --project=$PROJECT \
    --format="table(timestamp.date('%H:%M:%S'),resource.labels.function_name,textPayload.extract('.*').slice(:120))" \
    --freshness=1h
  
  echo ""
  echo "Last updated: $(date)"
  echo "Refreshing in 10 seconds... (Ctrl+C to stop)"
  sleep 10
done

