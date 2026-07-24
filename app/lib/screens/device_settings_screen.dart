import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/device_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/labeled_field.dart';

/// Rename, view the ID of, or unpair the current device.
class DeviceSettingsScreen extends StatefulWidget {
  const DeviceSettingsScreen({super.key});

  @override
  State<DeviceSettingsScreen> createState() => _DeviceSettingsScreenState();
}

class _DeviceSettingsScreenState extends State<DeviceSettingsScreen> {
  final _nameController = TextEditingController();
  bool _seeded = false;
  bool _savingName = false;
  bool _unpairing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    final device = context.read<DeviceProvider>().device;
    if (device != null) {
      _nameController.text = device.name;
      _seeded = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingName = true);
    try {
      await context.read<DeviceProvider>().renameDevice(name);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Name updated.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not save the name.')));
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _confirmUnpair() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unpair device?'),
        content: const Text(
          'The device will no longer appear in the app. You will need its ID '
          'and PIN to pair it again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Unpair', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final devices = context.read<DeviceProvider>();

    setState(() => _unpairing = true);
    try {
      await devices.unpairDevice();
      // RootGate already shows the pairing screen underneath.
      if (mounted) navigator.pop();
    } catch (_) {
      if (mounted) {
        setState(() => _unpairing = false);
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not unpair the device.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final device = context.watch<DeviceProvider>().device;
    final deviceId = device?.id ?? '—';

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        foregroundColor: context.colors.primary,
        title: Text('Manage device',
            style: AppText.headlineSm.copyWith(color: context.colors.primary)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Device name',
                controller: _nameController,
                icon: Icons.badge_outlined,
                hint: 'e.g. Grandpa\'s watch',
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saveName(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _savingName ? null : _saveName,
                  child: _savingName
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Save name'),
                ),
              ),
              const SizedBox(height: 24),

              Text('Device ID',
                  style: AppText.labelLg.copyWith(color: context.colors.onSurface)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.colors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(deviceId, style: AppText.bodyMd)),
                    IconButton(
                      tooltip: 'Copy',
                      icon: Icon(Icons.copy, size: 20, color: context.colors.primary),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: deviceId));
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('ID copied.')));
                      },
                    ),
                  ],
                ),
              ),

              const Spacer(),

              OutlinedButton.icon(
                onPressed: _unpairing ? null : _confirmUnpair,
                icon: _unpairing
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.link_off, color: context.colors.error),
                label: Text('Unpair',
                    style: AppText.labelLg.copyWith(color: context.colors.error)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: context.colors.error)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
