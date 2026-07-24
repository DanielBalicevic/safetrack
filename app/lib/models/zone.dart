import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/geo_utils.dart';
import 'geofence.dart' show GeofenceType;

/// Colors assigned to new zones in order.
const List<String> kZonePalette = [
  '#534AB7',
  '#1D9E75',
  '#BA7517',
  '#B3261E',
  '#1D6FB8',
  '#8E24AA',
  '#0F8A8A',
  '#C2185B',
];

/// A safe zone stored at `devices/{id}/geofences/{zoneId}`.
///
/// Circle: `center` (GeoPoint) and `radius`. Polygon: `vertices` ([{lat, lng}]).
/// Common fields: `name`, `type`, `active`, `color`, `createdAt`.
class Zone {
  final String id;
  final String name;
  final GeofenceType type;
  final double centerLat;
  final double centerLng;
  final double radius;
  final List<({double lat, double lng})> vertices;
  final bool active;
  final String colorHex;
  final DateTime? createdAt;

  const Zone({
    required this.id,
    required this.name,
    required this.type,
    required this.centerLat,
    required this.centerLng,
    required this.radius,
    required this.vertices,
    required this.active,
    required this.colorHex,
    required this.createdAt,
  });

  bool get isPolygon => type == GeofenceType.polygon && vertices.length >= 3;

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    final v = int.tryParse(hex, radix: 16) ?? 0x534AB7;
    return Color(0xFF000000 | v);
  }

  /// Same rules as the backend (functions/geo.js).
  bool contains(double lat, double lng) {
    if (isPolygon) return GeoUtils.pointInPolygon(lat, lng, vertices);
    return GeoUtils.haversineMeters(lat, lng, centerLat, centerLng) <= radius;
  }

  /// Distance to the center, or to the centroid for polygons.
  double distanceTo(double lat, double lng) {
    if (isPolygon) {
      var sLat = 0.0;
      var sLng = 0.0;
      for (final v in vertices) {
        sLat += v.lat;
        sLng += v.lng;
      }
      final n = vertices.length;
      return GeoUtils.haversineMeters(lat, lng, sLat / n, sLng / n);
    }
    return GeoUtils.haversineMeters(lat, lng, centerLat, centerLng);
  }

  factory Zone.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const {};
    final type = (data['type'] as String?) == 'polygon'
        ? GeofenceType.polygon
        : GeofenceType.circle;
    final center = data['center'] as GeoPoint?;
    final rawVertices = (data['vertices'] as List?) ?? const [];
    final vertices = <({double lat, double lng})>[
      for (final e in rawVertices)
        if (e is Map)
          (
            lat: (e['lat'] as num?)?.toDouble() ?? 0,
            lng: (e['lng'] as num?)?.toDouble() ?? 0,
          ),
    ];
    final name = (data['name'] as String?)?.trim();
    return Zone(
      id: snap.id,
      name: (name != null && name.isNotEmpty) ? name : 'Zone',
      type: type,
      centerLat: center?.latitude ?? 0,
      centerLng: center?.longitude ?? 0,
      radius: (data['radius'] as num?)?.toDouble() ?? 0,
      vertices: vertices,
      active: data['active'] as bool? ?? false,
      colorHex: (data['color'] as String?) ?? kZonePalette.first,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  static Zone? firstActiveContaining(
      Iterable<Zone> zones, double lat, double lng) {
    for (final z in zones) {
      if (z.active && z.contains(lat, lng)) return z;
    }
    return null;
  }

  static Zone? nearestActive(Iterable<Zone> zones, double lat, double lng) {
    Zone? best;
    double bestD = double.infinity;
    for (final z in zones) {
      if (!z.active) continue;
      final d = z.distanceTo(lat, lng);
      if (d < bestD) {
        bestD = d;
        best = z;
      }
    }
    return best;
  }
}
