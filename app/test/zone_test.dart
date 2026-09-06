import 'package:flutter_test/flutter_test.dart';
import 'package:safetrack/models/geofence.dart' show GeofenceType;
import 'package:safetrack/models/zone.dart';

/// Mirrors functions/test/geo.test.js so the app and the backend agree.
void main() {
  final square = <({double lat, double lng})>[
    (lat: 38.70, lng: -9.15),
    (lat: 38.70, lng: -9.10),
    (lat: 38.75, lng: -9.10),
    (lat: 38.75, lng: -9.15),
  ];

  Zone circle(String name, {bool active = true}) => Zone(
        id: name,
        name: name,
        type: GeofenceType.circle,
        centerLat: 38.72,
        centerLng: -9.12,
        radius: 150,
        vertices: const [],
        active: active,
        colorHex: '#534AB7',
        createdAt: null,
      );
  Zone poly(String name, {bool active = true}) => Zone(
        id: name,
        name: name,
        type: GeofenceType.polygon,
        centerLat: 0,
        centerLng: 0,
        radius: 0,
        vertices: square,
        active: active,
        colorHex: '#1D9E75',
        createdAt: null,
      );

  test('inside one of two zones returns that zone', () {
    final zones = [circle('Home'), poly('School')];
    expect(Zone.firstActiveContaining(zones, 38.72, -9.13)?.name, 'School');
  });

  test('outside all zones returns null', () {
    final zones = [circle('Home'), poly('School')];
    expect(Zone.firstActiveContaining(zones, 38.80, -9.12), isNull);
  });

  test('inactive zones are ignored', () {
    expect(Zone.firstActiveContaining([circle('Home', active: false)], 38.72, -9.12), isNull);
  });

  test('the circle center is inside', () {
    expect(Zone.firstActiveContaining([circle('Home')], 38.72, -9.12)?.name, 'Home');
  });
}
