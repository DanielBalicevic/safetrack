import 'package:cloud_firestore/cloud_firestore.dart';

enum AlertKind { geofenceExit, lowBattery, offline, unknown }

/// A document from the `alerts` collection. Alerts are created by the Cloud
/// Functions; the app only reads them and can mark them as resolved.
class AppAlert {
  final String id;
  final String deviceId;
  final String type; // "geofence_exit", "low_battery" or "offline"
  final String? zoneName;
  final int distance; // meters to the nearest zone
  final int radius;
  final double lat;
  final double lng;
  final DateTime? timestamp;
  final bool resolved;
  final DateTime? resolvedAt;
  final int? battery;
  final int silentMs;

  const AppAlert({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.zoneName,
    required this.distance,
    required this.radius,
    required this.lat,
    required this.lng,
    required this.timestamp,
    required this.resolved,
    this.resolvedAt,
    this.battery,
    this.silentMs = 0,
  });

  int get metersOutside => (distance - radius).clamp(0, distance);

  AlertKind get kind => switch (type) {
        'geofence_exit' => AlertKind.geofenceExit,
        'low_battery' => AlertKind.lowBattery,
        'offline' => AlertKind.offline,
        _ => AlertKind.unknown,
      };

  /// Offline alerts may have no known position.
  bool get hasPosition => lat != 0 || lng != 0;

  /// "2h05" or "18 min", same format as the backend.
  String get silentFor {
    final totalMin = silentMs ~/ 60000;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m min';
  }

  factory AppAlert.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const {};
    return AppAlert(
      id: snap.id,
      deviceId: data['deviceId'] as String? ?? '',
      // Older alerts have no type and are all geofence exits.
      type: data['type'] as String? ?? 'geofence_exit',
      zoneName: data['zoneName'] as String?,
      distance: (data['distance'] as num?)?.toInt() ?? 0,
      radius: (data['radius'] as num?)?.toInt() ?? 0,
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate(),
      resolved: data['resolved'] as bool? ?? false,
      resolvedAt: (data['resolvedAt'] as Timestamp?)?.toDate(),
      battery: (data['battery'] as num?)?.toInt(),
      silentMs: (data['silentMs'] as num?)?.toInt() ?? 0,
    );
  }
}
