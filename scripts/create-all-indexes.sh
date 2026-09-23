#!/bin/bash

# Script to create all Firestore indexes
# 
# NOTE: This script only creates composite indexes via gcloud commands.
# It does NOT deploy field-level index exemptions (fieldOverrides) from firestore.indexes.json.
# 
# RECOMMENDED: Use 'firebase deploy --only firestore:indexes' instead, which handles both:
#   - Composite indexes
#   - Field-level index exemptions (fieldOverrides)
#
# If you need to deploy to a specific database:
#   firebase deploy --only firestore:indexes --project allsides-roundtables
#
# To deploy to a named database, you'll need to update firebase.json

PROJECT_ID="allsides-roundtables"
DATABASE_ID=""

echo "Creating indexes in $DATABASE_ID..."
echo "This will take 5-10 minutes per index..."
echo ""
echo "⚠️  WARNING: This script doesn't deploy field-level indexes (fieldOverrides)."
echo "   Consider using: firebase deploy --only firestore:indexes"
echo ""

# Note: Index creation is async and happens in parallel
# Firestore can handle multiple index creations simultaneously

# Breakout rooms indexes
echo "Creating breakout-rooms indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=breakout-rooms \
  --query-scope=COLLECTION \
  --field-config=field-path=flagStatus,order=ASCENDING \
  --field-config=field-path=orderingPriority,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=breakout-rooms \
  --query-scope=COLLECTION \
  --field-config=field-path=flagStatus,order=ASCENDING \
  --field-config=field-path=roomName,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=breakout-rooms \
  --query-scope=COLLECTION \
  --field-config=field-path=participantIds,array-config=CONTAINS \
  --field-config=field-path=roomName,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Event participants indexes
echo "Creating event-participants indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=event-participants \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=id,order=ASCENDING \
  --field-config=field-path=isPresent,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=event-participants \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=id,order=ASCENDING \
  --field-config=field-path=status,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=event-participants \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=id,order=ASCENDING \
  --field-config=field-path=status,order=ASCENDING \
  --field-config=field-path=scheduledTime,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=event-participants \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=communityId,order=ASCENDING \
  --field-config=field-path=lastUpdatedTime,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Events indexes
echo "Creating events indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=events \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=isPublic,order=ASCENDING \
  --field-config=field-path=communityId,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=events \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=isPublic,order=ASCENDING \
  --field-config=field-path=communityId,order=ASCENDING \
  --field-config=field-path=scheduledTime,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=events \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=isPublic,order=ASCENDING \
  --field-config=field-path=scheduledTime,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=events \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=communityId,order=ASCENDING \
  --field-config=field-path=scheduledTime,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=events \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=communityId,order=ASCENDING \
  --field-config=field-path=scheduledTime,order=DESCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=events \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=eventType,order=ASCENDING \
  --field-config=field-path=scheduledTime,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Community membership indexes
echo "Creating community-membership indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=community-membership \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=communityId,order=ASCENDING \
  --field-config=field-path=firstJoined,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=community-membership \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=communityId,order=ASCENDING \
  --field-config=field-path=status,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Community tags indexes
echo "Creating community-tags indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=community-tags \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=communityId,order=ASCENDING \
  --field-config=field-path=taggedItemType,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Templates indexes
echo "Creating templates indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=templates \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=status,order=ASCENDING \
  --field-config=field-path=createdDate,order=DESCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Discussion threads indexes
echo "Creating discussion-threads indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=discussion-threads \
  --query-scope=COLLECTION \
  --field-config=field-path=isDeleted,order=ASCENDING \
  --field-config=field-path=createdAt,order=DESCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=discussion-thread-comments \
  --query-scope=COLLECTION \
  --field-config=field-path=isDeleted,order=ASCENDING \
  --field-config=field-path=createdAt,order=DESCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Community indexes
echo "Creating community indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=community \
  --query-scope=COLLECTION \
  --field-config=field-path=creatorId,order=ASCENDING \
  --field-config=field-path=createdDate,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

# Subscriptions indexes
echo "Creating subscriptions indexes..."
gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=subscriptions \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=appliedCommunityId,order=ASCENDING \
  --field-config=field-path=activeUntil,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

gcloud firestore indexes composite create \
  --project=$PROJECT_ID \
  --database=$DATABASE_ID \
  --collection-group=subscriptions \
  --query-scope=COLLECTION_GROUP \
  --field-config=field-path=appliedCommunityIds,array-config=CONTAINS \
  --field-config=field-path=activeUntil,order=ASCENDING \
  --async 2>/dev/null || echo "Index may already exist"

echo ""
echo "✅ Index creation initiated for all composite indexes!"
echo "Indexes are building in parallel and will take 5-10 minutes each."
echo "You can check progress at:"
echo "https://console.firebase.google.com/project/$PROJECT_ID/firestore/databases/$DATABASE_ID/indexes"


