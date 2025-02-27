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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDIGtWggJ4tBjt4mWUpuwokb1ZjxoEHi8s',
    appId: '1:831687325573:web:0b76647799e96a06f2b6ec',
    messagingSenderId: '831687325573',
    projectId: 'test-8e569',
    authDomain: 'test-8e569.firebaseapp.com',
    storageBucket: 'test-8e569.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDIGtWggJ4tBjt4mWUpuwokb1ZjxoEHi8s',
    appId: '1:831687325573:android:0b76647799e96a06f2b6ec',
    messagingSenderId: '831687325573',
    projectId: 'test-8e569',
    storageBucket: 'test-8e569.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'your-ios-api-key',
    appId: 'your-ios-app-id',
    messagingSenderId: '831687325573',
    projectId: 'test-8e569',
    storageBucket: 'test-8e569.firebasestorage.app',
    iosClientId: 'your-ios-client-id',
    iosBundleId: 'your-ios-bundle-id',
  );
} 