import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import 'auth/login_screen.dart';
import 'home/home_shell.dart';
import 'messaging_gate.dart';
import 'pairing_screen.dart';
import 'splash_screen.dart';

/// Picks the top-level screen from the session and device state:
///
///   session unknown ............. splash
///   signed out .................. login
///   signed in, loading device ... splash
///   signed in, no device ........ pairing
///   signed in, with device ...... home
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return const SplashScreen();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.authenticated:
        final device = context.watch<DeviceProvider>();
        return MessagingGate(
          child: Builder(
            builder: (_) {
              if (device.loadingDevice) {
                return const SplashScreen(message: 'Loading your device…');
              }
              if (!device.hasDevice) {
                return const PairingScreen();
              }
              return const HomeShell();
            },
          ),
        );
    }
  }
}
