import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/labeled_field.dart';

/// Account creation. Firebase signs the new user in, so the screen pops and
/// [RootGate] shows the next step.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final error = await auth.registerWithEmail(
      _emailController.text,
      _passwordController.text,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() => _error = error);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
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
              child: Column(
                children: [
                  const BrandLogo(size: 72),
                  const SizedBox(height: 12),
                  Text('Create account',
                      style: AppText.headlineMd.copyWith(color: context.colors.primary)),
                  const SizedBox(height: 4),
                  Text('Start keeping your loved ones safe',
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
                            textInputAction: TextInputAction.next,
                            validator: Validators.email,
                          ),
                          const SizedBox(height: 16),
                          LabeledField(
                            label: 'Password',
                            controller: _passwordController,
                            icon: Icons.lock_outline,
                            hint: '••••••••',
                            obscureText: _obscure,
                            textInputAction: TextInputAction.next,
                            validator: Validators.password,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: context.colors.outline,
                                size: 22,
                              ),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          const SizedBox(height: 16),
                          LabeledField(
                            label: 'Confirm Password',
                            controller: _confirmController,
                            icon: Icons.lock_outline,
                            hint: '••••••••',
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            validator: (value) {
                              if ((value ?? '').isEmpty) return 'Confirm your password.';
                              if (value != _passwordController.text) {
                                return 'Passwords do not match.';
                              }
                              return null;
                            },
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
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5, color: Colors.white),
                                  )
                                : const Text('Create account'),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Already have an account? ',
                                    style: AppText.bodySm.copyWith(color: context.colors.onSurfaceVariant)),
                                GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Text('Login',
                                      style: AppText.bodySm.copyWith(
                                          color: context.colors.primary, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
