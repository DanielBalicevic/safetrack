import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../../models/geofence.dart' show GeofenceType;
import '../../models/zone.dart';
import '../../providers/device_provider.dart';
import '../../providers/geocoding_provider.dart';
import '../../services/geocoding_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/map_styles.dart';

/// Creates or edits a zone. Circles have a draggable center and a radius;
/// polygons are drawn by tapping the map. New zones get a name and the next
/// palette color; when editing, the shape type cannot change.
class ZoneEditorScreen extends StatefulWidget {
  const ZoneEditorScreen({super.key, this.initial});

  /// The zone to edit, or null to create one.
  final Zone? initial;

  @override
  State<ZoneEditorScreen> createState() => _ZoneEditorScreenState();
}

class _ZoneEditorScreenState extends State<ZoneEditorScreen> {
  GoogleMapController? _controller;
  final _searchController = TextEditingController();

  late GeofenceType _mode;
  LatLng _center = const LatLng(39.5, -8.0);
  double _radius = 150;
  final List<LatLng> _polyPoints = [];
  bool _saving = false;
  bool _seededCenter = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final z = widget.initial;
    if (z != null) {
      _mode = z.type;
      if (z.isPolygon) {
        _polyPoints.addAll([for (final v in z.vertices) LatLng(v.lat, v.lng)]);
      } else {
        _center = LatLng(z.centerLat, z.centerLng);
        _radius = z.radius.clamp(50, 1000).toDouble();
      }
      _seededCenter = true;
    } else {
      _mode = GeofenceType.circle;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // New zone: start at the device's last known position.
    if (!_seededCenter) {
      final p = context.read<DeviceProvider>().lastPoint;
      if (p != null) {
        _center = LatLng(p.lat, p.lng);
        _seededCenter = true;
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onMapTap(LatLng pos) {
    setState(() {
      if (_mode == GeofenceType.polygon) {
        _polyPoints.add(pos);
      } else {
        _center = pos;
      }
    });
  }

  Future<void> _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusScope.of(context).unfocus();
    final geocoding = context.read<GeocodingProvider>();
    final messenger = ScaffoldMessenger.of(context);
    void snack(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

    final resp = await geocoding.search(query);
    if (!mounted) return;
    switch (resp.status) {
      case GeocodeStatus.network:
        snack('No connection. Please try again.');
      case GeocodeStatus.requestDenied:
        snack('Search unavailable. Check the Geocoding API key.');
      case GeocodeStatus.error:
        snack('Search failed. Please try again.');
      case GeocodeStatus.zeroResults:
        snack('Place not found.');
      case GeocodeStatus.ok:
        if (resp.results.length == 1) {
          _applyResult(resp.results.first);
        } else {
          _showResultsSheet(resp.results);
        }
    }
  }

  void _applyResult(GeocodeResult r) {
    final target = LatLng(r.lat, r.lng);
    if (_mode == GeofenceType.circle) setState(() => _center = target);
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {});
  }

  void _showResultsSheet(List<GeocodeResult> results) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.colors.surfaceContainerLowest,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Several places found', style: AppText.labelLg),
            ),
            for (final r in results)
              ListTile(
                leading: Icon(Icons.place_outlined, color: context.colors.primary),
                title: Text(r.formattedAddress, style: AppText.bodyMd),
                onTap: () {
                  Navigator.pop(ctx);
                  _applyResult(r);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(String defaultName) {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Zone name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Home'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_mode == GeofenceType.polygon && _polyPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A polygon needs at least 3 points.')),
      );
      return;
    }

    final device = context.read<DeviceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    String name;
    String colorHex;
    if (_isEditing) {
      name = widget.initial!.name;
      colorHex = widget.initial!.colorHex;
    } else {
      final entered = await _askName('Zone ${device.zones.length + 1}');
      if (entered == null || entered.isEmpty || !mounted) return;
      name = entered;
      colorHex = device.nextZoneColor();
    }

