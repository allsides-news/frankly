#!/bin/bash

PROJECT_ID="allsides-roundtables"
DATABASE_ID=""
RULES_FILE="firebase/firestore/firestore.rules"

echo "Deploying Firestore rules to $DATABASE_ID..."

# Get access token
TOKEN=$(gcloud auth print-access-token)

# Read rules file
RULES_CONTENT=$(cat $RULES_FILE | jq -Rs .)

# Create JSON payload
cat > /tmp/rules-payload.json <<EOF
{
  "rules": {
    "files": [
      {
        "name": "firestore.rules",
        "content": $RULES_CONTENT
      }
    ]
  }
}
EOF

# Deploy rules using REST API
curl -X PATCH \
  "https://firestore.googleapis.com/v1/projects/$PROJECT_ID/databases/$DATABASE_ID/securityRules" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d @/tmp/rules-payload.json

echo ""
echo "Rules deployment initiated!"

