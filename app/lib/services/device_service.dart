import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/app_alert.dart';
import '../models/device.dart';
import '../models/geofence.dart';
import '../models/telemetry_point.dart';
import '../models/zone.dart';

/// The reason for a failure is not exposed: unknown id, wrong PIN and an
/// already paired device all look the same to the client.
enum PairOutcome { success, failed }

/// Firestore access for devices, telemetry, zones and alerts. Reads are
/// exposed as streams so the UI updates as soon as new data arrives.
class DeviceService {
  DeviceService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _devices =>
      _db.collection('devices');

  /// The user's device, or null when none is paired yet. Each caregiver has
  /// one device.
  Stream<Device?> watchUserDevice(String uid) {
    return _devices
        .where('ownerId', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isEmpty ? null : Device.fromSnapshot(snap.docs.first));
  }

  Stream<Device> watchDevice(String deviceId) {
    return _devices
        .doc(deviceId)
        .snapshots()
        .map((snap) => Device.fromSnapshot(snap));
  }

  Stream<TelemetryPoint?> watchLatestTelemetry(String deviceId) {
    return _devices
        .doc(deviceId)
        .collection('telemetry')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : TelemetryPoint.fromSnapshot(snap.docs.first));
  }

  /// Legacy single geofence, read only by [migrateLegacyIfNeeded].
  DocumentReference<Map<String, dynamic>> _geofenceRef(String deviceId) =>
      _devices.doc(deviceId).collection('geofence').doc('current');

  CollectionReference<Map<String, dynamic>> _zonesCol(String deviceId) =>
      _devices.doc(deviceId).collection('geofences');

  Stream<List<Zone>> watchZones(String deviceId) {
    return _zonesCol(deviceId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(Zone.fromSnapshot).toList());
  }

  /// Copies the legacy `geofence/current` document into the `geofences`
  /// collection as "Zone 1". Runs once per device: the `zonesMigrated` flag
  /// keeps the zone from coming back after the user deletes every zone.
  /// The legacy document is kept as a backup.
  Future<void> migrateLegacyIfNeeded(String deviceId) async {
    final deviceRef = _devices.doc(deviceId);
    final deviceSnap = await deviceRef.get();
    if (deviceSnap.data()?['zonesMigrated'] == true) return;

    final zones = _zonesCol(deviceId);
    final existing = await zones.limit(1).get();
    if (existing.docs.isNotEmpty) {
      await deviceRef.set({'zonesMigrated': true}, SetOptions(merge: true));
      return;
    }

    final legacy = await _geofenceRef(deviceId).get();
    if (legacy.exists) {
      final g = Geofence.fromSnapshot(legacy);
      final data = <String, dynamic>{
        'name': 'Zone 1',
        'active': true,
        'color': kZonePalette.first,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (g.isPolygon) {
        data['type'] = 'polygon';
        data['vertices'] = [for (final p in g.points) {'lat': p.lat, 'lng': p.lng}];
      } else {
        data['type'] = 'circle';
        data['center'] = GeoPoint(g.centerLat, g.centerLng);
        data['radius'] = g.radius;
      }
      await zones.add(data);
    }
    await deviceRef.set({'zonesMigrated': true}, SetOptions(merge: true));
  }

  /// Builds a zone document. With [clearOtherType] (updates via
  /// `set(merge: true)`) the other shape's fields are deleted when switching
  /// between circle and polygon. It must be false for `.add()`, which rejects
  /// `FieldValue.delete()`.
  @visibleForTesting
  Map<String, dynamic> zonePayload({
    required String name,
    required GeofenceType type,
    double? centerLat,
    double? centerLng,
    double? radius,
    List<({double lat, double lng})>? vertices,
    required bool active,
    required String colorHex,
    bool clearOtherType = false,
  }) {
    final data = <String, dynamic>{
      'name': name.trim(),
      'type': type == GeofenceType.polygon ? 'polygon' : 'circle',
      'active': active,
      'color': colorHex,
    };
    if (type == GeofenceType.polygon) {
      data['vertices'] = [for (final v in vertices!) {'lat': v.lat, 'lng': v.lng}];
      if (clearOtherType) {
        data['center'] = FieldValue.delete();
        data['radius'] = FieldValue.delete();
      }
    } else {
      data['center'] = GeoPoint(centerLat!, centerLng!);
      data['radius'] = radius;
      if (clearOtherType) {
        data['vertices'] = FieldValue.delete();
      }
    }
    return data;
  }

  Future<String> createZone(
    String deviceId, {
    required String name,
    required GeofenceType type,
    double? centerLat,
    double? centerLng,
    double? radius,
    List<({double lat, double lng})>? vertices,
    required bool active,
    required String colorHex,
  }) async {
    final data = zonePayload(
      name: name, type: type, centerLat: centerLat, centerLng: centerLng,
      radius: radius, vertices: vertices, active: active, colorHex: colorHex,
    )..['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _zonesCol(deviceId).add(data);
    return ref.id;
  }

  Future<void> updateZone(
    String deviceId,
    String zoneId, {
    required String name,
    required GeofenceType type,
    double? centerLat,
    double? centerLng,
    double? radius,
    List<({double lat, double lng})>? vertices,
    required bool active,
    required String colorHex,
  }) {
    final data = zonePayload(
      name: name, type: type, centerLat: centerLat, centerLng: centerLng,
      radius: radius, vertices: vertices, active: active, colorHex: colorHex,
      clearOtherType: true,
    );
    return _zonesCol(deviceId).doc(zoneId).set(data, SetOptions(merge: true));
  }

  Future<void> setZoneActive(String deviceId, String zoneId, bool active) =>
      _zonesCol(deviceId).doc(zoneId).update({'active': active});

  Future<void> renameZone(String deviceId, String zoneId, String name) =>
      _zonesCol(deviceId).doc(zoneId).update({'name': name.trim()});

  Future<void> deleteZone(String deviceId, String zoneId) =>
      _zonesCol(deviceId).doc(zoneId).delete();

  /// Most recent first. Uses the (deviceId ASC, timestamp DESC) index.
  Stream<List<AppAlert>> watchAlerts(String deviceId) {
    return _devices.firestore
        .collection('alerts')
        .where('deviceId', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map(AppAlert.fromSnapshot).toList());
  }

  /// Lets the caregiver acknowledge an alert.
  Future<void> resolveAlert(String alertId) {
    return _devices.firestore.collection('alerts').doc(alertId).update({
      'resolved': true,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Most recent first.
  Stream<List<TelemetryPoint>> watchTelemetryHistory(
    String deviceId, {
    int limit = 50,
  }) {
    return _devices
        .doc(deviceId)
        .collection('telemetry')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(TelemetryPoint.fromSnapshot).toList());
  }

  /// Points since [sinceMs]. Filtering and ordering use the same field, so no
  /// composite index is needed.
  Stream<List<TelemetryPoint>> watchTelemetrySince(
    String deviceId, {
    required int sinceMs,
    int limit = 1000,
  }) {
    return _devices
        .doc(deviceId)
        .collection('telemetry')
        .where('timestamp', isGreaterThanOrEqualTo: sinceMs)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(TelemetryPoint.fromSnapshot).toList());
  }

  /// Claims a device. Non-owners cannot read devices, so the client writes
  /// `ownerId` together with the PIN it was given; the security rules accept
  /// the update only when the PIN matches the stored `pairingCode`.
  Future<PairOutcome> pairDevice(String deviceId, String uid, String pin) async {
    try {
      await _devices.doc(deviceId.trim()).update({
        'ownerId': uid,
        'pairingCode': pin.trim(),
      });
      return PairOutcome.success;
    } catch (_) {
      return PairOutcome.failed;
    }
  }

  Future<void> renameDevice(String deviceId, String name) {
    return _devices.doc(deviceId).update({'name': name.trim()});
  }

  /// Clears the owner. The pairing code is kept so the device can be paired
  /// again with the same PIN.
  Future<void> unpairDevice(String deviceId) {
    return _devices.doc(deviceId).update({'ownerId': ''});
  }
}
