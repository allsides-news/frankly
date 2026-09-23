#!/bin/bash

# Test script for Trigger Email extension
# Creates a document in the mail collection via REST API

PROJECT_ID="allsides-roundtables"
DATABASE_ID=""
COLLECTION="mail"

echo "Sending test email via Trigger Email extension..."
echo "Database: $DATABASE_ID"
echo "Collection: $COLLECTION"
echo ""

# Get access token
TOKEN=$(gcloud auth print-access-token)

# Create email document using Firestore REST API
RESPONSE=$(curl -s -X POST \
  "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/$DATABASE_ID/documents/$COLLECTION" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "to": {
        "stringValue": "scott@allsides.com"
      },
      "message": {
        "mapValue": {
          "fields": {
            "subject": {
              "stringValue": "Test Email from Trigger Email Extension"
            },
            "text": {
              "stringValue": "This is a test email sent from the newly configured allsides-roundtables-db database. If you receive this, the Trigger Email extension is working correctly!"
            },
            "html": {
              "stringValue": "<h1>✅ Test Email Success!</h1><p>This is a test email sent from the newly configured <strong>allsides-roundtables-db</strong> database.</p><p>If you receive this, the Trigger Email extension is working correctly!</p><hr><p><small>Sent via Trigger Email Extension</small></p>"
            }
          }
        }
      }
    }
  }')

# Extract document ID from response
DOC_ID=$(echo $RESPONSE | jq -r '.name' | awk -F'/' '{print $NF}')

if [ "$DOC_ID" != "null" ] && [ -n "$DOC_ID" ]; then
  echo "✅ Email document created successfully!"
  echo "Document ID: $DOC_ID"
  echo ""
  echo "The Trigger Email extension should process this within seconds."
  echo "Check your inbox at: scott@allsides.com"
  echo ""
  echo "Monitor the document status:"
  echo "https://console.firebase.google.com/project/$PROJECT_ID/firestore/databases/$DATABASE_ID/data/~2Fmail~2F$DOC_ID"
else
  echo "❌ Failed to create email document"
  echo "Response: $RESPONSE"
fi

