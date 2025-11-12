#!/bin/bash

# Workaround for build_runner compatibility issues with Dart 3.x
# Generate the build script if it doesn't exist
if [ ! -f .dart_tool/build/entrypoint/build.dart ]; then
  echo "[INFO] Generating build script..."
  dart pub run build_runner:build_runner --help > /dev/null 2>&1 || true
  # Try to trigger script generation without actually running it
  timeout 2 dart run build_runner build --delete-conflicting-outputs $@ 2>/dev/null || true
fi

# If the build script exists, compile and run it directly
if [ -f .dart_tool/build/entrypoint/build.dart ]; then
  echo "[INFO] Compiling build script..."
  dart compile kernel .dart_tool/build/entrypoint/build.dart -o .dart_tool/build/entrypoint/build.dart.dill > /dev/null 2>&1
  
  if [ -f .dart_tool/build/entrypoint/build.dart.dill ]; then
    echo "[INFO] Running build..."
    dart .dart_tool/build/entrypoint/build.dart build --delete-conflicting-outputs $@
    BUILD_EXIT_CODE=$?
    
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
      echo "[INFO] Copying build artifacts to build/ directory..."
      mkdir -p build/node
      cp -r .dart_tool/build/generated/functions/node/* build/node/
      mkdir -p build/js
      cp -r js/* build/js/
      
      echo "[INFO] Adding function export wrapper..."
      cat >> build/node/main.dart.js << 'EOF'

//# Dart functions export wrapper
(function() {
  try {
    // Get the functions object that was used by the Dart code
    const dartFuncs = self.$ && self.$.$get$functions ? self.$.$get$functions() : null;
    
    if (dartFuncs) {
      // Export all properties that look like Cloud Functions
      for (const key in dartFuncs) {
        const val = dartFuncs[key];
        if (val && typeof val === 'object' && (val.__trigger || val.run)) {
          exports[key] = val;
        }
      }
    }
  } catch (e) {
    console.error('[Build] Error exporting functions:', e);
  }
})();
EOF
      
      echo "[INFO] Build completed successfully!"
    fi
    
    exit $BUILD_EXIT_CODE
  fi
fi

# Fallback to original command if workaround fails
echo "[INFO] Using fallback build method..."
dart .dart_tool/build/entrypoint/build.dart build --delete-conflicting-outputs $@
