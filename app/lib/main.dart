import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_keys.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'providers/device_provider.dart';
import 'providers/geocoding_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/root_gate.dart';
import 'theme/app_theme.dart';

/// FCM handler for messages received while the app is in the background.
/// It runs in its own isolate, so Firebase must be initialized here too.
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
  runApp(const SafeTrackApp());
}

class SafeTrackApp extends StatelessWidget {
  const SafeTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => GeocodingProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // The device state follows the signed-in user.
        ChangeNotifierProxyProvider<AuthProvider, DeviceProvider>(
          create: (_) => DeviceProvider(),
          update: (_, auth, device) {
            device!.updateUser(auth.user?.uid);
            return device;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          title: 'SafeTrack',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.mode,
          scaffoldMessengerKey: scaffoldMessengerKey,
          home: const RootGate(),
        ),
      ),
    );
  }
}
