import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '',
    authDomain: 'edurishit.firebaseapp.com',
    projectId: 'edurishit',
    storageBucket: 'edurishit.firebasestorage.app',
    messagingSenderId: '350183278922',
    appId: '1:350183278922:web:d2b0a6a3efa72461e3d9b3',
  );
}
