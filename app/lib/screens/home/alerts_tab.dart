import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/app_alert.dart';
import '../../providers/device_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/map_styles.dart';

/// Live list of the device's alerts, with a filter and a resolve action.
class AlertsTab extends StatefulWidget {
  const AlertsTab({super.key});

  @override
  State<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<AlertsTab> {
  bool _onlyUnresolved = false;

  // Cached per device: a new stream on every build would make the
  // StreamBuilder resubscribe and flash the spinner.
  Stream<List<AppAlert>>? _stream;
  String? _boundId;

  @override
  Widget build(BuildContext context) {
    // Select only the device id so telemetry updates do not rebuild this screen.
    final deviceId = context.select<DeviceProvider, String?>((d) => d.deviceId);
    if (deviceId != _boundId) {
      _boundId = deviceId;
      _stream = context.read<DeviceProvider>().watchAlerts();
    }

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        title: Text('Alerts', style: AppText.headlineSm.copyWith(color: context.colors.primary)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: !_onlyUnresolved,
                  onTap: () => setState(() => _onlyUnresolved = false),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Unresolved',
                  selected: _onlyUnresolved,
                  onTap: () => setState(() => _onlyUnresolved = true),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<AppAlert>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) return const _AlertsError();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var alerts = snapshot.data ?? const <AppAlert>[];
                if (_onlyUnresolved) {
                  alerts = alerts.where((a) => !a.resolved).toList();
                }
                if (alerts.isEmpty) return const _EmptyAlerts();

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: alerts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _AlertCard(
                    alert: alerts[i],
                    onResolve: () => _resolve(alerts[i].id),
                    onViewMap: () => _showOnMap(context, alerts[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(String id) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<DeviceProvider>().resolveAlert(id);
      messenger.showSnackBar(const SnackBar(content: Text('Alert resolved.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not resolve the alert.')));
    }
  }

  void _showOnMap(BuildContext context, AppAlert alert) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _AlertMapSheet(alert: alert),
    );
  }
}

class _AlertsError extends StatelessWidget {
  const _AlertsError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off, size: 44, color: context.colors.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('Could not load alerts',
              style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

IconData _alertIcon(AppAlert a) => switch (a.kind) {
      AlertKind.geofenceExit => Icons.share_location,
      AlertKind.lowBattery => Icons.battery_alert,
      AlertKind.offline => Icons.cloud_off,
      AlertKind.unknown => Icons.warning_amber,
    };

String _alertTitle(AppAlert a) => switch (a.kind) {
      AlertKind.geofenceExit =>
        a.zoneName != null ? 'Left ${a.zoneName}' : 'Left the safe zones',
      AlertKind.lowBattery => 'Low battery',
      AlertKind.offline => 'Device offline',
      AlertKind.unknown => 'Alert',
    };

String _alertSubtitle(AppAlert a) => switch (a.kind) {
      AlertKind.geofenceExit => '${a.metersOutside} m outside',
      AlertKind.lowBattery =>
        a.battery != null ? '${a.battery}%, tracking stops when it runs out' : 'Low battery',
      AlertKind.offline => 'No report for ${a.silentFor}',
      AlertKind.unknown => '',
    };

/// "HH:mm", or "dd/MM HH:mm" when not today.
String _alertTime(DateTime? t) {
  if (t == null) return '';
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  return DateFormat(sameDay ? 'HH:mm' : 'dd/MM HH:mm').format(t);
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onResolve, required this.onViewMap});

  final AppAlert alert;
  final VoidCallback onResolve;
  final VoidCallback onViewMap;

  @override
  Widget build(BuildContext context) {
    final unresolved = !alert.resolved;

    return Container(
      decoration: BoxDecoration(
        color: unresolved ? context.colors.surfaceContainerLowest : context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Severity stripe on unresolved alerts.
            Container(width: 4, color: unresolved ? context.colors.error : context.colors.secondary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: unresolved ? context.colors.errorContainer : context.colors.secondaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            unresolved ? _alertIcon(alert) : Icons.check_circle_outline,
                            color: unresolved ? context.colors.error : context.colors.onSecondaryContainer,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_alertTitle(alert), style: AppText.labelLg),
                              const SizedBox(height: 2),
                              Text(
                                unresolved
                                    ? _alertSubtitle(alert)
                                    : 'Resolved${alert.resolvedAt != null ? ' at ${_alertTime(alert.resolvedAt)}' : ''}',
                                style: AppText.bodySm.copyWith(color: context.colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Text(_alertTime(alert.timestamp),
                            style: AppText.labelMd.copyWith(color: context.colors.onSurfaceVariant)),
                      ],
                    ),
                    if (unresolved)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Offline alerts may have no position.
                          if (alert.hasPosition)
                            TextButton(
                              onPressed: onViewMap,
                              child: Text(
                                  alert.kind == AlertKind.offline
                                      ? 'Last position'
                                      : 'View on map',
                                  style: AppText.labelMd.copyWith(color: context.colors.primary)),
                            ),
                          TextButton(
                            onPressed: onResolve,
                            child: Text('Resolve',
                                style: AppText.labelMd.copyWith(color: context.colors.primary)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertMapSheet extends StatelessWidget {
  const _AlertMapSheet({required this.alert});

  final AppAlert alert;

  @override
  Widget build(BuildContext context) {
    final pos = LatLng(alert.lat, alert.lng);
    return SizedBox(
      height: 360,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: context.colors.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.location_on, color: context.colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Alert location, ${_alertTime(alert.timestamp)}',
                      style: AppText.labelLg),
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: pos, zoom: 15),
              style: mapStyleFor(context),
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              markers: {
                Marker(
                  markerId: const MarkerId('alert'),
                  position: pos,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? context.colors.primaryContainer : context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppText.labelLg.copyWith(
            color: selected ? context.colors.onPrimaryContainer : context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyAlerts extends StatelessWidget {
  const _EmptyAlerts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: context.colors.secondaryContainer, shape: BoxShape.circle),
            child: Icon(Icons.verified_user, size: 44, color: context.colors.onSecondaryContainer),
          ),
          const SizedBox(height: 16),
          Text('No alerts', style: AppText.headlineSm),
          const SizedBox(height: 8),
          Text('Zone exits, low battery and offline alerts appear here.',
              style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}
