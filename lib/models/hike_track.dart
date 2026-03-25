import 'package:equatable/equatable.dart';

/// A single GPS point recorded during a hike.
class HikePoint extends Equatable {
  final double lat;
  final double lon;
  final double altitudeMeters;
  final DateTime timestamp;

  const HikePoint({
    required this.lat,
    required this.lon,
    required this.altitudeMeters,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    'altitudeMeters': altitudeMeters,
    'timestamp': timestamp.toIso8601String(),
  };

  factory HikePoint.fromJson(Map<String, dynamic> json) => HikePoint(
    lat: (json['lat'] as num).toDouble(),
    lon: (json['lon'] as num).toDouble(),
    altitudeMeters: (json['altitudeMeters'] as num).toDouble(),
    timestamp: DateTime.parse(json['timestamp'] as String),
  );

  @override
  List<Object?> get props => [lat, lon, altitudeMeters, timestamp];
}

/// A completed (or in-progress) hike track with summary statistics.
class HikeTrack extends Equatable {
  final String id;
  final String name;
  final List<HikePoint> points;
  final DateTime startTime;
  final DateTime? endTime;

  /// Total distance walked in meters.
  final double totalDistanceMeters;

  /// Active hiking time in seconds (excludes paused intervals).
  final int activeDurationSeconds;

  /// Cumulative uphill elevation change in meters.
  final double elevationGainMeters;

  /// Cumulative downhill elevation change in meters (stored as positive).
  final double elevationLossMeters;

  const HikeTrack({
    required this.id,
    required this.name,
    required this.points,
    required this.startTime,
    this.endTime,
    required this.totalDistanceMeters,
    required this.activeDurationSeconds,
    required this.elevationGainMeters,
    required this.elevationLossMeters,
  });

  /// Total distance in miles.
  double get totalDistanceMiles => totalDistanceMeters * 0.000621371;

  /// Elevation gain in feet.
  double get elevationGainFeet => elevationGainMeters * 3.28084;

  /// Elevation loss in feet.
  double get elevationLossFeet => elevationLossMeters * 3.28084;

  /// Active duration formatted as H:MM:SS.
  String get formattedDuration {
    final h = activeDurationSeconds ~/ 3600;
    final m = (activeDurationSeconds % 3600) ~/ 60;
    final s = activeDurationSeconds % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  /// Average pace in min/mile, or null if distance is zero.
  double? get paceMinPerMile {
    if (totalDistanceMiles <= 0) return null;
    return (activeDurationSeconds / 60.0) / totalDistanceMiles;
  }

  /// Average pace in min/km, or null if distance is zero.
  double? get paceMinPerKm {
    final km = totalDistanceMeters / 1000.0;
    if (km <= 0) return null;
    return (activeDurationSeconds / 60.0) / km;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'points': points.map((p) => p.toJson()).toList(),
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'totalDistanceMeters': totalDistanceMeters,
    'activeDurationSeconds': activeDurationSeconds,
    'elevationGainMeters': elevationGainMeters,
    'elevationLossMeters': elevationLossMeters,
  };

  factory HikeTrack.fromJson(Map<String, dynamic> json) => HikeTrack(
    id: json['id'] as String,
    name: json['name'] as String,
    points: (json['points'] as List)
        .map((p) => HikePoint.fromJson(p as Map<String, dynamic>))
        .toList(),
    startTime: DateTime.parse(json['startTime'] as String),
    endTime: json['endTime'] != null
        ? DateTime.parse(json['endTime'] as String)
        : null,
    totalDistanceMeters: (json['totalDistanceMeters'] as num).toDouble(),
    activeDurationSeconds: json['activeDurationSeconds'] as int,
    elevationGainMeters: (json['elevationGainMeters'] as num).toDouble(),
    elevationLossMeters: (json['elevationLossMeters'] as num).toDouble(),
  );

  @override
  List<Object?> get props => [id];
}
