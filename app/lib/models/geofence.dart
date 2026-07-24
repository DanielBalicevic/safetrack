import 'package:cloud_firestore/cloud_firestore.dart';

import '../services/geo_utils.dart';

enum GeofenceType { circle, polygon }

/// Legacy single geofence stored at `devices/{deviceId}/geofence/current`.
/// Only read when migrating to the `geofences` collection (see [Zone]).
class Geofence {
  final GeofenceType type;
  final double centerLat;
  final double centerLng;
  final double radius;
  final List<({double lat, double lng})> points;
  final bool active;

  const Geofence({
    required this.type,
    required this.centerLat,
    required this.centerLng,
    required this.radius,
    required this.points,
    required this.active,
  });

  bool get isPolygon => type == GeofenceType.polygon && points.length >= 3;

  factory Geofence.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const {};
    final type =
        (data['type'] as String?) == 'polygon' ? GeofenceType.polygon : GeofenceType.circle;

    final rawPoints = (data['points'] as List?) ?? const [];
    final points = <({double lat, double lng})>[
      for (final e in rawPoints)
        if (e is Map)
          (
            lat: (e['lat'] as num?)?.toDouble() ?? 0,
            lng: (e['lng'] as num?)?.toDouble() ?? 0,
          ),
    ];

    return Geofence(
      type: type,
      centerLat: (data['centerLat'] as num?)?.toDouble() ?? 0,
      centerLng: (data['centerLng'] as num?)?.toDouble() ?? 0,
      radius: (data['radius'] as num?)?.toDouble() ?? 0,
      points: points,
      active: data['active'] as bool? ?? false,
    );
  }

  bool contains(double lat, double lng) {
    if (isPolygon) return GeoUtils.pointInPolygon(lat, lng, points);
    return GeoUtils.haversineMeters(lat, lng, centerLat, centerLng) <= radius;
  }
}
