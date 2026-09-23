# Firebase Database Migration Scripts

Helper scripts for managing the Firestore database migration to `allsides-roundtables-db`.

## 📧 Email Testing

### send-test-email.sh
Send a test email using the Trigger Email extension via REST API.

```bash
./scripts/send-test-email.sh
```

**What it does:**
- Creates a document in the `mail` collection
- Trigger Email extension processes it automatically
- Email sent to `scott@allsides.com`

### test-trigger-email.js
Send a test email using Node.js and firebase-admin.

**Usage:**
```bash
cd firebase/functions
node ../../scripts/test-trigger-email.js [email@example.com]
```

**Requirements:**
- Must run from `firebase/functions` directory (where firebase-admin is installed)
- Requires gcloud authentication: `gcloud auth application-default login`

**Example:**
```bash
cd firebase/functions
node ../../scripts/test-trigger-email.js your@email.com
```

## 🔧 Index Management

### create-all-indexes.sh
Create all composite indexes for the database.

```bash
./scripts/create-all-indexes.sh
```

**⚠️ IMPORTANT:** This script only creates composite indexes via gcloud commands. It does NOT deploy field-level index exemptions (fieldOverrides).

**RECOMMENDED APPROACH:**
```bash
# Deploy both composite indexes AND field-level exemptions
firebase deploy --only firestore:indexes --project allsides-roundtables
```

**What create-all-indexes.sh does:**
- Creates 20+ composite indexes defined in `firestore.indexes.json`
- Indexes build in parallel (5-10 minutes each)
- Safe to run multiple times (skips existing indexes)
- ⚠️ Misses field-level index exemptions (fieldOverrides)

**Check progress:**
https://console.firebase.google.com/project/allsides-roundtables/firestore/databases/(default)/indexes

### deploy-indexes.sh
Guide and helper for deploying indexes.

```bash
./scripts/deploy-indexes.sh
```

**Shows:**
- Firebase Console URL for manual index creation
- Example gcloud commands
- Total index count

## 🔒 Rules Deployment

### deploy-rules-to-named-db.sh
Deploy Firestore security rules to the named database via REST API.

```bash
./scripts/deploy-rules-to-named-db.sh
```

**What it does:**
- Reads rules from `firebase/firestore/firestore.rules`
- Deploys to `allsides-roundtables-db` using Firestore REST API
- Requires gcloud authentication

**Note:** Firebase Console is often easier for rules deployment:
https://console.firebase.google.com/project/allsides-roundtables/firestore/databases/allsides-roundtables-db/rules

## 📋 Prerequisites

All scripts require:
- **gcloud CLI** installed and authenticated (`gcloud auth login`)
- **Firebase CLI** installed (`npm install -g firebase-tools`)
- **jq** for JSON processing (`brew install jq`)

## 🎯 Quick Start - New Database Setup

If you need to set up another named database in the future:

```bash
# 1. Export from source database
gcloud firestore export gs://BUCKET/backup --project=PROJECT_ID

# 2. Import to new database
gcloud firestore import gs://BUCKET/backup --project=PROJECT_ID --database=NEW_DB_ID

# 3. Create indexes
./scripts/create-all-indexes.sh

# 4. Deploy rules
./scripts/deploy-rules-to-named-db.sh

# 5. Test email extension
./scripts/send-test-email.sh
```

## 🐛 Troubleshooting

### "The query requires a COLLECTION_GROUP_ASC index" Error

**Symptom:** Getting Firestore index errors like:
```
[cloud_firestore/failed-precondition] The query requires a COLLECTION_GROUP_ASC 
index for collection events and field communityId
```

**Cause:** The `fieldOverrides` section in `firestore.indexes.json` hasn't been deployed. These define field-level index exemptions that allow certain fields to be indexed at the COLLECTION_GROUP scope.

**Solution:**
```bash
firebase deploy --only firestore:indexes --project allsides-roundtables
```

**Wait time:** Indexes take 5-10 minutes to build. Check progress:
- Default DB: https://console.firebase.google.com/project/allsides-roundtables/firestore/databases/(default)/indexes
- Named DB: https://console.firebase.google.com/project/allsides-roundtables/firestore/databases/allsides-roundtables-db/indexes

### Index Build Status

To check if indexes are still building:
```bash
# For default database
gcloud firestore indexes composite list --project=allsides-roundtables --database="(default)"

# For named database  
gcloud firestore indexes composite list --project=allsides-roundtables --database="allsides-roundtables-db"

# Check for indexes still building
gcloud firestore indexes composite list --project=allsides-roundtables --database="(default)" | grep CREATING
```

Look for indexes with `state: CREATING`. When they show `state: READY`, they're done. If `grep CREATING` returns nothing, all indexes are ready.

## 📚 Related Documentation

- **Migration Summary:** `../MIGRATION-SUMMARY.md`
- **Firestore Rules:** `../firebase/firestore/firestore.rules`
- **Index Definitions:** `../firebase/firestore/firestore.indexes.json`
- **Firebase Console:** https://console.firebase.google.com/project/allsides-roundtables

---

**Last Updated:** October 8, 2025

