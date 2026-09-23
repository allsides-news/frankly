# Build Versioning Strategy

## Overview

This project now uses **semantic versioning** with auto-incrementing build numbers for all deployments. The version format follows [Semantic Versioning 2.0.0](https://semver.org/) principles.

## Version Format

### Production Builds
```
<MAJOR>.<MINOR>.<PATCH>+<BUILD_NUMBER>
```
Example: `1.0.0+123`

### Staging Builds
```
<MAJOR>.<MINOR>.<PATCH>-staging+<BUILD_NUMBER>
```
Example: `1.0.0-staging+456`

### Preview Builds
```
<MAJOR>.<MINOR>.<PATCH>-preview+<BUILD_NUMBER>
```
Example: `1.0.0-preview+789`

## Version Components

| Component | Source | Description |
|-----------|--------|-------------|
| **Base Version** | `client/pubspec.yaml` | Semantic version (MAJOR.MINOR.PATCH) manually maintained |
| **Build Number** | `github.run_number` | Auto-increments with each workflow run |
| **Environment Label** | Workflow name | Indicates deployment environment (staging/preview) |

## How It Works

### Build Number Auto-Increment

GitHub Actions maintains a `run_number` for each workflow that:
- Starts at 1 for the first run
- Increments by 1 with each subsequent run
- Persists across all runs of the same workflow
- Is independent per workflow (production, staging, and preview each have their own counters)

### Version Extraction

During the build process, workflows:
1. Extract base version from `client/pubspec.yaml` using `grep`
2. Append the current `github.run_number` as the build number
3. Add environment label for non-production builds
4. Set this version in multiple places:
   - `index.html` (`window.platformVersion` and cache busting)
   - Sentry release tracking
   - Flutter build metadata

## Usage Examples

### Incrementing Major/Minor/Patch Version

To update the base version, edit `client/pubspec.yaml`:

```yaml
name: client
description: A platform for deliberations
publish_to: none
version: 2.0.0  # <-- Update this line
```

Changes take effect on the next deployment.

### Version Usage Scenarios

**Bug Fix (Patch):** `1.0.0` → `1.0.1`
```bash
# Edit pubspec.yaml: version: 1.0.1
# Next build will be: 1.0.1+124
```

**New Feature (Minor):** `1.0.1` → `1.1.0`
```bash
# Edit pubspec.yaml: version: 1.1.0
# Next build will be: 1.1.0+125
```

**Breaking Change (Major):** `1.1.0` → `2.0.0`
```bash
# Edit pubspec.yaml: version: 2.0.0
# Next build will be: 2.0.0+126
```

## Troubleshooting

### Version Shows as "vmain" or Wrong Value

This was the **old behavior** before implementing this versioning system. If you see this:
1. Ensure `pubspec.yaml` has a `version:` field
2. Verify the workflow file has the "Set Build Number and Version" step
3. Check that `${{ env.VERSION }}` is used instead of `${{ github.ref_name }}`

### Build Number Not Incrementing

Build numbers increment per workflow, not per repository. Each workflow (production, staging, preview) maintains its own counter. This is expected behavior.

### Cache Issues

The version number is used for cache busting in `index.html`:
```html
<script src="main.dart.js?version=__VERSION__"></script>
```

With auto-incrementing versions, each deployment gets a unique version, preventing browser caching issues.

## Technical Details

### Workflow Changes

All three deployment workflows (`deploy_client_prod.yaml`, `deploy_client_staging.yaml`, `deploy-preview.yml`) now include:

```yaml
- name: Set Build Number and Version
  run: |
    echo "BUILD_NUMBER=${{ github.run_number }}" >> $GITHUB_ENV
    BASE_VERSION=$(grep '^version: ' client/pubspec.yaml | sed 's/version: //')
    VERSION="${BASE_VERSION}+${{ github.run_number }}"  # Add -staging or -preview for non-prod
    echo "VERSION=${VERSION}" >> $GITHUB_ENV
    echo "Building version: ${VERSION}"
```

### Where Version is Used

1. **index.html** - Cache busting and version display
2. **Sentry** - Release tracking and error correlation
3. **Flutter Build** - Build metadata (`--build-number` flag)

## Migration Notes

### Previous Versioning

- **Production**: Used `github.ref_name` (resulted in "main" or "vmain")
- **Staging**: Used `github.sha` (full git commit hash)
- **Preview**: Used `github.sha` (full git commit hash)

### New Versioning

All environments now use consistent semantic versioning with auto-incrementing build numbers, making it easier to:
- Identify specific builds
- Track deployment history
- Troubleshoot cache issues
- Correlate errors in Sentry

## Future Enhancements

Possible improvements:
- Automated version bumping based on commit messages (Conventional Commits)
- Release notes generation from version changes
- Version comparison tools for deployment validation

