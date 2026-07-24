import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_alert.dart';
import '../models/device.dart';
import '../models/geofence.dart';
import '../models/telemetry_point.dart';
import '../models/zone.dart';
import '../services/device_service.dart';

/// The signed-in user's device and its live data: the device document, the
/// latest telemetry point and the zones. Re-subscribes whenever the user
/// changes (see [updateUser]).
class DeviceProvider extends ChangeNotifier {
  DeviceProvider({DeviceService? service})
      : _service = service ?? DeviceService();

  final DeviceService _service;

  String? _uid;
  String? _boundDeviceId;

  StreamSubscription<Device?>? _deviceSub;
  StreamSubscription<TelemetryPoint?>? _telemetrySub;
  StreamSubscription<List<Zone>>? _zonesSub;

  bool _loadingDevice = false;
  bool get loadingDevice => _loadingDevice;

  Device? _device;
  Device? get device => _device;
  bool get hasDevice => _device != null;

  TelemetryPoint? _lastPoint;
  TelemetryPoint? get lastPoint => _lastPoint;

  List<Zone> _zones = const [];
  List<Zone> get zones => _zones;
  List<Zone> get activeZones => [for (final z in _zones) if (z.active) z];
  bool get hasActiveZones => activeZones.isNotEmpty;

  /// The active zone containing the device, or null when outside all zones.
  Zone? get insideZone {
    final p = _lastPoint;
    if (p == null) return null;
    return Zone.firstActiveContaining(activeZones, p.lat, p.lng);
  }

  /// Called from `ProxyProvider.update`, i.e. during build, so it must not
  /// call `notifyListeners()` synchronously. Listeners are notified from the
  /// stream callbacks.
  void updateUser(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _resetAll();

    if (uid == null) {
      _loadingDevice = false;
      return;
    }

    _loadingDevice = true;

    _deviceSub = _service.watchUserDevice(uid).listen((device) {
      _loadingDevice = false;
      _device = device;

      if (device == null) {
        _bindDeviceStreams(null);
      } else if (device.id != _boundDeviceId) {
        _bindDeviceStreams(device.id);
      }
      notifyListeners();
    });
  }

  void _bindDeviceStreams(String? deviceId) {
    _telemetrySub?.cancel();
    _zonesSub?.cancel();
    _lastPoint = null;
    _zones = const [];
    _boundDeviceId = deviceId;

    if (deviceId == null) return;

    _service.migrateLegacyIfNeeded(deviceId);

    _telemetrySub = _service.watchLatestTelemetry(deviceId).listen((point) {
      _lastPoint = point;
      notifyListeners();
    });
    _zonesSub = _service.watchZones(deviceId).listen((zones) {
      _zones = zones;
      notifyListeners();
    });
  }

  void _resetAll() {
    _deviceSub?.cancel();
    _telemetrySub?.cancel();
    _zonesSub?.cancel();
    _deviceSub = null;
    _telemetrySub = null;
    _zonesSub = null;
    _boundDeviceId = null;
    _device = null;
    _lastPoint = null;
    _zones = const [];
  }

  /// On success the device stream picks up the new owner and the app moves on
  /// to the home screen.
  Future<PairOutcome> pairDevice(String deviceId, String uid, String pin) {
    return _service.pairDevice(deviceId, uid, pin);
  }

  String? get deviceId => _device?.id;

  String nextZoneColor() => kZonePalette[_zones.length % kZonePalette.length];

  Future<String?> createZone({
    required String name,
    required GeofenceType type,
    double? centerLat,
    double? centerLng,
    double? radius,
    List<({double lat, double lng})>? vertices,
    required bool active,
    required String colorHex,
  }) {
    final id = _device?.id;
    if (id == null) return Future.value(null);
    return _service.createZone(id,
        name: name,
        type: type,
        centerLat: centerLat,
        centerLng: centerLng,
        radius: radius,
        vertices: vertices,
        active: active,
        colorHex: colorHex);
  }

  Future<void> updateZone(
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
    final id = _device?.id;
    if (id == null) return Future.value();
    return _service.updateZone(id, zoneId,
        name: name,
        type: type,
        centerLat: centerLat,
        centerLng: centerLng,
        radius: radius,
        vertices: vertices,
        active: active,
        colorHex: colorHex);
  }

  Future<void> setZoneActive(String zoneId, bool active) {
    final id = _device?.id;
    if (id == null) return Future.value();
    return _service.setZoneActive(id, zoneId, active);
  }

  Future<void> renameZone(String zoneId, String name) {
    final id = _device?.id;
    if (id == null) return Future.value();
    return _service.renameZone(id, zoneId, name);
  }

  Future<void> deleteZone(String zoneId) {
    final id = _device?.id;
    if (id == null) return Future.value();
    return _service.deleteZone(id, zoneId);
  }

  Stream<List<AppAlert>> watchAlerts() {
    final id = _device?.id;
    if (id == null) return Stream.value(const []);
    return _service.watchAlerts(id);
  }

  Future<void> resolveAlert(String alertId) => _service.resolveAlert(alertId);

  Future<void> renameDevice(String name) {
    final id = _device?.id;
    if (id == null) return Future.value();
    return _service.renameDevice(id, name);
  }

  Future<void> unpairDevice() {
    final id = _device?.id;
    if (id == null) return Future.value();
    return _service.unpairDevice(id);
  }

  Stream<List<TelemetryPoint>> watchHistory({int limit = 50}) {
    final id = _device?.id;
    if (id == null) return Stream.value(const []);
    return _service.watchTelemetryHistory(id, limit: limit);
  }

  Stream<List<TelemetryPoint>> watchHistorySince({
    required int sinceMs,
    int limit = 1000,
  }) {
    final id = _device?.id;
    if (id == null) return Stream.value(const []);
    return _service.watchTelemetrySince(id, sinceMs: sinceMs, limit: limit);
  }

  /// Without new telemetry for this long the device is shown as having no signal.
  static const Duration offlineThreshold = Duration(minutes: 5);

  /// Server time of the last report, falling back to the last point's time.
  DateTime? get lastUpdateTime => _device?.lastSeen ?? _lastPoint?.timestamp;

  bool get isOffline {
    final t = lastUpdateTime;
    if (t == null) return false;
    return DateTime.now().difference(t) > offlineThreshold;
  }

  @override
  void dispose() {
    _resetAll();
    super.dispose();
  }
}
