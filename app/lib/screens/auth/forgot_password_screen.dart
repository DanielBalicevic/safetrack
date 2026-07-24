import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/labeled_field.dart';

/// Sends a Firebase password reset email. The confirmation does not reveal
/// whether the account exists.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  String? _error;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final error = await auth.sendPasswordReset(_emailController.text);
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
    } else {
      setState(() => _sent = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().busy;

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        foregroundColor: context.colors.primary,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sent ? _buildSent() : _buildForm(busy),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(bool busy) {
    return Column(
      children: [
        const BrandLogo(size: 72),
        const SizedBox(height: 12),
        Text('Recover password',
            style: AppText.headlineMd.copyWith(color: context.colors.primary)),
        const SizedBox(height: 4),
        Text('Enter your email and we\'ll send you a reset link.',
            style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Email Address',
                  controller: _emailController,
                  icon: Icons.mail_outline,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: Validators.email,
                ),
                const SizedBox(height: 16),
                ErrorBanner(_error),
                if (_error != null) const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Send reset link'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSent() {
    return Column(
      children: [
        const SizedBox(height: 32),
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: context.colors.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.mark_email_read_outlined,
              color: context.colors.onSecondaryContainer, size: 44),
        ),
        const SizedBox(height: 24),
        Text('Check your inbox',
            style: AppText.headlineMd.copyWith(color: context.colors.onSurface)),
        const SizedBox(height: 8),
        Text(
          'If an account exists for ${_emailController.text.trim()}, '
          'you\'ll receive a link to reset your password.',
          style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to login'),
        ),
      ],
    );
  }
}
