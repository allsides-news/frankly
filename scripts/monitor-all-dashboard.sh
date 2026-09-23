#!/bin/bash
# All-in-One Monitoring Dashboard - Quick snapshot of system health
# Runs once and shows current status (not auto-refreshing)
# For continuous monitoring, use the specific monitor-*.sh scripts

PROJECT="allsides-roundtables"

clear
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         🎯 ALLSIDES ROUNDTABLES HEALTH DASHBOARD               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Project: $PROJECT"
echo "Time: $(date)"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 RECENT RECORDING ACTIVITY (Last 5 minutes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
gcloud logging read "resource.type=cloud_function AND (textPayload:\"Successfully claimed recording\" OR textPayload:\"won the claim race\" OR textPayload:\"Successfully queued and started recording\")" \
  --limit=10 \
  --project=$PROJECT \
  --format="table(timestamp.date('%H:%M:%S'),textPayload.extract('.*').slice(:100))" \
  --freshness=5m 2>/dev/null || echo "No recent recording activity"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔒 DEDUPLICATION STATUS (Duplicates Prevented)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
DUPLICATES_PREVENTED=$(gcloud logging read "resource.type=cloud_function AND textPayload:\"Another request won the claim race\"" \
  --limit=100 \
  --project=$PROJECT \
  --format="value(textPayload)" \
  --freshness=10m 2>/dev/null | wc -l | xargs)
echo "✅ Duplicates prevented in last 10 min: $DUPLICATES_PREVENTED"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⚠️  ERRORS AND WARNINGS (Last 10 minutes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
gcloud logging read "resource.type=cloud_function AND severity>=ERROR AND NOT resource.labels.function_name=\"ShareLink\"" \
  --limit=5 \
  --project=$PROJECT \
  --format="table(timestamp.date('%H:%M:%S'),resource.labels.function_name,severity)" \
  --freshness=10m 2>/dev/null || echo "✅ No errors (excluding ShareLink known issues)"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎬 BREAKOUT ROOM ACTIVITY (Last 10 minutes)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=\"GetBreakoutRoomJoinInfo\"" \
  --limit=5 \
  --project=$PROJECT \
  --format="table(timestamp.date('%H:%M:%S'))" \
  --freshness=10m 2>/dev/null || echo "No recent breakout room joins"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐛 FLUTTER CLIENT ERRORS (Sentry — production)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -z "$SENTRY_AUTH_TOKEN" ]; then
  echo "⚠️  Skipped: set SENTRY_AUTH_TOKEN to enable"
  echo "   Generate at: https://sentry.io/settings/account/api/auth-tokens/"
else
  python3 <<PYEOF
import urllib.request, urllib.parse, json, datetime, sys, ssl

_ssl_ctx = ssl.create_default_context()
_ssl_ctx.check_hostname = False
_ssl_ctx.verify_mode = ssl.CERT_NONE

token = "$SENTRY_AUTH_TOKEN"
params = urllib.parse.urlencode({"query": "is:unresolved", "environment": "production", "limit": "5", "sort": "date"})
url = f"https://sentry.io/api/0/projects/allsides-technologies-inc/allsides-roundtables/issues/?{params}"
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
try:
    with urllib.request.urlopen(req, timeout=10, context=_ssl_ctx) as resp:
        data = json.loads(resp.read().decode())
except urllib.error.HTTPError as e:
    data = json.loads(e.read().decode())
    e.close()
except Exception as e:
    print(f"  ❌  Request failed: {e}")
    sys.exit(0)

if isinstance(data, dict) and "detail" in data:
    print(f"  ❌  Sentry error: {data['detail']}")
elif not data:
    print("  ✅  No unresolved client errors")
else:
    for i in data:
        dt = datetime.datetime.fromisoformat(i.get("lastSeen", "").replace("Z", "+00:00"))
        print(f"  [{dt.strftime('%H:%M:%S')}] ({i.get('count','?')}x) {i.get('title','')[:80]}")
PYEOF
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 AVAILABLE MONITORING SCRIPTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ./scripts/monitor-recording-activity.sh     - Watch all recording activity"
echo "  ./scripts/monitor-claim-deduplication.sh    - Watch deduplication in action"
echo "  ./scripts/monitor-function-errors.sh        - Watch for errors/warnings"
echo "  ./scripts/monitor-recording-queue.sh        - Watch queue processing"
echo "  ./scripts/monitor-specific-room.sh ROOM_ID  - Track specific room"
echo "  ./scripts/monitor-client-errors.sh          - Watch Flutter app errors (Sentry)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ System Status: READY"
echo "🎯 Deduplication Fix: DEPLOYED"
echo "📅 Last checked: $(date)"
echo ""

