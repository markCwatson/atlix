import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/features/weather/models/weather_data.dart';
import 'package:monyx/features/weather/services/weather_service.dart';

// ── Service ───────────────────────────────────────────────────────────────────

final weatherServiceProvider = Provider<WeatherService>((_) => WeatherService());

// ── Location key ─────────────────────────────────────────────────────────────

/// Simple lat/lon pair used as provider family argument.
class LatLon {
  const LatLon({required this.lat, required this.lon});

  final double lat;
  final double lon;

  /// Rounded to 2 decimal places so nearby locations share a cached result.
  LatLon get gridded => LatLon(
    lat: (lat * 100).roundToDouble() / 100,
    lon: (lon * 100).roundToDouble() / 100,
  );

  @override
  bool operator ==(Object other) =>
      other is LatLon && lat == other.lat && lon == other.lon;

  @override
  int get hashCode => Object.hash(lat, lon);
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// FutureProvider that fetches weather for a given [LatLon].
/// The family caches by gridded coordinates to avoid redundant calls.
final weatherProvider = FutureProvider.family<WeatherData?, LatLon>((
  ref,
  location,
) async {
  final service = ref.watch(weatherServiceProvider);
  return service.getWeather(location.gridded.lat, location.gridded.lon);
});
