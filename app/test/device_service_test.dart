import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safetrack/models/geofence.dart' show GeofenceType;
import 'package:safetrack/services/device_service.dart';

/// [DeviceService] against an in-memory Firestore. Covers two regressions:
///  - creating a zone must never send `FieldValue.delete()`, which `.add()`
///    rejects;
///  - the legacy migration runs once per device, so deleting every zone does
///    not bring "Zone 1" back.
void main() {
  late FakeFirebaseFirestore db;
  late DeviceService service;
  const deviceId = 'test-device';

  setUp(() {
    db = FakeFirebaseFirestore();
    service = DeviceService(firestore: db);
  });

  CollectionReference<Map<String, dynamic>> zonesCol() =>
      db.collection('devices/$deviceId/geofences');

  group('zonePayload', () {
    test('creating a circle contains no FieldValue',
        () {
      final data = service.zonePayload(
        name: 'Home',
        type: GeofenceType.circle,
        centerLat: 37.1,
        centerLng: -8.2,
        radius: 200,
        active: true,
        colorHex: '#534AB7',
      );
      expect(data.values.whereType<FieldValue>(), isEmpty);
      expect(data['center'], isA<GeoPoint>());
      expect(data['radius'], 200);
      expect(data.containsKey('vertices'), isFalse);
    });

    test('creating a polygon contains no FieldValue', () {
      final data = service.zonePayload(
        name: 'Park',
        type: GeofenceType.polygon,
        vertices: const [(lat: 1, lng: 1), (lat: 2, lng: 2), (lat: 3, lng: 1)],
        active: true,
        colorHex: '#1D9E75',
      );
      expect(data.values.whereType<FieldValue>(), isEmpty);
      expect(data['vertices'], isA<List>());
      expect(data.containsKey('center'), isFalse);
      expect(data.containsKey('radius'), isFalse);
    });

    test('updating deletes the other shape\'s fields', () {
      final circle = service.zonePayload(
        name: 'Home',
        type: GeofenceType.circle,
        centerLat: 1,
        centerLng: 1,
        radius: 100,
        active: true,
        colorHex: '#534AB7',
        clearOtherType: true,
      );
      expect(circle['vertices'], isA<FieldValue>());

      final poly = service.zonePayload(
        name: 'Park',
        type: GeofenceType.polygon,
        vertices: const [(lat: 1, lng: 1), (lat: 2, lng: 2), (lat: 3, lng: 1)],
        active: true,
        colorHex: '#1D9E75',
        clearOtherType: true,
      );
      expect(poly['center'], isA<FieldValue>());
      expect(poly['radius'], isA<FieldValue>());
    });
  });

  group('createZone', () {
    test('creates a circle with center and radius, without vertices', () async {
      final id = await service.createZone(
        deviceId,
        name: 'Home',
        type: GeofenceType.circle,
        centerLat: 37.1,
        centerLng: -8.2,
        radius: 200,
        active: true,
        colorHex: '#534AB7',
      );
      final doc = await zonesCol().doc(id).get();
      final data = doc.data()!;
      expect(data['type'], 'circle');
      expect(data['center'], isA<GeoPoint>());
      expect((data['center'] as GeoPoint).latitude, closeTo(37.1, 1e-9));
      expect(data['radius'], 200);
      expect(data['active'], true);
      expect(data.containsKey('vertices'), isFalse);
      expect(data['createdAt'], isNotNull);
    });

    test('creates a polygon with vertices, without center and radius', () async {
      final id = await service.createZone(
        deviceId,
        name: 'Park',
        type: GeofenceType.polygon,
        vertices: const [(lat: 1, lng: 1), (lat: 2, lng: 2), (lat: 3, lng: 1)],
        active: true,
        colorHex: '#1D9E75',
      );
      final data = (await zonesCol().doc(id).get()).data()!;
      expect(data['type'], 'polygon');
      expect((data['vertices'] as List).length, 3);
      expect(data.containsKey('center'), isFalse);
      expect(data.containsKey('radius'), isFalse);
    });
  });

  group('updateZone / deleteZone', () {
    test('switching from polygon to circle removes the vertices', () async {
      final id = await service.createZone(
        deviceId,
        name: 'Zone',
        type: GeofenceType.polygon,
        vertices: const [(lat: 1, lng: 1), (lat: 2, lng: 2), (lat: 3, lng: 1)],
        active: true,
        colorHex: '#1D9E75',
      );
      await service.updateZone(
        deviceId,
        id,
        name: 'Zone',
        type: GeofenceType.circle,
        centerLat: 5,
        centerLng: 5,
        radius: 150,
        active: true,
        colorHex: '#1D9E75',
      );
      final data = (await zonesCol().doc(id).get()).data()!;
      expect(data['type'], 'circle');
      expect(data['radius'], 150);
      expect(data.containsKey('vertices'), isFalse);
    });

    test('deleteZone removes the document', () async {
      final id = await service.createZone(
        deviceId,
        name: 'X',
        type: GeofenceType.circle,
        centerLat: 1,
        centerLng: 1,
        radius: 100,
        active: true,
        colorHex: '#534AB7',
      );
      await service.deleteZone(deviceId, id);
      expect((await zonesCol().doc(id).get()).exists, isFalse);
    });
  });

  group('migrateLegacyIfNeeded', () {
    Future<void> seedLegacy() async {
      await db.doc('devices/$deviceId').set({'ownerId': 'u1'});
      await db.doc('devices/$deviceId/geofence/current').set({
        'centerLat': 37.1,
        'centerLng': -8.2,
        'radius': 230.0,
        'active': true,
      });
    }

    Future<bool> migratedFlag() async =>
        (await db.doc('devices/$deviceId').get()).data()?['zonesMigrated'] ==
        true;

    test('creates "Zone 1" from the legacy document and sets the flag', () async {
      await seedLegacy();
      await service.migrateLegacyIfNeeded(deviceId);

      final zones = await zonesCol().get();
      expect(zones.docs.length, 1);
      expect(zones.docs.first.data()['name'], 'Zone 1');
      expect((zones.docs.first.data()['center'] as GeoPoint).latitude,
          closeTo(37.1, 1e-9));
      expect(await migratedFlag(), isTrue);
    });

    test('running again does not duplicate the zone', () async {
      await seedLegacy();
      await service.migrateLegacyIfNeeded(deviceId);
      await service.migrateLegacyIfNeeded(deviceId);
      expect((await zonesCol().get()).docs.length, 1);
    });

    test('deleting every zone does not bring Zone 1 back', () async {
      await seedLegacy();
      await service.migrateLegacyIfNeeded(deviceId);

      final only = (await zonesCol().get()).docs.first;
      await service.deleteZone(deviceId, only.id);
      expect((await zonesCol().get()).docs, isEmpty);

      await service.migrateLegacyIfNeeded(deviceId);
      expect((await zonesCol().get()).docs, isEmpty,
          reason: 'zonesMigrated must prevent seeding again');
    });

    test('existing zones without the flag: sets the flag and seeds nothing', () async {
      await db.doc('devices/$deviceId').set({'ownerId': 'u1'});
      await service.createZone(
        deviceId,
        name: 'Mine',
        type: GeofenceType.circle,
        centerLat: 1,
        centerLng: 1,
        radius: 100,
        active: true,
        colorHex: '#534AB7',
      );
      await service.migrateLegacyIfNeeded(deviceId);
      expect((await zonesCol().get()).docs.length, 1);
      expect(await migratedFlag(), isTrue);
    });

    test('no legacy document: creates nothing but sets the flag', () async {
      await db.doc('devices/$deviceId').set({'ownerId': 'u1'});
      await service.migrateLegacyIfNeeded(deviceId);
      expect((await zonesCol().get()).docs, isEmpty);
      expect(await migratedFlag(), isTrue);
    });
  });
}
