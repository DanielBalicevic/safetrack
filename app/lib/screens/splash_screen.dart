import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/brand_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandLogo(size: 112),
            const SizedBox(height: 16),
            Text('SafeTrack', style: AppText.headlineLg.copyWith(color: context.colors.primary)),
            const SizedBox(height: 8),
            Text(
              message ?? 'Reliable care for peace of mind',
              style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: context.colors.primaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}
