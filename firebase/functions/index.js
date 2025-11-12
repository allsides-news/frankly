// Patch firebase-admin to support named databases
// Database ID to use (configured for default database)
const FIREBASE_DATABASE_ID = process.env.FIREBASE_DATABASE_ID || '(default)';

console.log(`[Named DB Config] Using Firestore database: ${FIREBASE_DATABASE_ID}`);

// Set environment variable for @google-cloud/firestore
// This is picked up by the Firestore constructor
process.env.FIRESTORE_DATABASE_ID = FIREBASE_DATABASE_ID;

// Patch firebase-admin module loading
const Module = require('module');
const originalRequire = Module.prototype.require;

Module.prototype.require = function(id) {
  const module = originalRequire.apply(this, arguments);
  
  // Intercept firebase-admin and patch it
  if (id === 'firebase-admin' && !module.__firestore_patched) {
    const admin = module;
    const originalFirestore = admin.firestore.bind(admin);
    let firestoreInstance = null;
    
    // Override admin.firestore() to inject database ID
    admin.firestore = function(app) {
      if (firestoreInstance) {
        return firestoreInstance;
      }
      
      // Call original to get initialized instance
      firestoreInstance = originalFirestore(app);
      
      // Monkey-patch the settings to use named database
      // This works with the Firestore internal implementation
      const originalSettings = firestoreInstance._settings || {};
      
      Object.defineProperty(firestoreInstance, '_settings', {
        get: function() {
          return {
            ...originalSettings,
            databaseId: FIREBASE_DATABASE_ID
          };
        },
        set: function(val) {
          // Preserve other settings but override databaseId
          Object.assign(originalSettings, val);
          originalSettings.databaseId = FIREBASE_DATABASE_ID;
        }
      });
      
      // Also patch _referencePath which is used internally
      const originalReferencePath = firestoreInstance._referencePath || {};
      Object.defineProperty(firestoreInstance, '_referencePath', {
        get: function() {
          return {
            ...originalReferencePath,
            databaseId: FIREBASE_DATABASE_ID
          };
        }
      });
      
      console.log(`[Named DB Config] Patched Firestore instance to use: ${FIREBASE_DATABASE_ID}`);
      return firestoreInstance;
    };
    
    module.__firestore_patched = true;
  }
  
  return module;
};

// Simple wrapper that loads the Dart-compiled code
module.exports = require('./build/node/main.dart.js');

