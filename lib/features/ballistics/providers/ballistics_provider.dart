import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:monyx/core/constants/app_constants.dart';
import 'package:monyx/core/utils/geo_utils.dart';
import 'package:monyx/features/map/providers/map_provider.dart';
import 'package:monyx/features/profiles/providers/profile_provider.dart';
import 'package:monyx/features/weather/providers/weather_provider.dart';
import 'package:monyx/features/ballistics/models/ballistic_input.dart';
import 'package:monyx/features/ballistics/models/ballistic_result_state.dart';
import 'package:monyx/features/ballistics/models/ballistic_solution.dart';
import 'package:monyx/features/ballistics/solver/ballistic_solver.dart';

// ── Solver provider (singleton) ───────────────────────────────────────────────

final ballisticSolverProvider = Provider<BallisticSolver>(
  (_) => const BallisticSolver(),
);

// ── Input provider ────────────────────────────────────────────────────────────

final ballisticInputProvider = StateProvider<BallisticInput?>((ref) {
  // Auto-build input from active map pin + profile + weather when all available
  final mapState = ref.watch(mapStateProvider);
  final activeProfile = ref.watch(activeRifleProfileProvider);
  final selectedPin = mapState.selectedPin;

  if (activeProfile == null || selectedPin == null) return null;
  if (!mapState.hasLocation) return null;

  final rangeM = GeoUtils.haversineDistance(
    mapState.userLatitude!,
    mapState.userLongitude!,
    selectedPin.latitude,
    selectedPin.longitude,
  );
  final rangeYards = GeoUtils.metersToYards(rangeM);

  double shootingAngle = 0.0;
  if (mapState.userElevationMeters != null &&
      selectedPin.elevationMeters != null) {
    final elevDiff =
        selectedPin.elevationMeters! - mapState.userElevationMeters!;
    shootingAngle = GeoUtils.shootingAngleDeg(rangeM, elevDiff);
  }

  return BallisticInput(
    rifleProfile: activeProfile,
    rangeYards: rangeYards,
    shootingAngleDegrees: shootingAngle,
    temperatureFahrenheit: AppConstants.standardTempF,
    pressureInHg: AppConstants.standardPressureInHg,
  );
});

// ── Result notifier ───────────────────────────────────────────────────────────

class BallisticsNotifier extends StateNotifier<BallisticResultState> {
  BallisticsNotifier(this._ref) : super(const BallisticResultState());

  final Ref _ref;

  Future<void> compute([BallisticInput? overrideInput]) async {
    final input = overrideInput ?? _ref.read(ballisticInputProvider);
    if (input == null) {
      state = state.copyWith(
        clearSolution: true,
        errorMessage: 'No target selected or profile missing',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final solver = _ref.read(ballisticSolverProvider);
      final solution = await Future.microtask(() => solver.solve(input));
      final card = await Future.microtask(
        () => solver.rangeCard(
          input,
          maxRangeYards: 1000,
          stepYards: 25,
        ),
      );
      state = state.copyWith(
        isLoading: false,
        solution: solution,
        rangeCard: card,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Solver error: $e',
        clearSolution: true,
      );
    }
  }

  /// Update a specific environmental override and recompute.
  Future<void> updateWeather({
    double? windSpeedMph,
    double? windDirectionDeg,
    double? temperatureF,
    double? pressureInHg,
    double? humidity,
  }) async {
    final current = _ref.read(ballisticInputProvider);
    if (current == null) return;
    final updated = current.copyWith(
      windSpeedMph: windSpeedMph,
      windDirectionDegrees: windDirectionDeg,
      temperatureFahrenheit: temperatureF,
      pressureInHg: pressureInHg,
      humidityPercent: humidity,
    );
    _ref.read(ballisticInputProvider.notifier).state = updated;
    await compute(updated);
  }
}

final ballisticsProvider =
    StateNotifierProvider<BallisticsNotifier, BallisticResultState>((ref) {
      return BallisticsNotifier(ref);
    });

// ── Convenience: solution only ────────────────────────────────────────────────

final ballisticSolutionProvider = Provider<BallisticSolution?>((ref) {
  return ref.watch(ballisticsProvider).solution;
});

// ── Auto-apply weather from WeatherService ────────────────────────────────────

final weatherAppliedInputProvider = Provider<BallisticInput?>((ref) {
  final base = ref.watch(ballisticInputProvider);
  if (base == null) return null;

  final mapState = ref.watch(mapStateProvider);
  if (!mapState.hasLocation) return base;

  final weatherAsync = ref.watch(
    weatherProvider(
      LatLon(lat: mapState.userLatitude!, lon: mapState.userLongitude!),
    ),
  );

  return weatherAsync.whenOrNull(
    data: (w) {
      if (w == null) return base;
      final windMph = GeoUtils.msToMph(w.windSpeedMs);
      final pressInHg = w.pressureHpa * 0.02952998;
      final tempF = GeoUtils.celsiusToFahrenheit(w.temperatureCelsius);
      return base.copyWith(
        windSpeedMph: windMph,
        windDirectionDegrees: w.windDirectionDeg,
        temperatureFahrenheit: tempF,
        pressureInHg: pressInHg,
        humidityPercent: w.humidityPercent,
      );
    },
  ) ?? base;
});
