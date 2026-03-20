import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'package:monyx/../core/constants/app_constants.dart';
import 'package:monyx/features/weather/models/weather_data.dart';

/// Fetches current weather from the Open-Meteo free API and computes
/// density altitude for ballistic correction.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Fetches weather at the given coordinates.
  /// Returns null if the request fails (e.g. offline).
  Future<WeatherData?> getWeather(double lat, double lon) async {
    final uri = Uri.parse(
      '${AppConstants.openMeteoBaseUrl}/forecast'
      '?latitude=$lat'
      '&longitude=$lon'
      '&current=temperature_2m,wind_speed_10m,wind_direction_10m,'
      'surface_pressure,relative_humidity_2m'
      '&wind_speed_unit=ms'
      '&timezone=auto',
    );

    try {
      final response = await _client.get(uri).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final current = body['current'] as Map<String, dynamic>;

      final tempC = (current['temperature_2m'] as num).toDouble();
      final windMs = (current['wind_speed_10m'] as num).toDouble();
      final windDir = (current['wind_direction_10m'] as num).toDouble();
      final pressHpa = (current['surface_pressure'] as num).toDouble();
      final humidity = (current['relative_humidity_2m'] as num).toDouble();

      final da = _computeDensityAltitudeFeet(tempC, pressHpa, humidity);

      return WeatherData(
        temperatureCelsius: tempC,
        windSpeedMs: windMs,
        windDirectionDeg: windDir,
        pressureHpa: pressHpa,
        humidityPercent: humidity,
        densityAltitudeFeet: da,
        fetchedAt: DateTime.now(),
        latitude: lat,
        longitude: lon,
      );
    } catch (_) {
      return null;
    }
  }

  // ── Density altitude ──────────────────────────────────────────────────────────
  //
  // Uses the FAA formula:
  //   DA = PA + (ISA_temp_deviation / 0.003) / 1000
  //
  // Where:
  //   Pressure Altitude (PA) = (1 - (P/1013.25)^0.190284) * 145366.45 feet
  //   ISA temp at PA         = 59 - (3.56 * PA_in_thousands_ft)  [°F]
  //   Station temp (°F)      = C * 9/5 + 32
  //   ISA deviation (°F)     = StationTemp - ISA_temp
  //
  // Correction for humidity (virtual temperature):
  //   Pv = humidity/100 * 6.1078 * 10^(7.5*T/(237.3+T))   [hPa]  (Magnus formula)
  //   Tv = T_kelvin / (1 - (Pv/P)*(1 - 0.622))            [K]

  static double _computeDensityAltitudeFeet(
    double tempC,
    double pressureHpa,
    double humidityPercent,
  ) {
    // Saturation vapour pressure via Magnus formula (hPa)
    final eSat = 6.1078 * math.pow(10, 7.5 * tempC / (237.3 + tempC));
    final eAct = (humidityPercent / 100.0) * eSat;

    // Virtual temperature (K)
    final tempK = tempC + 273.15;
    final tv = tempK / (1 - (eAct / pressureHpa) * (1 - 0.622));

    // Density altitude via hypsometric equation
    // ρ = P / (Rd * Tv)  → DA = (1 - (ρ/ρ0)^0.235) * 145366
    // Simplified: use pressure altitude then temperature correction.
    final pa =
        (1 - math.pow(pressureHpa / 1013.25, 0.190284)) * 145366.45; // feet
    final isaTempF = 59.0 - (3.56561 * pa / 1000.0);
    final stationTempF = tempC * 9 / 5 + 32;
    final isaDev = stationTempF - isaTempF;
    final da = pa + (isaDev / 0.003) / 1000.0 * 1000.0;

    // Use virtual temperature correction for humidity
    final tvCorrection = (tv - tempK) * 120.0; // rough ft correction
    return da + tvCorrection;
  }
}
