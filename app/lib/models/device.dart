import 'package:cloud_firestore/cloud_firestore.dart';

/// A `devices/{deviceId}` document. [batteryLevel], [lastSeen] and
/// [alertActive] are written by the Cloud Functions; [ownerId] and [name] by
/// the app.
class Device {
  final String id;
  final String ownerId;
  final String name;
  final int? batteryLevel;
  final DateTime? lastSeen;
  final bool alertActive;

  const Device({
    required this.id,
    required this.ownerId,
    required this.name,
    this.batteryLevel,
    this.lastSeen,
    this.alertActive = false,
  });

  factory Device.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    final data = snap.data() ?? const {};
    final name = (data['name'] as String?)?.trim();
    return Device(
      id: snap.id,
      ownerId: data['ownerId'] as String? ?? '',
      name: (name != null && name.isNotEmpty) ? name : snap.id,
      batteryLevel: (data['batteryLevel'] as num?)?.toInt(),
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      alertActive: data['alertActive'] as bool? ?? false,
    );
  }
}
