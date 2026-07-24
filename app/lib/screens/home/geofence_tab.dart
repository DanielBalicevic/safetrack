import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/zone.dart';
import '../../providers/device_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/map_styles.dart';
import 'zone_editor_screen.dart';

/// Lists the device's zones and draws them on the map (inactive zones faded).
/// Selecting a zone shows actions to toggle, edit, rename or delete it.
class GeofenceTab extends StatefulWidget {
  const GeofenceTab({super.key});

  @override
  State<GeofenceTab> createState() => _GeofenceTabState();
}

class _GeofenceTabState extends State<GeofenceTab> {
  GoogleMapController? _controller;
  String? _selectedId;
  bool _fittedOnce = false;
  bool _actionBusy = false;

  void _openEditor([Zone? zone]) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ZoneEditorScreen(initial: zone)),
    );
  }

  void _selectZone(Zone z) {
    setState(() => _selectedId = z.id);
    _focusZone(z);
  }

  void _focusZone(Zone z) {
    if (_controller == null) return;
    if (z.isPolygon) {
      final lats = z.vertices.map((v) => v.lat);
      final lngs = z.vertices.map((v) => v.lng);
      _controller!.animateCamera(CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
          northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
        ),
        64,
      ));
    } else {
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(z.centerLat, z.centerLng), 15));
    }
  }

  void _fitAll(List<Zone> zones) {
    if (_fittedOnce || _controller == null || zones.isEmpty) return;
    final pts = <LatLng>[];
    for (final z in zones) {
      if (z.isPolygon) {
        pts.addAll([for (final v in z.vertices) LatLng(v.lat, v.lng)]);
      } else {
        pts.add(LatLng(z.centerLat, z.centerLng));
      }
    }
    if (pts.isEmpty) return;
    _fittedOnce = true;
    if (pts.length == 1) {
      _controller!.moveCamera(CameraUpdate.newLatLngZoom(pts.first, 15));
      return;
    }
    final lats = pts.map((p) => p.latitude);
    final lngs = pts.map((p) => p.longitude);
    _controller!.moveCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce(math.min), lngs.reduce(math.min)),
        northeast: LatLng(lats.reduce(math.max), lngs.reduce(math.max)),
      ),
      64,
    ));
  }

  Future<void> _runAction(Future<void> Function() action, String okMsg) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _actionBusy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(okMsg)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Action failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _rename(Zone z) async {
    final controller = TextEditingController(text: z.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename zone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Zone name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    await _runAction(() => context.read<DeviceProvider>().renameZone(z.id, name), 'Zone renamed.');
  }

  Future<void> _delete(Zone z) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete zone?'),
        content: Text("Delete '${z.name}'? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: context.colors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runAction(() => context.read<DeviceProvider>().deleteZone(z.id), 'Zone deleted.');
    if (mounted) setState(() => _selectedId = null);
  }

  @override
  Widget build(BuildContext context) {
    final zones = context.watch<DeviceProvider>().zones;

    // The selected zone may have been deleted.
    Zone? selected;
    for (final z in zones) {
      if (z.id == _selectedId) selected = z;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll(zones));

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        title: Text('Zones', style: AppText.headlineSm.copyWith(color: context.colors.primary)),
      ),
      body: zones.isEmpty
          ? _EmptyZones(onCreate: () => _openEditor())
          : Column(
              children: [
                _ZoneChips(
                  zones: zones,
                  selectedId: _selectedId,
                  onSelect: _selectZone,
                  onNew: () => _openEditor(),
                ),
                Expanded(
                  child: GoogleMap(
                    initialCameraPosition: const CameraPosition(target: LatLng(39.5, -8.0), zoom: 6),
                    onMapCreated: (c) {
                      _controller = c;
                      _fitAll(zones);
                    },
                    style: mapStyleFor(context),
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    circles: _circles(zones),
                    polygons: _polygons(zones),
                  ),
                ),
                if (selected != null) _ActionBar(zone: selected, busy: _actionBusy, tab: this),
              ],
            ),
    );
  }

  Set<Circle> _circles(List<Zone> zones) {
    return {
      for (final z in zones)
        if (!z.isPolygon)
          Circle(
            circleId: CircleId(z.id),
            center: LatLng(z.centerLat, z.centerLng),
            radius: z.radius,
            fillColor: z.color.withValues(alpha: z.active ? 0.15 : 0.05),
            strokeColor: z.color.withValues(alpha: z.active ? 0.7 : 0.3),
            strokeWidth: z.id == _selectedId ? 4 : 2,
          ),
    };
  }

  Set<Polygon> _polygons(List<Zone> zones) {
    return {
      for (final z in zones)
        if (z.isPolygon)
          Polygon(
            polygonId: PolygonId(z.id),
            points: [for (final v in z.vertices) LatLng(v.lat, v.lng)],
            fillColor: z.color.withValues(alpha: z.active ? 0.15 : 0.05),
            strokeColor: z.color.withValues(alpha: z.active ? 0.7 : 0.3),
            strokeWidth: z.id == _selectedId ? 4 : 2,
          ),
    };
  }
}

