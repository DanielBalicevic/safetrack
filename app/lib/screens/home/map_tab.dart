import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/device_provider.dart';
import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/map_styles.dart';
import '../../utils/time_ago.dart';
import '../device_settings_screen.dart';

/// Full-screen map with the device's latest position and a status card
/// (last update, battery, zone status). A periodic [_ticker] rebuilds the
/// screen so the "x ago" text stays current without new telemetry.
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  GoogleMapController? _controller;
  Timer? _ticker;

  // Marker icons generated at runtime: purple (reporting) and grey (no signal).
  BitmapDescriptor? _onlineIcon;
  BitmapDescriptor? _offlineIcon;

  // Initial camera (Portugal) until the first point arrives.
  static const _fallback = CameraPosition(target: LatLng(39.5, -8.0), zoom: 6);

  String? _centeredPointId;

  @override
  void initState() {
    super.initState();
    _generateMarkerIcons();
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _generateMarkerIcons() async {
    // Fixed colors that read well on both light and dark maps.
    final online = await _circleMarker(AppColorsData.light.primaryContainer);
    final offline = await _circleMarker(AppColorsData.light.outline);
    if (mounted) {
      setState(() {
        _onlineIcon = online;
        _offlineIcon = offline;
      });
    }
  }

  /// Draws a colored dot with a white halo. `defaultMarkerWithHue` cannot
  /// produce grey.
  Future<BitmapDescriptor> _circleMarker(Color color) async {
    const double px = 120;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const center = Offset(px / 2, px / 2);
    canvas.drawCircle(center, px * 0.42, Paint()..color = Colors.white);
    canvas.drawCircle(center, px * 0.30, Paint()..color = color);
    final image = await recorder.endRecording().toImage(px.toInt(), px.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(data!.buffer.asUint8List(), width: 40, height: 40);
  }

  void _centerOnDevice(DeviceProvider device, {bool animate = true}) {
    final point = device.lastPoint;
    if (point == null || _controller == null) return;
    final target = LatLng(point.lat, point.lng);
    _controller!.animateCamera(
      animate
          ? CameraUpdate.newLatLng(target)
          : CameraUpdate.newLatLngZoom(target, 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final device = context.watch<DeviceProvider>();
    final point = device.lastPoint;

    // Center on new points after the frame, not during build.
    if (point != null && point.id != _centeredPointId && _controller != null) {
      _centeredPointId = point.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnDevice(device));
    }

    final offline = device.isOffline;
    final markerIcon = offline
        ? (_offlineIcon ?? BitmapDescriptor.defaultMarker)
        : (_onlineIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet));
    final markers = <Marker>{
      if (point != null)
        Marker(
          markerId: const MarkerId('device'),
          position: LatLng(point.lat, point.lng),
          icon: markerIcon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(
            title: device.device?.name ?? 'Device',
            snippet: offline
                ? 'No signal'
                : (point.isApproximate
                    ? 'Approximate location (~${point.accuracy.round()} m)'
                    : null),
          ),
        ),
    };

    final activeZones = device.activeZones;
    final circles = <Circle>{
      // Show the uncertainty radius for Wi-Fi positions.
      if (point != null && point.isApproximate && point.accuracy > 0)
        Circle(
          circleId: const CircleId('accuracy'),
          center: LatLng(point.lat, point.lng),
          radius: point.accuracy,
          fillColor: context.colors.primaryContainer.withValues(alpha: 0.15),
          strokeColor: context.colors.primaryContainer.withValues(alpha: 0.45),
          strokeWidth: 1,
        ),
      for (final z in activeZones)
        if (!z.isPolygon)
          Circle(
            circleId: CircleId(z.id),
            center: LatLng(z.centerLat, z.centerLng),
            radius: z.radius,
            fillColor: z.color.withValues(alpha: 0.12),
            strokeColor: z.color.withValues(alpha: 0.6),
            strokeWidth: 2,
          ),
    };
    final polygons = <Polygon>{
      for (final z in activeZones)
        if (z.isPolygon)
          Polygon(
            polygonId: PolygonId(z.id),
            points: [for (final v in z.vertices) LatLng(v.lat, v.lng)],
            fillColor: z.color.withValues(alpha: 0.12),
            strokeColor: z.color.withValues(alpha: 0.6),
            strokeWidth: 2,
          ),
    };

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: point != null
              ? CameraPosition(target: LatLng(point.lat, point.lng), zoom: 16)
              : _fallback,
          markers: markers,
          circles: circles,
          polygons: polygons,
          style: mapStyleFor(context),
          myLocationButtonEnabled: false,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (c) {
            _controller = c;
            if (point != null) {
              _centeredPointId = point.id;
              _centerOnDevice(device, animate: false);
            }
          },
        ),

        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                const _HomeHeader(),
                const SizedBox(height: 8),
                DeviceStatusCard(device: device),
              ],
            ),
          ),
        ),

        Positioned(
          right: 16,
          bottom: 32,
          child: FloatingActionButton(
            heroTag: 'recenter',
            backgroundColor: context.colors.primaryContainer,
            foregroundColor: context.colors.onPrimary,
            elevation: 4,
            onPressed: () {
              if (point == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No known position.')),
                );
              } else {
                _centerOnDevice(device, animate: false);
              }
            },
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4).copyWith(left: 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: context.colors.primaryContainer.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Text('SafeTrack',
              style: AppText.headlineMd.copyWith(color: context.colors.primary)),
          const Spacer(),
          IconButton(
            tooltip: 'Theme: ${theme.label}',
            icon: Icon(theme.icon, color: context.colors.primary),
            onPressed: () => context.read<ThemeProvider>().cycle(),
          ),
          IconButton(
            tooltip: 'Manage device',
            icon: Icon(Icons.settings_outlined, color: context.colors.primary),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeviceSettingsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Green above 50%, amber from 20% to 50%, red below 20%.
Color batteryColor(int? level, AppColorsData c) {
  if (level == null) return c.onSurfaceVariant;
  if (level > 50) return c.secondary;
  if (level >= 20) return c.warning;
  return c.error;
}

IconData batteryIcon(int? level) {
  if (level == null) return Icons.battery_unknown;
  if (level >= 90) return Icons.battery_full;
  if (level >= 60) return Icons.battery_5_bar;
  if (level >= 35) return Icons.battery_3_bar;
  if (level >= 15) return Icons.battery_2_bar;
  return Icons.battery_alert;
}

class DeviceStatusCard extends StatelessWidget {
  const DeviceStatusCard({super.key, required this.device});

  final DeviceProvider device;

  @override
  Widget build(BuildContext context) {
    final d = device.device;
    final point = device.lastPoint;
    final battery = d?.batteryLevel ?? point?.battery;
    final updatedAt = device.lastUpdateTime;
    final battColor = batteryColor(battery, context.colors);
    final offline = device.isOffline;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: context.colors.primaryContainer.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Unlike the backend, the badge has no debounce.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(d?.name ?? 'Device', style: AppText.headlineSm)),
              const SizedBox(width: 8),
              Flexible(child: _ZoneBadge(device: device)),
            ],
          ),
          const SizedBox(height: 6),

          if (offline)
            _OfflineBanner(since: updatedAt)
          else
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: context.colors.secondary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Reporting · updated ${timeAgo(updatedAt)}',
                    style: AppText.bodySm.copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
          const SizedBox(height: 12),

          Row(
            children: [
              Icon(batteryIcon(battery), size: 20, color: battColor),
              const SizedBox(width: 6),
              Text('Battery',
                  style: AppText.labelMd.copyWith(color: context.colors.onSurfaceVariant)),
              const Spacer(),
              Text(battery != null ? '$battery%' : '—',
                  style: AppText.labelLg.copyWith(color: battColor, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (battery ?? 0) / 100,
              minHeight: 8,
              backgroundColor: context.colors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation(battColor),
            ),
          ),
        ],
      ),
    );
  }
}

