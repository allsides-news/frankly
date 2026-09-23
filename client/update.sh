#!/bin/bash

# Flutter 3.41.4 Update Script
# This script sets up the Flutter client application after checkout
# Compatible with Linux and macOS

set -e  # Exit on error

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Darwin*)    IS_MAC=true;;
    Linux*)     IS_MAC=false;;
    *)          IS_MAC=false;;
esac

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function for semantic version comparison
version_ge() {
    # Returns 0 (true) if $1 >= $2
    # Works on both Linux and macOS
    printf '%s\n%s\n' "$2" "$1" | sort -V -C 2>/dev/null || \
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -t. -k1,1n -k2,2n -k3,3n | head -n1)" = "$2" ]
}

# Helper functions
print_step() {
    echo -e "${BLUE}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
    print_error "pubspec.yaml not found. Please run this script from the client directory."
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   Flutter 3.41.4 Update Script            ║"
echo "╚════════════════════════════════════════════╝"
echo ""

if [ "$IS_MAC" = true ]; then
    echo "Detected macOS"
else
    echo "Detected Linux"
fi
echo ""

# Step 1: Check Flutter version
print_step "Checking Flutter version..."
# Portable version extract (avoid grep -oP: GNU-only; macOS BSD grep rejects -P)
FLUTTER_VERSION=$(flutter --version 2>/dev/null | head -n 1 | sed -nE 's/.*Flutter ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
if [ -z "$FLUTTER_VERSION" ]; then
    print_error "Could not parse Flutter version. Is Flutter on your PATH?"
    exit 1
fi
echo "Current Flutter version: $FLUTTER_VERSION"

# Use semantic version comparison (works on both Linux and macOS)
if ! version_ge "$FLUTTER_VERSION" "3.41.4"; then
    print_warning "Flutter version $FLUTTER_VERSION detected. Flutter 3.41.4 or higher is recommended."
    echo "To upgrade Flutter, run: flutter upgrade"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    print_success "Flutter version is compatible"
fi

# Step 2: Patched path deps must be *full* packages (Git tracks overlays only — see bootstrap_patches.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
print_step "Verifying / bootstrapping patched packages..."
export AGORA_PATCH_REPO="${AGORA_PATCH_REPO:-https://github.com/berkmancenter/Agora-Flutter-SDK.git}"
export YOUTUBE_IFRAME_WEB_VERSION="${YOUTUBE_IFRAME_WEB_VERSION:-2.0.2}"
if ! bash "${SCRIPT_DIR}/bootstrap_patches.sh"; then
    print_error "Patch bootstrap failed."
    exit 1
fi
print_success "Patched packages ready"

# Step 3: Clean build artifacts
print_step "Cleaning build artifacts..."
flutter clean > /dev/null 2>&1
print_success "Build artifacts cleaned"

# Step 4: Get dependencies
print_step "Fetching dependencies..."
flutter pub get 2>&1 | tee /tmp/flutter_pub_get.log
pub_exit=${PIPESTATUS[0]}
if [[ "$pub_exit" -eq 0 ]]; then
    print_success "Dependencies fetched successfully"
    
    # Check for overridden packages
    if grep -q "youtube_player_iframe_web.*from path" /tmp/flutter_pub_get.log; then
        print_success "Using patched youtube_player_iframe_web"
    fi
    if grep -q "agora_rtc_engine.*from path" /tmp/flutter_pub_get.log; then
        print_success "Using patched agora_rtc_engine"
    fi
else
    print_error "Failed to fetch dependencies"
    exit 1
fi

# Step 5: Generate localization files
print_step "Generating localization files..."
if flutter gen-l10n > /dev/null 2>&1; then
    print_success "Localization files generated"
    
    # Verify l10n files exist
    if [ -f "lib/l10n/app_localizations.dart" ]; then
        print_success "app_localizations.dart exists"
    else
        print_warning "app_localizations.dart not found in lib/l10n/"
    fi
else
    print_error "Failed to generate localization files"
    exit 1
fi

# Step 6: Run Flutter analyze (optional, continue on warnings)
print_step "Running Flutter analyze..."
if flutter analyze --no-fatal-infos > /tmp/flutter_analyze.log 2>&1; then
    print_success "No analysis errors found"
else
    print_warning "Analysis completed with some issues (see /tmp/flutter_analyze.log)"
    echo "This is usually okay - the app should still build."
fi

# Step 7: Ask about building
echo ""
read -p "Would you like to build the web app now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_step "Building web app (this may take a minute)..."
    flutter build web --release 2>&1 | tee /tmp/flutter_build.log
    build_exit=${PIPESTATUS[0]}
    if [[ "$build_exit" -eq 0 ]]; then
        print_success "Web app built successfully!"
        echo "Output: build/web/"
    else
        print_error "Build failed. Check /tmp/flutter_build.log for details"
        exit 1
    fi
fi

# Step 8: Summary
echo ""
echo "╔════════════════════════════════════════════╗"
echo "║   Setup Complete!                          ║"
echo "╚════════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "  To run the development server:"
echo "    ${GREEN}flutter run -d web-server --web-port=8090${NC}"
echo ""
echo "  To build for production:"
echo "    ${GREEN}flutter build web --release${NC}"
echo ""
echo "  To view the app:"
echo "    Open ${GREEN}http://localhost:8090${NC} in your browser"
echo ""
echo "For more information, see UPGRADE-README.md"
echo ""

print_success "All done!"
