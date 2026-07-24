import 'package:cloud_firestore/cloud_firestore.dart';

/// `gps` comes from the device's GNSS; `wifi` was resolved on the server from
/// a Wi-Fi scan and is accurate to tens of meters.
enum PositionSource { gps, wifi }

/// A `devices/{deviceId}/telemetry/{pointId}` document.
class TelemetryPoint {
  final String id;
  final double lat;
  final double lng;
  final int battery;
  final DateTime timestamp; // device time (UTC)
  final DateTime? receivedAt; // server time
  final PositionSource source;
  final double accuracy; // meters, 0 for a GPS fix

  const TelemetryPoint({
    required this.id,
    required this.lat,
    required this.lng,
    required this.battery,
    required this.timestamp,
    this.receivedAt,
    this.source = PositionSource.gps,
    this.accuracy = 0,
  });

  bool get isApproximate => source == PositionSource.wifi || accuracy > 0;

  factory TelemetryPoint.fromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const {};
    return TelemetryPoint(
      id: snap.id,
      lat: (data['lat'] as num).toDouble(),
      lng: (data['lng'] as num).toDouble(),
      battery: (data['battery'] as num?)?.toInt() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (data['timestamp'] as num?)?.toInt() ?? 0,
        isUtc: true,
      ),
      receivedAt: (data['receivedAt'] as Timestamp?)?.toDate(),
      source: (data['source'] as String?) == 'wifi'
          ? PositionSource.wifi
          : PositionSource.gps,
      accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0,
    );
  }
}
