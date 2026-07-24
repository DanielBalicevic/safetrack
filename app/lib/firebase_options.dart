// Firebase options for the iOS app, matching ios/Runner/GoogleService-Info.plist.
// The API key is read from config/secrets.dart.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

import 'config/secrets.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
        throw UnsupportedError(
          'Android is not configured. Run `flutterfire configure` to add it.',
        );
      default:
        throw UnsupportedError('Unsupported platform.');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: Secrets.firebaseApiKey,
    appId: '1:167177354370:ios:9e580fd1a0f3a4cb57c89b',
    messagingSenderId: '167177354370',
    projectId: 'safetrack-b46b1',
    storageBucket: 'safetrack-b46b1.firebasestorage.app',
    iosBundleId: 'com.danielbalicevic.safetrack',
    iosClientId:
        '167177354370-pcoe6msv8ui96eivpg2d8bmqdb73mc2u.apps.googleusercontent.com',
  );
}
