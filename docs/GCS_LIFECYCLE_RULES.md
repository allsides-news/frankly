# GCS Object Lifecycle Rules

These rules must be applied to the Agora recording/transcription storage bucket
whenever the project is deployed to a new environment. Without them, objects
under `temp-downloads/` accumulate indefinitely.

## Required rules

### 1. Delete transcription ZIP files after 1 day

`download-transcription.js` writes a ZIP to `temp-downloads/{eventId}/transcriptions.zip`
on every admin download request. The fixed filename means at most one file per
event exists at any time, but the file is not explicitly deleted (a signed URL
becomes a 404 the moment its underlying object is removed). This lifecycle rule
performs deferred cleanup.

```bash
# One-time setup — run once per GCS bucket (staging and production)
BUCKET="your-agora-storage-bucket-name"   # agora.storage_bucket_name in Firebase config

cat > /tmp/lifecycle.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": { "type": "Delete" },
        "condition": {
          "matchesPrefix": ["temp-downloads/"],
          "age": 1
        }
      }
    ]
  }
}
EOF

gsutil lifecycle set /tmp/lifecycle.json gs://$BUCKET
```

Verify the rule was applied:

```bash
gsutil lifecycle get gs://$BUCKET
```

### Notes

- `age: 1` means objects are deleted when they are at least 1 day old.
  Adjust if a longer retention window is needed.
- This rule has no effect on MP4 recordings (stored under `{eventId}/` and
  `{roomId}/` prefixes) or STT VTT slices (stored under `stt/{roomId}/`).
  It only targets the `temp-downloads/` prefix.
- The bucket name is stored in Firebase Functions config as
  `agora.storage_bucket_name`. Retrieve it with:
  `firebase functions:config:get agora --project <project-id>`