    setState(() => _saving = true);
    try {
      final vertices = _mode == GeofenceType.polygon
          ? [for (final p in _polyPoints) (lat: p.latitude, lng: p.longitude)]
          : null;
      if (_isEditing) {
        await device.updateZone(
          widget.initial!.id,
          name: name,
          type: _mode,
          centerLat: _mode == GeofenceType.circle ? _center.latitude : null,
          centerLng: _mode == GeofenceType.circle ? _center.longitude : null,
          radius: _mode == GeofenceType.circle ? _radius : null,
          vertices: vertices,
          active: widget.initial!.active,
          colorHex: colorHex,
        );
      } else {
        await device.createZone(
          name: name,
          type: _mode,
          centerLat: _mode == GeofenceType.circle ? _center.latitude : null,
          centerLng: _mode == GeofenceType.circle ? _center.longitude : null,
          radius: _mode == GeofenceType.circle ? _radius : null,
          vertices: vertices,
          active: true,
          colorHex: colorHex,
        );
      }
      messenger.showSnackBar(const SnackBar(content: Text('Zone saved.')));
      navigator.pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not save. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPoly = _mode == GeofenceType.polygon;
    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        elevation: 0,
        foregroundColor: context.colors.primary,
        title: Text(_isEditing ? 'Edit zone' : 'New zone',
            style: AppText.headlineSm.copyWith(color: context.colors.primary)),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _center, zoom: 15),
                  onMapCreated: (c) {
                    _controller = c;
                    if (isPoly && _polyPoints.length >= 2) _fitToPolygon();
                  },
                  onTap: _onMapTap,
                  style: mapStyleFor(context),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: _markers(context),
                  circles: _circles(context),
                  polygons: _polygons(context),
                ),
                Positioned(top: 8, left: 12, right: 12, child: _searchBar(context)),
                Positioned(left: 0, right: 0, bottom: 12, child: Center(child: _hintBanner(isPoly))),
              ],
            ),
          ),
          _panel(context, isPoly),
        ],
      ),
    );
  }

  void _fitToPolygon() {
    if (_controller == null || _polyPoints.length < 2) return;
    final lats = _polyPoints.map((p) => p.latitude);
    final lngs = _polyPoints.map((p) => p.longitude);
    _controller!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      64,
    ));
  }

  Set<Marker> _markers(BuildContext context) {
    if (_mode == GeofenceType.circle) {
      return {
        Marker(
          markerId: const MarkerId('center'),
          position: _center,
          draggable: true,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          onDragEnd: (pos) => setState(() => _center = pos),
        ),
      };
    }
    return {
      for (var i = 0; i < _polyPoints.length; i++)
        Marker(
          markerId: MarkerId('v$i'),
          position: _polyPoints[i],
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(title: 'Point ${i + 1}'),
        ),
    };
  }

  Set<Circle> _circles(BuildContext context) {
    if (_mode != GeofenceType.circle) return {};
    return {
      Circle(
        circleId: const CircleId('draft'),
        center: _center,
        radius: _radius,
        fillColor: context.colors.primary.withValues(alpha: 0.15),
        strokeColor: context.colors.primary.withValues(alpha: 0.6),
        strokeWidth: 2,
      ),
    };
  }

  Set<Polygon> _polygons(BuildContext context) {
    if (_mode != GeofenceType.polygon || _polyPoints.length < 3) return {};
    return {
      Polygon(
        polygonId: const PolygonId('draft'),
        points: _polyPoints,
        fillColor: context.colors.primary.withValues(alpha: 0.15),
        strokeColor: context.colors.primary.withValues(alpha: 0.6),
        strokeWidth: 2,
      ),
    };
  }

  /// Hint over the map. For polygons it disappears after the third point.
  Widget _hintBanner(bool isPoly) {
    if (isPoly && _polyPoints.length >= 3) return const SizedBox.shrink();
    final text = isPoly
        ? 'Tap the map to add points (at least 3)'
        : 'Drag the pin or tap the map to set the center';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isPoly ? Icons.touch_app_outlined : Icons.pin_drop_outlined,
              size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text,
                style: AppText.labelMd.copyWith(color: Colors.white),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(BuildContext context) {
    final searching = context.watch<GeocodingProvider>().searching;
    final hasText = _searchController.text.isNotEmpty;
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: context.colors.surfaceContainerLowest,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _onSearch(),
        onChanged: (_) => setState(() {}),
        style: AppText.bodyMd,
        decoration: InputDecoration(
          hintText: 'Search for an address or place…',
          hintStyle: AppText.bodyMd.copyWith(color: context.colors.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, color: context.colors.onSurfaceVariant),
          suffixIcon: searching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
              : (hasText
                  ? IconButton(
                      icon: Icon(Icons.clear, color: context.colors.onSurfaceVariant),
                      onPressed: () => setState(() => _searchController.clear()))
                  : null),
          filled: true,
          fillColor: context.colors.surfaceContainerLowest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.colors.primary, width: 1.5)),
        ),
      ),
    );
  }

  Widget _panel(BuildContext context, bool isPoly) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, -8)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The shape type is locked when editing.
              SegmentedButton<GeofenceType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: GeofenceType.circle, label: Text('Circle'), icon: Icon(Icons.circle_outlined)),
                  ButtonSegment(value: GeofenceType.polygon, label: Text('Polygon'), icon: Icon(Icons.pentagon_outlined)),
                ],
                selected: {_mode},
                onSelectionChanged: _isEditing ? null : (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 12),
              if (isPoly) _polygonControls(context) else _circleControls(context),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : Text(_isEditing ? 'Save changes' : 'Save zone'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _circleControls(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Zone radius', style: AppText.labelLg),
              const Spacer(),
              Text('${_radius.round()} m',
                  style: AppText.bodyLg.copyWith(color: context.colors.primary, fontWeight: FontWeight.w700)),
            ],
          ),
          Slider(
            value: _radius,
            min: 50,
            max: 1000,
            divisions: 95,
            activeColor: context.colors.primary,
            label: '${_radius.round()} m',
            onChanged: (v) => setState(() => _radius = v),
          ),
          Text('Drag the pin or search for an address to set the center.',
              style: AppText.labelMd.copyWith(color: context.colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _polygonControls(BuildContext context) {
    final n = _polyPoints.length;
    final enough = n >= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(enough ? Icons.check_circle : Icons.info_outline,
              size: 18, color: enough ? context.colors.secondary : context.colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Text('$n ${n == 1 ? 'point' : 'points'}', style: AppText.labelLg),
          const Spacer(),
          TextButton.icon(
            onPressed: n == 0 ? null : () => setState(() => _polyPoints.removeLast()),
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Undo'),
          ),
          TextButton.icon(
            onPressed: n == 0 ? null : () => setState(_polyPoints.clear),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
