import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Text field with a label above it and a leading icon.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    required this.icon,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.suffix,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final IconData icon;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final void Function(String)? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.labelLg.copyWith(color: context.colors.onSurface)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          validator: validator,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          style: AppText.bodyMd,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppText.bodyMd.copyWith(color: context.colors.outline),
            prefixIcon: Icon(icon, color: context.colors.outline, size: 22),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}
