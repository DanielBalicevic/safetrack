import 'package:flutter_test/flutter_test.dart';
import 'package:safetrack/models/geofence.dart';
import 'package:safetrack/services/geo_utils.dart';

void main() {
  // Square around Lisbon: lat 38.70..38.75, lng -9.15..-9.10.
  final square = <({double lat, double lng})>[
    (lat: 38.70, lng: -9.15),
    (lat: 38.70, lng: -9.10),
    (lat: 38.75, lng: -9.10),
    (lat: 38.75, lng: -9.15),
  ];

  group('GeoUtils.pointInPolygon', () {
    test('point clearly inside', () {
      expect(GeoUtils.pointInPolygon(38.72, -9.12, square), isTrue);
    });

    test('point clearly outside', () {
      expect(GeoUtils.pointInPolygon(38.80, -9.12, square), isFalse);
      expect(GeoUtils.pointInPolygon(38.72, -9.00, square), isFalse);
    });

    test('points just inside and just outside an edge', () {
      expect(GeoUtils.pointInPolygon(38.7001, -9.12, square), isTrue);
      expect(GeoUtils.pointInPolygon(38.6999, -9.12, square), isFalse);
    });

    test('fewer than 3 points never contains a point', () {
      expect(GeoUtils.pointInPolygon(38.72, -9.12, [(lat: 38.7, lng: -9.1)]), isFalse);
    });
  });

  group('Geofence.contains', () {
    test('circle: center inside, far point outside', () {
      const g = Geofence(
        type: GeofenceType.circle,
        centerLat: 38.72,
        centerLng: -9.12,
        radius: 150,
        points: [],
        active: true,
      );
      expect(g.contains(38.72, -9.12), isTrue);
      expect(g.contains(38.80, -9.12), isFalse);
    });

    test('polygon uses ray casting', () {
      final g = Geofence(
        type: GeofenceType.polygon,
        centerLat: 0,
        centerLng: 0,
        radius: 0,
        points: square,
        active: true,
      );
      expect(g.contains(38.72, -9.12), isTrue);
      expect(g.contains(38.80, -9.12), isFalse);
    });
  });

  test('haversine matches a known distance (~1.1 km per 0.01 deg of latitude)', () {
    final d = GeoUtils.haversineMeters(38.70, -9.10, 38.71, -9.10);
    expect(d, greaterThan(1050));
    expect(d, lessThan(1150));
  });
}
