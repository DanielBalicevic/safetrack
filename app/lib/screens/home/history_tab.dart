import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/telemetry_point.dart';
import '../../providers/device_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/map_styles.dart';
import '../../utils/history_stats.dart';

enum HistoryRange {
  lastHour('Last hour', Duration(hours: 1)),
  today('Today', null),
  week('7 days', Duration(days: 7));

  const HistoryRange(this.label, this.duration);

  final String label;
  final Duration? duration; // null means since local midnight

  /// Window start in epoch ms, fixed when the filter is selected.
  int cutoffMs() {
    final now = DateTime.now();
    if (this == HistoryRange.today) {
      return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    }
    return now.subtract(duration!).millisecondsSinceEpoch;
  }
}

const int _historyLimit = 1000;

/// Position history with a time filter and summary statistics.
class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  GoogleMapController? _controller;
  bool _fitted = false; // fit the camera to the trail only once

  HistoryRange _range = HistoryRange.today;

  // Recreated only when the device or the filter changes.
  Stream<List<TelemetryPoint>>? _stream;
  String? _boundId;
  HistoryRange? _streamRange;

  void _fitToTrail(List<TelemetryPoint> points) {
    if (_fitted || _controller == null || points.isEmpty) return;
    _fitted = true;

    if (points.length == 1) {
      _controller!.moveCamera(
        CameraUpdate.newLatLngZoom(LatLng(points.first.lat, points.first.lng), 15),
      );
      return;
    }
    final lats = points.map((p) => p.lat);
    final lngs = points.map((p) => p.lng);
    final bounds = LatLngBounds(
      southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
      northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
    );
    _controller!.moveCamera(CameraUpdate.newLatLngBounds(bounds, 48));
  }

  void _setRange(HistoryRange r) {
    if (r == _range) return;
    setState(() => _range = r);
  }

  @override
  Widget build(BuildContext context) {
    final deviceId = context.select<DeviceProvider, String?>((d) => d.deviceId);
    if (deviceId != _boundId || _range != _streamRange) {
      _boundId = deviceId;
      _streamRange = _range;
      _fitted = false;
      _stream = context
          .read<DeviceProvider>()
          .watchHistorySince(sinceMs: _range.cutoffMs(), limit: _historyLimit);
    }

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        title: Text('History', style: AppText.headlineSm.copyWith(color: context.colors.primary)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                for (final r in HistoryRange.values) ...[
                  _RangeChip(
                    label: r.label,
                    selected: r == _range,
                    onTap: () => _setRange(r),
                  ),
                  if (r != HistoryRange.values.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<TelemetryPoint>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _centered(Icons.cloud_off, 'Could not load the history');
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final newestFirst = snapshot.data ?? const <TelemetryPoint>[];
                if (newestFirst.isEmpty) return const _EmptyHistory();

                final chrono = newestFirst.reversed.toList();
                final activeZones = context.read<DeviceProvider>().activeZones;
                final stats = HistoryStats.compute(chrono, activeZones);
                WidgetsBinding.instance.addPostFrameCallback((_) => _fitToTrail(chrono));

                return Column(
                  children: [
                    _StatsPanel(stats: stats, capped: newestFirst.length >= _historyLimit),
                    SizedBox(
                      height: 220,
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(newestFirst.first.lat, newestFirst.first.lng),
                          zoom: 14,
                        ),
                        onMapCreated: (c) {
                          _controller = c;
                          _fitToTrail(chrono);
                        },
                        style: mapStyleFor(context),
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        polylines: {
                          Polyline(
                            polylineId: const PolylineId('trail'),
                            points: [for (final p in chrono) LatLng(p.lat, p.lng)],
                            color: context.colors.primaryContainer,
                            width: 4,
                          ),
                        },
                        markers: {
                          Marker(
                            markerId: const MarkerId('latest'),
                            position: LatLng(newestFirst.first.lat, newestFirst.first.lng),
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                            infoWindow: const InfoWindow(title: 'Latest'),
                          ),
                        },
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: newestFirst.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: context.colors.outlineVariant),
                        itemBuilder: (context, i) =>
                            _PointRow(point: newestFirst[i], isLatest: i == 0),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _centered(IconData icon, String text) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: context.colors.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(text, style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant)),
          ],
        ),
      );
}

class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.stats, required this.capped});

  final HistoryStats stats;
  final bool capped;

  String get _distance {
    final m = stats.distanceMeters;
    if (m >= 1000) return '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1)} km';
    return '${m.round()} m';
  }

  String get _speed => '${stats.avgSpeedKmh.toStringAsFixed(1)} km/h';

  String get _inside =>
      stats.insideFraction == null ? '—' : '${(stats.insideFraction! * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatTile(icon: Icons.straighten, label: 'Distance', value: _distance),
              _divider(context),
              _StatTile(icon: Icons.speed, label: 'Avg. speed', value: _speed),
              _divider(context),
              _StatTile(icon: Icons.verified_user, label: 'Time inside', value: _inside),
            ],
          ),
          if (capped) ...[
            const SizedBox(height: 8),
            Text('showing the latest $_historyLimit points',
                style: AppText.labelMd.copyWith(color: context.colors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Container(width: 1, height: 36, color: context.colors.outlineVariant);
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 20, color: context.colors.primary),
          const SizedBox(height: 4),
          Text(value, style: AppText.labelLg.copyWith(color: context.colors.onSurface)),
          const SizedBox(height: 2),
          Text(label, style: AppText.labelMd.copyWith(color: context.colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
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
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  const _PointRow({required this.point, required this.isLatest});

  final TelemetryPoint point;
  final bool isLatest;

  @override
  Widget build(BuildContext context) {
    final local = point.timestamp.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            isLatest ? Icons.location_on : Icons.circle,
            size: isLatest ? 22 : 12,
            color: isLatest ? context.colors.primary : context.colors.outlineVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('dd/MM/yyyy HH:mm:ss').format(local), style: AppText.labelLg),
                const SizedBox(height: 2),
                Text(
                  '${point.lat.toStringAsFixed(5)}, ${point.lng.toStringAsFixed(5)}',
                  style: AppText.bodySm.copyWith(color: context.colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Icon(Icons.battery_std, size: 16, color: context.colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('${point.battery}%',
                  style: AppText.labelMd.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, shape: BoxShape.circle),
            child: Icon(Icons.history, size: 44, color: context.colors.primary),
          ),
          const SizedBox(height: 16),
          Text('No positions in this period', style: AppText.headlineSm),
          const SizedBox(height: 8),
          Text('Try another time range.',
              style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
