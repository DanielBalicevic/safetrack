import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// SafeTrack logo: a location pin in the brand color with a white dot.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.location_on, size: size, color: context.colors.primaryContainer),
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.22),
            child: Container(
              width: size * 0.30,
              height: size * 0.30,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
