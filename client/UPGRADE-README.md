# Flutter 3.41.4 Upgrade Guide

This document details all changes made to upgrade the Flutter client application from Flutter 3.22.2 to Flutter 3.41.4.

## Overview

The upgrade addresses breaking API changes in Flutter 3.41.4 including:
- JavaScript interop migrated off deprecated **`dart:js_util`** to **`dart:js_interop`** / stubs (`dart.library.html`)
- `platformViewRegistry` moved to `dart:ui_web`
- `InputDecorationTheme` type changes
- `google_fonts` package updates
- Localization system changes

## Prerequisites

- Flutter 3.41.4 or later
- Dart 3.11.1 or later
- **macOS users**: Xcode Command Line Tools (for `sort` command)
  ```bash
  xcode-select --install
  ```

## Quick Start

If you're checking out this branch on a new machine (Linux or macOS), run:

```bash
cd client
./update.sh
```

This will install dependencies, apply patches, generate localization files, and optionally build the app.

**Note**: The script automatically detects your OS and adjusts commands for compatibility.

### Patch bootstrap (git vs CI)

Only **overlay** files under `client/patches/` are tracked; full upstream trees are fetched by **`client/bootstrap_patches.sh`** (pub.dev tarball + shallow git clone). [`update.sh`](./update.sh) calls this script non-interactively first.

GitHub Actions client workflows run the same script **before** `flutter pub get`, so CI matches local developer setup.

### Web renderer / platform views (Flutter 3.41+)

The **`--web-renderer html`** flag was **removed** from `flutter build web`; builds use the toolchain default composition pipeline (distinct from legacy HTML renderer behavior).

**Suggested manual QA after upgrading or changing video/embed code:**

- Vimeo (`VimeoVideoWidget`), Video.js canvas (`CanvasKitUrlVideoWidget`), YouTube iframe (`youtube_player_iframe_web`), Agora live meeting video (`HtmlElementView` / WebRTC): pointer hit-testing, z-order/stacking, fullscreen, controls.

## Detailed Changes

### 1. External Package Patches

Two external packages required patching for Flutter 3.41.4 compatibility:

#### youtube_player_iframe_web (v2.0.2)
**Location:** `client/patches/youtube_player_iframe_web-2.0.2/`

**Changes:**
- Added `import 'dart:ui_web' as ui_web;`
- Changed `ui.platformViewRegistry` to `ui_web.platformViewRegistry`
- **`window.onMessage`** for the YoutubePlayer JS channel is owned by a **`StatefulWidget`** subview so subscriptions are cancelled on dispose and before rebinding when **`HtmlElementView`** is recreated (avoids stacked listeners).

**File modified:** `lib/src/web_youtube_player_iframe_controller.dart`

#### agora_rtc_engine (v6.3.0)
**Location:** `client/patches/agora_rtc_engine/`

**Changes:**
- Added `import 'dart:ui_web' as ui_web;`
- Changed `ui.platformViewRegistry` to `ui_web.platformViewRegistry`
- Removed `// ignore: undefined_prefixed_name` comment

**File modified:** `lib/src/impl/platform/web/global_video_view_controller_platform_web.dart`

### 2. Dependency Configuration

**File:** `client/pubspec.yaml`

Added dependency overrides to use patched packages:

```yaml
dependency_overrides:
  collection: ^1.19.0
  http_parser: ^4.1.0
  intl: ^0.19.0
  # Patched versions for Flutter 3.41.4 compatibility
  youtube_player_iframe_web:
    path: patches/youtube_player_iframe_web-2.0.2
  agora_rtc_engine:
    path: patches/agora_rtc_engine
```

Updated packages:
- `google_fonts: ^8.1.0` (from ^4.0.4)

### 3. JavaScript Interop Migration

Web-only bridges use **`dart:js_interop`** and **`dart:js_interop_unsafe`** (not deprecated **`dart:js_util`**). Conditional imports gate implementations with **`dart.library.html`** so VM/mobile analysis keeps using stubs.

**`lib/core/utils/js_interop_bridge_web.dart`** exposes helpers such as **`jsHasProperty`**, **`jsCallMethod`**, **`jsJsify`**, plus **`jsInteropVoid`** / **`jsInteropDynamicPair`** for callbacks passed into legacy JS APIs — **`Function.toJS`** requires a statically known closure type, so a single generic `allowInterop(Function)` wrapper does not compile on Dart 3.5+.

