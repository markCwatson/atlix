import 'dart:math';

/// Convert inches of correction to MOA at a given range in yards.
double inchesToMoa(double inches, double rangeYards) {
  if (rangeYards <= 0) return 0;
  // 1 MOA ≈ 1.047" at 100 yards
  return inches * 100.0 / (1.047 * rangeYards);
}

/// Convert MOA to inches at a given range in yards.
double moaToInches(double moa, double rangeYards) {
  return moa * 1.047 * rangeYards / 100.0;
}

/// Convert MOA to clicks given click value in MOA/click.
int moaToClicks(double moa, double clickValueMoa) {
  if (clickValueMoa <= 0) return 0;
  return (moa / clickValueMoa).round();
}

/// Haversine distance between two lat/lon points in yards.
double haversineYards(double lat1, double lon1, double lat2, double lon2) {
  const earthRadiusFt = 20902231.0; // mean Earth radius in feet
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadiusFt * c / 3.0; // feet to yards
}

/// Bearing from point 1 to point 2 in degrees (0=N, 90=E).
double bearing(double lat1, double lon1, double lat2, double lon2) {
  final dLon = _toRad(lon2 - lon1);
  final y = sin(dLon) * cos(_toRad(lat2));
  final x =
      cos(_toRad(lat1)) * sin(_toRad(lat2)) -
      sin(_toRad(lat1)) * cos(_toRad(lat2)) * cos(dLon);
  return (_toDeg(atan2(y, x)) + 360) % 360;
}

/// Slant range in yards given horizontal distance and elevation difference.
double slantRange(double horizontalYards, double elevDiffFt) {
  final horizFt = horizontalYards * 3.0;
  return sqrt(horizFt * horizFt + elevDiffFt * elevDiffFt) / 3.0;
}

/// Shot angle in degrees (positive = shooting uphill).
double shotAngleDeg(double horizontalYards, double elevDiffFt) {
  if (horizontalYards <= 0) return 0;
  return _toDeg(atan2(elevDiffFt, horizontalYards * 3.0));
}

/// Decompose wind into headwind and crosswind given shooting azimuth.
/// Returns (headwind, crosswind) in the same units as windSpeed.
/// Positive headwind = into shooter's face.
/// Positive crosswind = from left (pushes bullet right).
(double headwind, double crosswind) decomposeWind({
  required double windSpeedMph,
  required double windFromDeg,
  required double shootingAzimuthDeg,
}) {
  final relAngle = _toRad(shootingAzimuthDeg - windFromDeg);
  final headwind = windSpeedMph * cos(relAngle);
  final crosswind = windSpeedMph * sin(relAngle);
  return (headwind, crosswind);
}

/// Haversine distance between two lat/lon points in meters.
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  return haversineYards(lat1, lon1, lat2, lon2) * 0.9144;
}

/// Convert meters to feet.
double metersToFeet(double meters) => meters * 3.28084;

/// Convert Celsius to Fahrenheit.
double celsiusToFahrenheit(double c) => c * 9.0 / 5.0 + 32.0;

/// Convert hPa (hectopascals) to inHg.
double hpaToInHg(double hpa) => hpa * 0.02953;

/// Convert m/s to mph.
double msToMph(double ms) => ms * 2.23694;

/// Convert km/h to mph.
double kmhToMph(double kmh) => kmh * 0.621371;

/// Convert mph to km/h.
double mphToKmh(double mph) => mph * 1.60934;

double _toRad(double deg) => deg * pi / 180.0;
double _toDeg(double rad) => rad * 180.0 / pi;
