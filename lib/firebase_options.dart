// File generated manually from google-services.json
// This provides FirebaseOptions for all platforms.
//
// To regenerate, run: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ── Android options (from google-services.json) ──
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCI3uFuMbVQYKaQ9qaCICEbEvv7vpNbc94',
    appId: '1:672370147410:android:b2c05818765e58926d9f8b',
    messagingSenderId: '672370147410',
    projectId: 'chat-1b759',
    storageBucket: 'chat-1b759.firebasestorage.app',
  );

  // ── Web options ──
  // IMPORTANT: You need to add a Web app in Firebase Console to get the
  // correct web API key. For now, using the Android API key as a fallback.
  // To get the proper web config:
  //   1. Go to Firebase Console → Project Settings → General
  //   2. Scroll to "Your apps" → Click "Add app" → Web (</> icon)
  //   3. Register the app → Copy the firebaseConfig values
  //   4. Replace the values below
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCI3uFuMbVQYKaQ9qaCICEbEvv7vpNbc94',
    appId: '1:672370147410:android:b2c05818765e58926d9f8b',
    messagingSenderId: '672370147410',
    projectId: 'chat-1b759',
    storageBucket: 'chat-1b759.firebasestorage.app',
    authDomain: 'chat-1b759.firebaseapp.com',
  );

  // ── iOS options (placeholder — update if needed) ──
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCI3uFuMbVQYKaQ9qaCICEbEvv7vpNbc94',
    appId: '1:672370147410:android:b2c05818765e58926d9f8b',
    messagingSenderId: '672370147410',
    projectId: 'chat-1b759',
    storageBucket: 'chat-1b759.firebasestorage.app',
    iosBundleId: 'com.resonance.resonanceChat',
  );
}