/// "HH:mm", or "dd/MM HH:mm" when not today.
String _fmtClock(DateTime? t) {
  if (t == null) return '—';
  final local = t.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
  return DateFormat(sameDay ? 'HH:mm' : 'dd/MM HH:mm').format(local);
}

/// Shown when the device has not reported for [DeviceProvider.offlineThreshold].
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.since});

  final DateTime? since;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.signal_wifi_connected_no_internet_4,
              size: 18, color: context.colors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text('No signal since ${_fmtClock(since)}',
                style: AppText.labelLg.copyWith(color: context.colors.warning)),
          ),
        ],
      ),
    );
  }
}

/// Inside a zone (green), outside all zones (red) or no active zones (grey).
class _ZoneBadge extends StatelessWidget {
  const _ZoneBadge({required this.device});

  final DeviceProvider device;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String label;

    if (!device.hasActiveZones) {
      bg = context.colors.surfaceContainerHigh;
      fg = context.colors.onSurfaceVariant;
      icon = Icons.help_outline;
      label = 'No zones set';
    } else {
      final inside = device.insideZone;
      if (inside != null) {
        bg = context.colors.secondaryContainer;
        fg = context.colors.onSecondaryContainer;
        icon = Icons.verified_user;
        label = 'Inside ${inside.name}';
      } else {
        bg = context.colors.errorContainer;
        fg = context.colors.onErrorContainer;
        icon = Icons.warning_amber_rounded;
        label = 'Outside all zones';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                style: AppText.labelMd.copyWith(color: fg),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
