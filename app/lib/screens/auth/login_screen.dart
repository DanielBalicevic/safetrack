import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/brand_logo.dart';
import '../../widgets/error_banner.dart';
import '../../widgets/labeled_field.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Email/password and Google sign-in. Navigation after sign-in is handled
/// by [RootGate].
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final error = await auth.signInWithEmail(
      _emailController.text,
      _passwordController.text,
    );
    if (error != null && mounted) setState(() => _error = error);
  }

  Future<void> _google() async {
    setState(() => _error = null);
    final auth = context.read<AuthProvider>();
    final error = await auth.signInWithGoogle();
    if (error != null && mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) {
    final busy = context.watch<AuthProvider>().busy;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const BrandLogo(size: 96),
                  const SizedBox(height: 16),
                  Text('SafeTrack',
                      style: AppText.headlineLg.copyWith(color: context.colors.primary)),
                  const SizedBox(height: 4),
                  Text('Reliable care for peace of mind',
                      style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant)),
                  const SizedBox(height: 32),

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
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
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
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
                              ),
                              child: Text('Forgot password?',
                                  style: AppText.labelMd.copyWith(color: context.colors.primary)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ErrorBanner(_error),
                          if (_error != null) const SizedBox(height: 16),

                          ElevatedButton(
                            onPressed: busy ? null : _submit,
                            child: busy
                                ? const _ButtonSpinner()
                                : const Text('Login'),
                          ),
                          const SizedBox(height: 16),

                          Row(
                            children: [
                              Expanded(child: Divider(color: context.colors.outlineVariant)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('OR',
                                    style: AppText.labelMd.copyWith(color: context.colors.outline)),
                              ),
                              Expanded(child: Divider(color: context.colors.outlineVariant)),
                            ],
                          ),
                          const SizedBox(height: 16),

                          OutlinedButton.icon(
                            onPressed: busy ? null : _google,
                            icon: Icon(Icons.g_mobiledata, size: 28, color: context.colors.primary),
                            label: const Text('Continue with Google'),
                          ),
                          const SizedBox(height: 16),

                          Center(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text("Don't have an account? ",
                                    style: AppText.bodySm.copyWith(color: context.colors.onSurfaceVariant)),
                                GestureDetector(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                                  ),
                                  child: Text('Create account',
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

/// Small white spinner shown inside buttons while busy.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
    );
  }
}
