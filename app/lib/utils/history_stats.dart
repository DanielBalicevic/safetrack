import '../models/telemetry_point.dart';
import '../models/zone.dart';
import '../services/geo_utils.dart';

/// Distance travelled, average speed and share of time spent inside an active
/// zone for a stretch of history.
class HistoryStats {
  final double distanceMeters;
  final double avgSpeedKmh;
  final double? insideFraction; // 0..1, null without active zones or data
  final int pointCount;

  const HistoryStats({
    required this.distanceMeters,
    required this.avgSpeedKmh,
    required this.insideFraction,
    required this.pointCount,
  });

  /// [chrono] must be in chronological order.
  static HistoryStats compute(List<TelemetryPoint> chrono, List<Zone> activeZones) {
    if (chrono.length < 2) {
      return HistoryStats(
        distanceMeters: 0,
        avgSpeedKmh: 0,
        insideFraction: null,
        pointCount: chrono.length,
      );
    }

    double distance = 0;
    for (var i = 1; i < chrono.length; i++) {
      distance += GeoUtils.haversineMeters(
        chrono[i - 1].lat, chrono[i - 1].lng, chrono[i].lat, chrono[i].lng,
      );
    }

    final spanMs = chrono.last.timestamp
        .difference(chrono.first.timestamp)
        .inMilliseconds;
    final hours = spanMs / 3600000.0;
    final avgSpeed = hours > 0 ? (distance / 1000) / hours : 0.0;

    // Each point counts for the time until the next one.
    double? insideFraction;
    if (activeZones.isNotEmpty) {
      double insideMs = 0;
      double totalMs = 0;
      for (var i = 0; i < chrono.length - 1; i++) {
        final dt = chrono[i + 1].timestamp
            .difference(chrono[i].timestamp)
            .inMilliseconds;
        if (dt <= 0) continue;
        totalMs += dt;
        if (Zone.firstActiveContaining(activeZones, chrono[i].lat, chrono[i].lng) != null) {
          insideMs += dt;
        }
      }
      insideFraction = totalMs > 0 ? insideMs / totalMs : null;
    }

    return HistoryStats(
      distanceMeters: distance,
      avgSpeedKmh: avgSpeed,
      insideFraction: insideFraction,
      pointCount: chrono.length,
    );
  }
}
