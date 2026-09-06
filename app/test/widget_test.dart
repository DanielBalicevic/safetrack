import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetrack/theme/app_theme.dart';
import 'package:safetrack/widgets/brand_logo.dart';

void main() {
  testWidgets('BrandLogo renders the pin icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(body: Center(child: BrandLogo())),
      ),
    );

    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.byIcon(Icons.location_on), findsOneWidget);
  });
}
