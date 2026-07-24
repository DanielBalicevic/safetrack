import 'dart:math' as math;

/// Geometry helpers. Must stay in sync with functions/geo.js so the app and
/// the backend always agree on inside/outside.
class GeoUtils {
  GeoUtils._();

  static const double _earthRadiusMeters = 6371000;

  static double haversineMeters(
      double lat1, double lng1, double lat2, double lng2) {
    double toRad(double deg) => deg * math.pi / 180;

    final dLat = toRad(lat2 - lat1);
    final dLng = toRad(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(toRad(lat1)) *
            math.cos(toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  /// Ray casting, with lng as x and lat as y.
  static bool pointInPolygon(
      double lat, double lng, List<({double lat, double lng})> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    final n = polygon.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].lng;
      final yi = polygon[i].lat;
      final xj = polygon[j].lng;
      final yj = polygon[j].lat;
      final intersect = ((yi > lat) != (yj > lat)) &&
          (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }
}