Other web shards: **`check_can_autoplay_future_web.dart`**, **`sidebar_platform_version_web.dart`**, **`stripe_checkout_redirect_web.dart`**, **`media_helper_cloudinary_web.dart`**, and **`patches/agora_rtc_engine/.../iris_js_promise_web.dart`** use the same interop stack (`JSPromise.toDart`, `.jsify()` / `.dartify()`, unsafe `JSObject` helpers).

- **`lib/core/utils/meta_tag_service.dart`**: uses native DOM APIs (`setAttribute`) instead of JS interop where possible.

### 4. Platform View Registry Fix

**File:** `lib/core/utils/web_utils.dart`

Added `dart:ui_web` import and updated registration:

```dart
import 'dart:ui_web' as ui_web;

// Changed from:
ui.platformViewRegistry.registerViewFactory(key, factory);

// To:
ui_web.platformViewRegistry.registerViewFactory(key, factory);
```

### 5. InputDecorationTheme Fix

**File:** `lib/features/events/features/create_event/presentation/widgets/custom_time_picker.dart`

Fixed type mismatch:
- Changed explicit `InputDecorationTheme?` type to use type inference
- Resolves to `InputDecorationThemeData?` which is the correct type in Flutter 3.41.4

### 6. Localization Configuration

**File:** `client/l10n.yaml`

Removed deprecated `synthetic-package` option:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
use-deferred-loading: false
untranslated-messages-file: missing.json
```

**Files with Import Changes:**
- `lib/app.dart`: Changed to `import 'l10n/app_localizations.dart';`
- `lib/core/localization/localization_helper.dart`: Changed to `import '../../l10n/app_localizations.dart';`
- `lib/core/localization/app_localization_service.dart`: Changed to `import '../../l10n/app_localizations.dart';`

Localization files are now generated directly in `lib/l10n/` instead of `.dart_tool/flutter_gen/`.

## Migration Patterns

### JavaScript Interop Pattern

**Old (dart:js_interop_unsafe):**
```dart
import 'dart:js_interop' as js;
import 'dart:js_interop_unsafe' as js_unsafe;

js_unsafe.callMethod(
  object as js.JSAny,
  'methodName'.toJS,
  [args.jsify()].toJS,
);
```

**New (package:js/js_util.dart):**
```dart
import 'package:js/js_util.dart' as js_util;

js_util.callMethod(object, 'methodName', [
  js_util.jsify(args),
]);
```

### Platform View Registry Pattern

**Old:**
```dart
import 'dart:ui' as ui;

ui.platformViewRegistry.registerViewFactory(id, factory);
```

**New:**
```dart
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

ui_web.platformViewRegistry.registerViewFactory(id, factory);
```

## Testing

After applying updates:

1. **Verify dependencies:**
   ```bash
   flutter pub get
   ```

2. **Check for analysis issues:**
   ```bash
   flutter analyze
   ```

3. **Build for web:**
   ```bash
   flutter build web --release
   ```

4. **Run development server:**
   ```bash
   flutter run -d web-server --web-port=8090
   ```

5. **Access app:**
   Open `http://localhost:8090` in your browser

## Known Issues

- `file_picker` package warnings about plugin implementation (non-critical, does not affect web builds)
- Some packages have newer versions available but are incompatible with current dependency constraints

## Rollback

To rollback these changes:

1. Delete `client/patches/` directory
2. Remove dependency overrides from `pubspec.yaml`
3. Revert all code changes in the modified files listed above
4. Downgrade Flutter to 3.22.2

## Support

For issues or questions about this upgrade:
- Review the Flutter 3.41.4 migration guide
- Check `dart:ui_web` documentation
- Review JavaScript interop updates in Flutter

## Changelog

### 2026-05-12
- Initial Flutter 3.41.4 upgrade
- Patched `youtube_player_iframe_web` and `agora_rtc_engine`
- Migrated all JS interop code to `package:js/js_util.dart`
- Fixed `platformViewRegistry` usage
- Updated localization configuration
- All builds passing successfully
