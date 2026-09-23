Initial AllSides fork: Configure Firebase project and fix critical build issues
This commit represents the initial fork of the Frankly platform for AllSides,
transitioning from the original frankly-1c193 Firebase project to the
allsides-roundtables project.

## Firebase Configuration Changes

### Firebase Functions
- Added .gcloudignore for proper deployment exclusions
- Created index.js wrapper to load Dart-compiled Cloud Functions
- Updated build.sh with improved build script compilation workflow
- Modified package.json and pubspec.yaml dependency versions
- Deployed 70 Cloud Functions successfully to allsides-roundtables project

### Functions Infrastructure Updates
- Fixed Stripe payment integration endpoints (checkout sessions, billing portal, connected accounts)
- Updated Agora API integration for live meeting functionality
- Fixed RSS/ICS calendar feed utilities with proper encoding
- Corrected email template rendering and notification utilities
- Updated cloud tasks client and firestore event handlers
- Fixed share link generation and server timestamp utilities

### Client Configuration
- Added client/firebase_options.dart for AllSides Firebase project
- Created client/firebase.json for project-specific settings
- Updated client/.gitignore to exclude sensitive configuration
- Modified environment.dart to point to allsides-roundtables project

## Critical Build Fixes

### Dart/Flutter Constructor Issues (Fixed 3 missing field initializations)
- Fixed _BottomNavAddIcon missing onTap parameter initialization
- Fixed _CreateCommunityDialog missing showImageEdit parameter
- Fixed _DatePickerHeader missing titleSemanticsLabel parameter

### Client Application Fixes
- Fixed error handling utilities (error_utils.dart)
- Corrected Firestore database service initialization
- Updated cloud functions service endpoints for community and events
- Fixed localization service configuration
- Corrected numerous widget null safety and initialization issues across:
  - Chat widgets
  - Community creation and management
  - Discussion threads
  - Event management and live meetings
  - Video conferencing components
  - User profile and notification systems

### Data Models & Utilities
- Updated community data model field handling
- Fixed web utility functions for browser compatibility
- Corrected matching service algorithm implementations

### Testing Updates
- Fixed function test fixtures for new Firebase project
- Updated live meeting test utilities
- Corrected networking status test configurations

## Deployment Status
All 70 Firebase Cloud Functions successfully deployed to allsides-roundtables:
- Payment & Stripe integration functions
- Community management functions
- Event creation and scheduling functions
- Live meeting & video conferencing functions
- Breakout room orchestration functions
- Discussion thread handlers
- Calendar feed generators (RSS/ICS)
- Webhook handlers (Stripe, Mux)
- Email notification system
- Share link generators

## Project Transition
- Original: frankly-1c193 Firebase project
- New: allsides-roundtables Firebase project
- Branch: frankly-init (to become main branch in allsides-frankly repo)
- Organization: allsides-news (GitHub)
- Repository: allsides-frankly (private)

All changes necessary to build, deploy, and run the Frankly platform
under the AllSides organization with the allsides-roundtables Firebase project.

-0-0-0-0-

# Frankly 💬

Welcome to the Frankly repo!

Frankly is an online deliberations platform that allows anyone to host video-enabled conversations about any topic. Key functionalities include:

- Matching participants into breakout rooms based on survey questions
- Creating structured event templates with different activities to take participants through

The Frankly codebase is AGPL 3.0 licensed (see LICENSE.txt). Dependencies distributed with Frankly (external and vendored) are AGPL compatible and should be consulted as needed.

# Documentation

Please visit our [documentation site](https://berkmancenter.github.io/frankly) for an introduction and overview, installation guide, troubleshooting guide, and FAQ.

