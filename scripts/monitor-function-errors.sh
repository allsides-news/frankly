#!/bin/bash
# Monitor Function Errors - Shows all cloud function errors and warnings
# Refreshes every 15 seconds

PROJECT="allsides-roundtables"

echo "=================================================="
echo "⚠️  Cloud Function Error Monitor"
echo "=================================================="
echo "Monitoring project: $PROJECT"
echo "Showing errors and warnings from all functions"
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "=================================================="
  echo "⚠️  Cloud Function Error Monitor"
  echo "=================================================="
  echo "Time: $(date)"
  echo "Showing last 10 minutes of errors/warnings..."
  echo ""
  
  gcloud logging read "resource.type=cloud_function AND severity>=WARNING" \
    --limit=25 \
    --project=$PROJECT \
    --format="table(timestamp.date('%H:%M:%S'),resource.labels.function_name,severity,textPayload.extract('.*').slice(:100))" \
    --freshness=10m
  
  echo ""
  echo "Last updated: $(date)"
  echo "Refreshing in 15 seconds... (Ctrl+C to stop)"
  sleep 15
done

