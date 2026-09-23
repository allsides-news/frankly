#!/bin/bash
set -e

echo "🚀 Deploying to Production (allsides-roundtables)"
echo "=================================================="

# Set Firebase project
firebase use allsides-roundtables

echo ""
echo "📦 Building Client..."
cd client
flutter build web --release --source-maps -t lib/main.dart
cd ..

echo ""
echo "🔥 Deploying to Firebase Hosting..."
firebase deploy --only hosting --project=allsides-roundtables

echo ""
echo "✅ Deployment Complete!"
echo "🌐 Site URL: https://allsides-roundtables.web.app"

