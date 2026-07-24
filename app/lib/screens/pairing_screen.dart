import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/device_provider.dart';
import '../services/device_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/error_banner.dart';
import '../widgets/labeled_field.dart';

/// Shown to signed-in users without a device. Claims a device by ID and PIN;
/// on success the device stream updates and [RootGate] moves to the home screen.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _deviceIdController = TextEditingController();
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _deviceIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  String? _validatePin(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Enter the PIN.';
    if (!RegExp(r'^\d{6}$').hasMatch(s)) return 'The PIN has 6 digits.';
    return null;
  }

  Future<void> _pair() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final devices = context.read<DeviceProvider>();
    final uid = auth.user!.uid;

    setState(() => _busy = true);
    try {
      final outcome = await devices.pairDevice(
        _deviceIdController.text,
        uid,
        _pinController.text,
      );
      if (!mounted) return;
      switch (outcome) {
        case PairOutcome.success:
          break;
        case PairOutcome.failed:
          // Deliberately generic: does not reveal which check failed.
          setState(() => _error = 'Wrong ID or PIN, or the device is already paired.');
          break;
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not pair the device. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        title: Text('SafeTrack',
            style: AppText.headlineSm.copyWith(color: context.colors.primary)),
        actions: [
          TextButton(
            onPressed: () => context.read<AuthProvider>().signOut(),
            child: Text('Sign out', style: AppText.labelLg.copyWith(color: context.colors.primary)),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: context.colors.primaryFixed,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_link, color: context.colors.primary, size: 44),
                  ),
                  const SizedBox(height: 24),
                  Text('Pair your device',
                      style: AppText.headlineMd.copyWith(color: context.colors.onSurface)),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your SafeTrack\'s ID and 6-digit PIN to link it to your account.',
                    style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
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
                            label: 'Device ID',
                            controller: _deviceIdController,
                            icon: Icons.qr_code_2,
                            hint: 'device-teste-01',
                            textInputAction: TextInputAction.next,
                            validator: (v) => Validators.notEmpty(v, message: 'Enter the device ID.'),
                          ),
                          const SizedBox(height: 16),
                          LabeledField(
                            label: 'PIN (6 digits)',
                            controller: _pinController,
                            icon: Icons.password,
                            hint: '••••••',
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _pair(),
                            validator: _validatePin,
                          ),
                          const SizedBox(height: 16),
                          ErrorBanner(_error),
                          if (_error != null) const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _busy ? null : _pair,
                            child: _busy
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  )
                                : const Text('Pair device'),
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
