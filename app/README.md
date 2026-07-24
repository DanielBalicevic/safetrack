# SafeTrack caregiver app

Flutter app (iOS) for caregivers: live map, safe zones, position history and
alerts.

## Structure

```
lib/
  models/      Firestore documents (Device, Zone, TelemetryPoint, AppAlert)
  services/    Firebase Auth, Firestore, FCM and Geocoding access
  providers/   App state (ChangeNotifier + provider)
  screens/     UI; RootGate picks the top-level screen
  widgets/     Shared widgets
  theme/       Light and dark themes
```

Screens read state from providers, providers call services, and services are
the only code that talks to Firebase. Firestore data is consumed as streams,
so the map and the alerts update as soon as the backend writes.

`RootGate` chooses the screen from the session and device state: splash while
loading, login when signed out, pairing when the user has no device, and the
home screen otherwise.

Inside/outside checks use the same Haversine and ray casting rules as the
backend (`functions/geo.js`), so the app and the alerts always agree.

## Setup

```bash
cp lib/config/secrets.example.dart lib/config/secrets.dart   # fill in the keys
cp ios/Runner/GoogleService-Info.example.plist ios/Runner/GoogleService-Info.plist
cp ios/Flutter/Secrets.example.xcconfig ios/Flutter/Secrets.xcconfig     # Google Maps key
flutter pub get
flutter run
```

Use your own Firebase project's `GoogleService-Info.plist` (or run
`flutterfire configure`).

If the project is inside an iCloud-synced folder, run
`bash tools/relink-build.sh` once after `flutter clean`, otherwise iOS code
signing fails.

## Tests

```bash
flutter analyze
flutter test
```
