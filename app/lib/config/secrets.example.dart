// Copy to secrets.dart (git-ignored) and fill in your keys:
//   cp lib/config/secrets.example.dart lib/config/secrets.dart
class Secrets {
  /// Google Geocoding API key (address search).
  static const String geocodingApiKey = 'YOUR_GEOCODING_API_KEY';

  /// Firebase iOS API key (API_KEY in GoogleService-Info.plist).
  static const String firebaseApiKey = 'YOUR_FIREBASE_IOS_API_KEY';
}
