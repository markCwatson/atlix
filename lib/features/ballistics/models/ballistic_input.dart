import 'package:monyx/features/profiles/models/rifle_profile.dart';

/// All inputs required for a ballistic calculation.
class BallisticInput {
  const BallisticInput({
    required this.rifleProfile,
    required this.rangeYards,
    this.shootingAngleDegrees = 0.0,
    this.windSpeedMph = 0.0,
    this.windDirectionDegrees = 90.0,
    this.temperatureFahrenheit = 59.0,
    this.pressureInHg = 29.92,
    this.humidityPercent = 50.0,
    this.altitudeFeet = 0.0,
  });

  final RifleProfile rifleProfile;

  /// Slant range to the target (yards).
  final double rangeYards;

  /// Shooting angle in degrees.  Positive = uphill, negative = downhill.
  final double shootingAngleDegrees;

  /// Wind speed at the shooter's position (mph).
  final double windSpeedMph;

  /// Wind direction relative to shooter:
  ///   0° = full headwind, 90° = right-to-left, 180° = full tailwind, 270° = left-to-right.
  final double windDirectionDegrees;

  final double temperatureFahrenheit;

  /// Barometric pressure at shooting location (inches of mercury).
  final double pressureInHg;

  final double humidityPercent;

  /// Elevation of the shooting position above sea level (feet).
  final double altitudeFeet;

  BallisticInput copyWith({
    RifleProfile? rifleProfile,
    double? rangeYards,
    double? shootingAngleDegrees,
    double? windSpeedMph,
    double? windDirectionDegrees,
    double? temperatureFahrenheit,
    double? pressureInHg,
    double? humidityPercent,
    double? altitudeFeet,
  }) => BallisticInput(
    rifleProfile: rifleProfile ?? this.rifleProfile,
    rangeYards: rangeYards ?? this.rangeYards,
    shootingAngleDegrees: shootingAngleDegrees ?? this.shootingAngleDegrees,
    windSpeedMph: windSpeedMph ?? this.windSpeedMph,
    windDirectionDegrees: windDirectionDegrees ?? this.windDirectionDegrees,
    temperatureFahrenheit: temperatureFahrenheit ?? this.temperatureFahrenheit,
    pressureInHg: pressureInHg ?? this.pressureInHg,
    humidityPercent: humidityPercent ?? this.humidityPercent,
    altitudeFeet: altitudeFeet ?? this.altitudeFeet,
  );
}