class _ZoneChips extends StatelessWidget {
  const _ZoneChips({
    required this.zones,
    required this.selectedId,
    required this.onSelect,
    required this.onNew,
  });

  final List<Zone> zones;
  final String? selectedId;
  final void Function(Zone) onSelect;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final z in zones) ...[
            _ZoneChip(zone: z, selected: z.id == selectedId, onTap: () => onSelect(z)),
            const SizedBox(width: 8),
          ],
          _NewChip(onTap: onNew),
        ],
      ),
    );
  }
}

class _ZoneChip extends StatelessWidget {
  const _ZoneChip({required this.zone, required this.selected, required this.onTap});

  final Zone zone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dim = !zone.active;
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: dim ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? context.colors.primaryContainer : context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: selected ? context.colors.primaryContainer : context.colors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: zone.color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(zone.name,
                  style: AppText.labelLg.copyWith(
                      color: selected ? context.colors.onPrimaryContainer : context.colors.onSurface)),
              const SizedBox(width: 6),
              Icon(zone.isPolygon ? Icons.pentagon_outlined : Icons.circle_outlined,
                  size: 16,
                  color: selected ? context.colors.onPrimaryContainer : context.colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewChip extends StatelessWidget {
  const _NewChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.colors.primary),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, size: 18, color: context.colors.primary),
            const SizedBox(width: 4),
            Text('New', style: AppText.labelLg.copyWith(color: context.colors.primary)),
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.zone, required this.busy, required this.tab});

  final Zone zone;
  final bool busy;
  final _GeofenceTabState tab;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, -6)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(width: 14, height: 14, decoration: BoxDecoration(color: zone.color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(zone.name, style: AppText.headlineSm, overflow: TextOverflow.ellipsis)),
                  Text(zone.active ? 'Active' : 'Inactive',
                      style: AppText.labelMd.copyWith(color: context.colors.onSurfaceVariant)),
                  Switch(
                    value: zone.active,
                    activeThumbColor: context.colors.primary,
                    onChanged: busy
                        ? null
                        : (v) => tab._runAction(
                            () => context.read<DeviceProvider>().setZoneActive(zone.id, v),
                            v ? 'Zone enabled.' : 'Zone disabled.'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => tab._openEditor(zone),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => tab._rename(zone),
                      icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                      label: const Text('Rename'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => tab._delete(zone),
                      icon: Icon(Icons.delete_outline, size: 18, color: context.colors.error),
                      label: Text('Delete', style: TextStyle(color: context.colors.error)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: context.colors.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyZones extends StatelessWidget {
  const _EmptyZones({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: context.colors.surfaceContainerHigh, shape: BoxShape.circle),
              child: Icon(Icons.add_location_alt_outlined, size: 44, color: context.colors.primary),
            ),
            const SizedBox(height: 16),
            Text('No safe zones', style: AppText.headlineSm),
            const SizedBox(height: 8),
            Text('Create a zone to get alerts when the device leaves it.',
                style: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create zone'),
            ),
          ],
        ),
      ),
    );
  }
}
