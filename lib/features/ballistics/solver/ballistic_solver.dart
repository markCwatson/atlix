import 'dart:math' as math;

import 'package:monyx/features/ballistics/models/ballistic_input.dart';
import 'package:monyx/features/ballistics/models/ballistic_solution.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// G1 Standard Drag Table
//
// Source: Ingalls tables / Hornady G1 reference, re-expressed as
//   CD_form_factor(Mach) where the retardation coefficient is:
//   a(v) = (ρ/ρ₀) × v² × (π/8) × (d²/m) × CD(Mach) / BC_form_factor
//
// The table stores [Mach, drag_coefficient] pairs.
// Intermediate values are linearly interpolated.
// ═══════════════════════════════════════════════════════════════════════════════

/// A single entry in the drag function table.
class _DragPoint {
  const _DragPoint(this.mach, this.cd);
  final double mach;
  final double cd;
}

/// G1 drag coefficient table indexed by Mach number.
/// These values reproduce the classic Siacci/Ingalls G1 drag model.
const List<_DragPoint> _g1Table = [
  _DragPoint(0.00, 0.2629),
  _DragPoint(0.05, 0.2558),
  _DragPoint(0.10, 0.2487),
  _DragPoint(0.15, 0.2413),
  _DragPoint(0.20, 0.2340),
  _DragPoint(0.25, 0.2265),
  _DragPoint(0.30, 0.2190),
  _DragPoint(0.35, 0.2116),
  _DragPoint(0.40, 0.2043),
  _DragPoint(0.45, 0.1972),
  _DragPoint(0.50, 0.1903),
  _DragPoint(0.55, 0.1838),
  _DragPoint(0.60, 0.1774),
  _DragPoint(0.65, 0.1714),
  _DragPoint(0.70, 0.1657),
  _DragPoint(0.725, 0.1630),
  _DragPoint(0.75, 0.1607),
  _DragPoint(0.775, 0.1588),
  _DragPoint(0.80, 0.1572),
  _DragPoint(0.825, 0.1558),
  _DragPoint(0.85, 0.1546),
  _DragPoint(0.875, 0.1536),
  _DragPoint(0.90, 0.1530),
  _DragPoint(0.925, 0.1528),
  _DragPoint(0.95, 0.1532),
  _DragPoint(0.975, 0.1543),
  _DragPoint(1.00, 0.1579),
  _DragPoint(1.025, 0.1638),
  _DragPoint(1.05, 0.1718),
  _DragPoint(1.075, 0.1804),
  _DragPoint(1.10, 0.1895),
  _DragPoint(1.125, 0.1984),
  _DragPoint(1.15, 0.2069),
  _DragPoint(1.20, 0.2230),
  _DragPoint(1.25, 0.2368),
  _DragPoint(1.30, 0.2483),
  _DragPoint(1.35, 0.2579),
  _DragPoint(1.40, 0.2659),
  _DragPoint(1.45, 0.2728),
  _DragPoint(1.50, 0.2788),
  _DragPoint(1.55, 0.2840),
  _DragPoint(1.60, 0.2884),
  _DragPoint(1.65, 0.2916),
  _DragPoint(1.70, 0.2948),
  _DragPoint(1.75, 0.2976),
  _DragPoint(1.80, 0.3001),
  _DragPoint(1.85, 0.3023),
  _DragPoint(1.90, 0.3042),
  _DragPoint(1.95, 0.3058),
  _DragPoint(2.00, 0.3070),
  _DragPoint(2.05, 0.3080),
  _DragPoint(2.10, 0.3087),
  _DragPoint(2.15, 0.3092),
  _DragPoint(2.20, 0.3095),
  _DragPoint(2.25, 0.3097),
  _DragPoint(2.30, 0.3098),
  _DragPoint(2.35, 0.3097),
  _DragPoint(2.40, 0.3095),
  _DragPoint(2.45, 0.3091),
  _DragPoint(2.50, 0.3086),
  _DragPoint(2.60, 0.3073),
  _DragPoint(2.70, 0.3057),
  _DragPoint(2.80, 0.3039),
  _DragPoint(2.90, 0.3020),
  _DragPoint(3.00, 0.2999),
  _DragPoint(3.10, 0.2977),
  _DragPoint(3.20, 0.2955),
  _DragPoint(3.30, 0.2931),
  _DragPoint(3.40, 0.2908),
  _DragPoint(3.50, 0.2883),
  _DragPoint(3.60, 0.2858),
  _DragPoint(3.70, 0.2833),
  _DragPoint(3.80, 0.2807),
  _DragPoint(3.90, 0.2780),
  _DragPoint(4.00, 0.2753),
  _DragPoint(4.20, 0.2697),
  _DragPoint(4.40, 0.2640),
  _DragPoint(4.60, 0.2581),
  _DragPoint(4.80, 0.2520),
  _DragPoint(5.00, 0.2459),
];

/// G7 drag coefficient table indexed by Mach number.
/// G7 is the preferred model for long-range, boat-tail bullets.
const List<_DragPoint> _g7Table = [
  _DragPoint(0.00, 0.1198),
  _DragPoint(0.05, 0.1197),
  _DragPoint(0.10, 0.1196),
  _DragPoint(0.15, 0.1194),
  _DragPoint(0.20, 0.1193),
  _DragPoint(0.25, 0.1194),
  _DragPoint(0.30, 0.1194),
  _DragPoint(0.35, 0.1194),
  _DragPoint(0.40, 0.1193),
  _DragPoint(0.45, 0.1193),
  _DragPoint(0.50, 0.1194),
  _DragPoint(0.55, 0.1193),
  _DragPoint(0.60, 0.1194),
  _DragPoint(0.65, 0.1197),
  _DragPoint(0.70, 0.1202),
  _DragPoint(0.725, 0.1207),
  _DragPoint(0.75, 0.1215),
  _DragPoint(0.775, 0.1226),
  _DragPoint(0.80, 0.1242),
  _DragPoint(0.825, 0.1266),
  _DragPoint(0.85, 0.1306),
  _DragPoint(0.875, 0.1368),
  _DragPoint(0.90, 0.1464),
  _DragPoint(0.925, 0.1594),
  _DragPoint(0.95, 0.1730),
  _DragPoint(0.975, 0.1858),
  _DragPoint(1.00, 0.1968),
  _DragPoint(1.025, 0.2060),
  _DragPoint(1.05, 0.2130),
  _DragPoint(1.10, 0.2218),
  _DragPoint(1.15, 0.2278),
  _DragPoint(1.20, 0.2303),
  _DragPoint(1.25, 0.2313),
  _DragPoint(1.30, 0.2310),
  _DragPoint(1.35, 0.2298),
  _DragPoint(1.40, 0.2280),
  _DragPoint(1.50, 0.2230),
  _DragPoint(1.60, 0.2174),
  _DragPoint(1.70, 0.2116),
  _DragPoint(1.80, 0.2059),
  _DragPoint(1.90, 0.2004),
  _DragPoint(2.00, 0.1952),
  _DragPoint(2.20, 0.1853),
  _DragPoint(2.40, 0.1758),
  _DragPoint(2.60, 0.1668),
  _DragPoint(2.80, 0.1581),
  _DragPoint(3.00, 0.1500),
  _DragPoint(3.20, 0.1422),
  _DragPoint(3.40, 0.1350),
  _DragPoint(3.60, 0.1282),
  _DragPoint(3.80, 0.1220),
  _DragPoint(4.00, 0.1163),
  _DragPoint(4.50, 0.1050),
  _DragPoint(5.00, 0.0950),
];

// ═══════════════════════════════════════════════════════════════════════════════
// Ballistic Solver
// ═══════════════════════════════════════════════════════════════════════════════

/// 3-DoF point-mass ballistic solver using the Pejsa / Siacci drag model
/// with table-based G1 or G7 drag functions.
///
/// Equations of motion (in the shooter's frame, X downrange, Y up, Z right):
///
///   dVx/dt = -Fd * Vx/|V|   - (wind correction is handled separately)
///   dVy/dt = -Fd * Vy/|V|   - g*cos(angle)
///   dVz/dt = -Fd * Vz/|V|
///
/// Where Fd is the drag retardation magnitude:
///   Fd = (ρ/ρ₀) × (Cd(Mach) / BC) × v² × k
///   k  = (1 / (2 * m/A)) = constant absorbed into BC definition
///
/// The BC already encodes the form factor vs the reference projectile, so
/// the net retardation (ft/s² or m/s²) is:
///   a_ret = (ρ/ρ₀) × Cd(Mach) × v² / (2 × BC × i)
/// where i=1 for the G1 model (BC already in G1 units).
class BallisticSolver {
  const BallisticSolver();

  // ── Constants ────────────────────────────────────────────────────────────────

  static const double _g = 9.80665; // m/s²
  static const double _stdSpeedOfSoundMs = 340.29; // m/s at sea level, 15°C
  static const double _stdDensityKgm3 = 1.2250; // kg/m³ at sea level, 15°C

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Compute the ballistic solution at the target range specified by [input].
  BallisticSolution solve(BallisticInput input) {
    final results = _integrate(input);
    return _buildSolution(input, results);
  }

  /// Compute a range card from 0 to [maxRangeYards] in [stepYards] increments.
  List<BallisticSolution> rangeCard(
    BallisticInput input, {
    int maxRangeYards = 1000,
    int stepYards = 25,
  }) {
    final card = <BallisticSolution>[];
    for (int r = stepYards; r <= maxRangeYards; r += stepYards) {
      final cardInput = input.copyWith(rangeYards: r.toDouble());
      card.add(solve(cardInput));
    }
    return card;
  }

  // ── Core integration ──────────────────────────────────────────────────────────

  _TrajectoryResult _integrate(BallisticInput input) {
    final profile = input.rifleProfile;
    final bullet = profile.bulletProfile;

    // Prefer G7 if available, else use G1
    final useG7 = bullet.ballisticCoefficientG7 != null;
    final bc = useG7
        ? bullet.ballisticCoefficientG7!
        : bullet.ballisticCoefficientG1;
    final dragTable = useG7 ? _g7Table : _g1Table;

    // ── Atmospheric conditions ───────────────────────────────────────────────
    final rho = _airDensity(
      input.temperatureFahrenheit,
      input.pressureInHg,
      input.humidityPercent,
    );
    final densityRatio = rho / _stdDensityKgm3;
    final speedOfSound = _speedOfSound(input.temperatureFahrenheit);

    // ── Convert units to SI ──────────────────────────────────────────────────
    final muzzleVelocityMs = _fpsToMs(bullet.muzzleVelocityFps);
    final targetRangeM = _yardsToM(input.rangeYards);
    final zeroRangeM = _yardsToM(profile.zeroDistanceYards);
    final sightHeightM = profile.sightHeightInches * 0.0254;

    // Angle of fire due to shooting angle (Rifleman's Rule: use cosine for
    // gravity component along the horizontal, since drop is roughly a
    // function of horizontal distance to target).
    final angleDeg = input.shootingAngleDegrees;
    final angleRad = angleDeg * math.pi / 180.0;
    final cosAngle = math.cos(angleRad);

    // Wind crosswind component (perpendicular to bore, right is positive)
    // wind_dir: 0=headwind, 90=right→left wind (pushes bullet right), etc.
    final windSpeedMs = input.windSpeedMph * 0.44704;
    final windDirRad = input.windDirectionDegrees * math.pi / 180.0;
    final crosswindMs = windSpeedMs * math.sin(windDirRad);

    // ── Zero the rifle ───────────────────────────────────────────────────────
    // Find the launch elevation angle that achieves zero at zeroRangeM.
    final zeroAngleRad = _findZeroAngle(
      muzzleVelocityMs: muzzleVelocityMs,
      zeroRangeM: zeroRangeM,
      sightHeightM: sightHeightM,
      bc: bc,
      densityRatio: densityRatio,
      speedOfSound: speedOfSound,
      dragTable: dragTable,
      shootingAngleCos: cosAngle,
    );

    // ── Integrate to target range ────────────────────────────────────────────
    return _runTrajectory(
      muzzleVelocityMs: muzzleVelocityMs,
      launchElevationRad: zeroAngleRad,
      targetRangeM: targetRangeM,
      sightHeightM: sightHeightM,
      zeroRangeM: zeroRangeM,
      bc: bc,
      densityRatio: densityRatio,
      speedOfSound: speedOfSound,
      crosswindMs: crosswindMs,
      dragTable: dragTable,
      shootingAngleCos: cosAngle,
      twistInchesPerTurn: profile.twistRateInchesPerTwist,
      bulletDiameterInches: bullet.bulletDiameterInches,
    );
  }

  // ── Zero-finding ──────────────────────────────────────────────────────────────

  /// Bisection search for the launch elevation angle that makes the bullet
  /// cross the line-of-sight at [zeroRangeM].
  double _findZeroAngle({
    required double muzzleVelocityMs,
    required double zeroRangeM,
    required double sightHeightM,
    required double bc,
    required double densityRatio,
    required double speedOfSound,
    required List<_DragPoint> dragTable,
    required double shootingAngleCos,
  }) {
    double lo = -0.05; // -3°
    double hi = 0.05;  //  3°

    for (int i = 0; i < 50; i++) {
      final mid = (lo + hi) / 2;
      final result = _runTrajectory(
        muzzleVelocityMs: muzzleVelocityMs,
        launchElevationRad: mid,
        targetRangeM: zeroRangeM,
        sightHeightM: sightHeightM,
        zeroRangeM: zeroRangeM,
        bc: bc,
        densityRatio: densityRatio,
        speedOfSound: speedOfSound,
        crosswindMs: 0,
        dragTable: dragTable,
        shootingAngleCos: shootingAngleCos,
        twistInchesPerTurn: 10,
        bulletDiameterInches: 0.308,
      );
      // We want bullet height at zero range to equal sight height above bore.
      // Drop from LOS = 0 → bullet Y at zeroRange = 0 (relative to LOS).
      // result.dropM is the bullet Y minus LOS Y.  We want it to be 0.
      if (result.dropM > 0) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    return (lo + hi) / 2;
  }

  // ── Trajectory integration (RK4) ─────────────────────────────────────────────

  _TrajectoryResult _runTrajectory({
    required double muzzleVelocityMs,
    required double launchElevationRad,
    required double targetRangeM,
    required double sightHeightM,
    required double zeroRangeM,
    required double bc,
    required double densityRatio,
    required double speedOfSound,
    required double crosswindMs,
    required List<_DragPoint> dragTable,
    required double shootingAngleCos,
    required double twistInchesPerTurn,
    required double bulletDiameterInches,
  }) {
    const double dt = 0.0005; // 0.5 ms time step
    const int maxSteps = 40000;

    // State: [x, y, z, vx, vy, vz]
    // x = downrange, y = vertical, z = lateral
    double x = 0;
    double y = -sightHeightM; // bore is below sight line
    double z = 0;
    double vx = muzzleVelocityMs * math.cos(launchElevationRad);
    double vy = muzzleVelocityMs * math.sin(launchElevationRad);
    double vz = 0;

    // Line-of-sight slope (rise over run), accounting for shooting angle
    // LOS drops at the sine of shooting angle per unit of horizontal distance
    final losSlope = math.tan(launchElevationRad); // approximated from zero

    // Spin drift accumulator
    // Litz formula: drift ≈ 1.25*(sg+1.2) * t^1.83  (inches at range)
    // We compute it at the end via empirical estimate.

    double t = 0;
    int step = 0;

    // Variables to sample at target range
    double dropAtTarget = 0;
    double zAtTarget = 0;
    double vAtTarget = 0;
    double tAtTarget = 0;

    // Previous x for interpolation
    double xPrev = 0;
    double yPrev = y;
    double zPrev = z;
    double tPrev = 0;
    double vPrev = muzzleVelocityMs;

    bool reached = false;

    while (step < maxSteps && x < targetRangeM * 1.01) {
      final v = math.sqrt(vx * vx + vy * vy + vz * vz);
      if (v < 1.0) break; // bullet stopped

      final mach = v / speedOfSound;
      final cd = _interpolateDrag(dragTable, mach);

      // Drag retardation magnitude (m/s²)
      // a_drag = (ρ/ρ₀) * Cd * v² / (2 * BC_lb_sq_in)
      // BC must be converted: 1 lb/in² = 703.07 kg/m²
      final bcSI = bc * 703.07; // kg/m²
      final aDrag = densityRatio * cd * v * v / (2.0 * bcSI);

      // Drag acceleration components (oppose velocity)
      final ax = -aDrag * vx / v;
      // Gravity acts downward; shooting angle handled via cosine rule:
      // gravity component perpendicular to line of fire = g*cos(angle)
      final ay = -aDrag * vy / v - _g * shootingAngleCos;
      // Wind acceleration: only for steady crosswind (simplified – no lag)
      final windAccZ = (crosswindMs - vz) * aDrag / v;
      final az = -aDrag * vz / v + windAccZ;

      xPrev = x;
      yPrev = y;
      zPrev = z;
      tPrev = t;
      vPrev = v;

      // RK4 integration
      // k1
      final k1vx = ax; final k1vy = ay; final k1vz = az;
      final k1x = vx; final k1y = vy; final k1z = vz;

      // k2
      final vx2 = vx + k1vx * dt / 2;
      final vy2 = vy + k1vy * dt / 2;
      final vz2 = vz + k1vz * dt / 2;
      final v2 = math.sqrt(vx2*vx2 + vy2*vy2 + vz2*vz2).clamp(0.1, double.infinity);
      final m2 = v2 / speedOfSound;
      final cd2 = _interpolateDrag(dragTable, m2);
      final a2 = densityRatio * cd2 * v2 * v2 / (2.0 * bcSI);
      final k2vx = -a2*vx2/v2;
      final k2vy = -a2*vy2/v2 - _g*shootingAngleCos;
      final k2vz = -a2*vz2/v2 + (crosswindMs - vz2)*a2/v2;
      final k2x = vx2; final k2y = vy2; final k2z = vz2;

      // k3
      final vx3 = vx + k2vx * dt / 2;
      final vy3 = vy + k2vy * dt / 2;
      final vz3 = vz + k2vz * dt / 2;
      final v3 = math.sqrt(vx3*vx3 + vy3*vy3 + vz3*vz3).clamp(0.1, double.infinity);
      final m3 = v3 / speedOfSound;
      final cd3 = _interpolateDrag(dragTable, m3);
      final a3 = densityRatio * cd3 * v3 * v3 / (2.0 * bcSI);
      final k3vx = -a3*vx3/v3;
      final k3vy = -a3*vy3/v3 - _g*shootingAngleCos;
      final k3vz = -a3*vz3/v3 + (crosswindMs - vz3)*a3/v3;
      final k3x = vx3; final k3y = vy3; final k3z = vz3;

      // k4
      final vx4 = vx + k3vx * dt;
      final vy4 = vy + k3vy * dt;
      final vz4 = vz + k3vz * dt;
      final v4 = math.sqrt(vx4*vx4 + vy4*vy4 + vz4*vz4).clamp(0.1, double.infinity);
      final m4 = v4 / speedOfSound;
      final cd4 = _interpolateDrag(dragTable, m4);
      final a4 = densityRatio * cd4 * v4 * v4 / (2.0 * bcSI);
      final k4vx = -a4*vx4/v4;
      final k4vy = -a4*vy4/v4 - _g*shootingAngleCos;
      final k4vz = -a4*vz4/v4 + (crosswindMs - vz4)*a4/v4;
      final k4x = vx4; final k4y = vy4; final k4z = vz4;

      vx += (k1vx + 2*k2vx + 2*k3vx + k4vx) * dt / 6;
      vy += (k1vy + 2*k2vy + 2*k3vy + k4vy) * dt / 6;
      vz += (k1vz + 2*k2vz + 2*k3vz + k4vz) * dt / 6;
      x  += (k1x  + 2*k2x  + 2*k3x  + k4x)  * dt / 6;
      y  += (k1y  + 2*k2y  + 2*k3y  + k4y)  * dt / 6;
      z  += (k1z  + 2*k2z  + 2*k3z  + k4z)  * dt / 6;
      t  += dt;
      step++;

      // Detect when we cross targetRangeM and interpolate
      if (!reached && x >= targetRangeM) {
        // Linear interpolation fraction
        final frac = (targetRangeM - xPrev) / (x - xPrev);
        final yInterp = yPrev + frac * (y - yPrev);
        final zInterp = zPrev + frac * (z - zPrev);
        final vInterp = vPrev + frac * (v - vPrev);
        final tInterp = tPrev + frac * (t - tPrev);

        // LOS height at this range (in metres) – sight is above bore
        final losHeight = sightHeightM + targetRangeM * losSlope;
        dropAtTarget = yInterp - losHeight;
        zAtTarget = zInterp;
        vAtTarget = vInterp;
        tAtTarget = tInterp;
        reached = true;
        break;
      }
    }

    if (!reached) {
      // Bullet did not reach target
      final losHeight = sightHeightM + targetRangeM * losSlope;
      dropAtTarget = y - losHeight;
      zAtTarget = z;
      vAtTarget = math.sqrt(vx * vx + vy * vy + vz * vz);
      tAtTarget = t;
    }

    // Gyroscopic spin drift (Litz, simplified)
    // Stability factor sg ≈ (twist / (bullet length)) * constant; we
    // approximate with a formula that depends on twist and bullet diameter.
    final sg = _stabilityFactor(
      muzzleVelocityMs,
      twistInchesPerTurn,
      bulletDiameterInches,
    );
    // Drift in metres for right-hand twist: positive = right
    final spinDriftM = 0.0254 * 1.25 * (sg + 1.2) * math.pow(tAtTarget, 1.83);

    return _TrajectoryResult(
      dropM: dropAtTarget,
      lateralDriftM: zAtTarget + spinDriftM,
      spinDriftM: spinDriftM,
      velocityMs: vAtTarget,
      timeOfFlightS: tAtTarget,
    );
  }

  // ── Solution builder ──────────────────────────────────────────────────────────

  BallisticSolution _buildSolution(
    BallisticInput input,
    _TrajectoryResult result,
  ) {
    final profile = input.rifleProfile;
    final dropInches = result.dropM * 39.3701;
    final windDriftInches = result.lateralDriftM * 39.3701;
    final spinDriftInches = result.spinDriftM * 39.3701;
    final rangeYards = input.rangeYards;

    // ── MOA / MIL conversions ────────────────────────────────────────────────
    // 1 MOA = 1.047197551 inches at 100 yards → at rangeYards:
    //   1 MOA = 1.047197551 * rangeYards / 100  inches
    // 1 mil = 3.599 MOA = (rangeYards * 0.1) / 0.9144 * (1000/1000) inches
    //       = rangeYards * 3.6 / 100 inches per mil (NATO mil approximation)
    const double moaInchesAt100 = 1.04719755; // exact
    final inchesPerMoaAtRange = moaInchesAt100 * rangeYards / 100.0;
    final inchesPerMilAtRange = rangeYards * 3.59817 / 100.0; // 1 mil exactly

    // Elevation: drop is negative (below LOS), we need to correct UP
    final elevMoa =
        rangeYards > 0 ? (-dropInches / inchesPerMoaAtRange) : 0.0;
    final elevMil = elevMoa / 3.43775; // 1 mil = 3.43775 MOA (NATO)
    final elevClicks = (elevMoa / profile.clickValueMoa).round();

    // Wind: positive drift = bullet went right, correct LEFT
    final windMoa =
        rangeYards > 0 ? (-windDriftInches / inchesPerMoaAtRange) : 0.0;
    final windMil = windMoa / 3.43775;
    final windClicks = (windMoa / profile.clickValueMoa).round();

    // ── Terminal energy ──────────────────────────────────────────────────────
    final vFps = result.velocityMs / 0.3048;
    final massGrains = profile.bulletProfile.bulletWeightGrains;
    final energyFtLbs = massGrains * vFps * vFps / 450437.0;

    // ── Assumption string ────────────────────────────────────────────────────
    final bc = profile.bulletProfile.ballisticCoefficientG7 != null
        ? 'G7 BC=${profile.bulletProfile.ballisticCoefficientG7}'
        : 'G1 BC=${profile.bulletProfile.ballisticCoefficientG1}';
    final assumptions =
        '${input.temperatureFahrenheit.toStringAsFixed(0)}°F, '
        '${input.pressureInHg.toStringAsFixed(2)}" Hg, '
        '${input.humidityPercent.toStringAsFixed(0)}% RH, '
        '${input.altitudeFeet.toStringAsFixed(0)} ft elev, '
        '$bc';

    return BallisticSolution(
      rangeYards: rangeYards,
      dropInches: dropInches,
      elevationCorrectionMoa: elevMoa,
      elevationCorrectionMil: elevMil,
      elevationClicksUp: elevClicks,
      windDriftInches: windDriftInches - spinDriftInches,
      windCorrectionMoa: windMoa,
      windCorrectionMil: windMil,
      windClicksLeft: windClicks,
      timeOfFlightSeconds: result.timeOfFlightS,
      remainingVelocityFps: vFps,
      remainingEnergyFtLbs: energyFtLbs,
      spinDriftInches: spinDriftInches,
      assumptions: assumptions,
    );
  }

  // ── Drag interpolation ────────────────────────────────────────────────────────

  double _interpolateDrag(List<_DragPoint> table, double mach) {
    if (mach <= table.first.mach) return table.first.cd;
    if (mach >= table.last.mach) return table.last.cd;

    // Binary search for the surrounding bracket
    int lo = 0;
    int hi = table.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) ~/ 2;
      if (table[mid].mach <= mach) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final t =
        (mach - table[lo].mach) / (table[hi].mach - table[lo].mach);
    return table[lo].cd + t * (table[hi].cd - table[lo].cd);
  }

  // ── Atmosphere ────────────────────────────────────────────────────────────────

  /// Air density in kg/m³ using the ideal gas law with humidity correction.
  double _airDensity(double tempF, double pressureInHg, double humidity) {
    final tempC = (tempF - 32) * 5 / 9;
    final tempK = tempC + 273.15;
    final pressurePa = pressureInHg * 3386.389;

    // Saturation vapour pressure (Magnus formula, Pa)
    final eSatPa =
        610.78 * math.pow(10, 7.5 * tempC / (237.3 + tempC));
    final eActPa = (humidity / 100.0) * eSatPa;

    // Density of moist air (Rd = 287.058, Rv = 461.495 J/kg/K)
    const Rd = 287.058;
    const Rv = 461.495;
    final rho = (pressurePa - eActPa) / (Rd * tempK) +
        eActPa / (Rv * tempK);
    return rho;
  }

  /// Speed of sound in m/s at given temperature (°F).
  double _speedOfSound(double tempF) {
    final tempC = (tempF - 32) * 5 / 9;
    return 331.3 * math.sqrt(1 + tempC / 273.15);
  }

  // ── Gyroscopic stability ──────────────────────────────────────────────────────

  /// Simplified Miller stability formula.
  /// Returns the gyroscopic stability factor Sg.
  double _stabilityFactor(
    double muzzleVelocityMs,
    double twistInchesPerTurn,
    double bulletDiameterInches,
  ) {
    // Convert to fps / inches for Miller formula
    final muzzleFps = muzzleVelocityMs / 0.3048;
    // Miller: Sg = 30 * m / (t² * d³ * l * (1 + l²))
    // Simplified approximation (assume l=4 calibers, m from diameter):
    final t = twistInchesPerTurn;
    final d = bulletDiameterInches;
    final sg = (muzzleFps / 2800.0) * (30.0 / (t * t * d));
    return sg.clamp(1.0, 3.0);
  }

  // ── Unit helpers ──────────────────────────────────────────────────────────────

  static double _fpsToMs(double fps) => fps * 0.3048;
  static double _yardsToM(double yards) => yards * 0.9144;
}

/// Internal trajectory result.
class _TrajectoryResult {
  const _TrajectoryResult({
    required this.dropM,
    required this.lateralDriftM,
    required this.spinDriftM,
    required this.velocityMs,
    required this.timeOfFlightS,
  });

  /// Vertical position relative to line-of-sight (m). Negative = below LOS.
  final double dropM;

  /// Total lateral drift including wind and spin drift (m).
  final double lateralDriftM;

  /// Spin drift component only (m).
  final double spinDriftM;

  final double velocityMs;
  final double timeOfFlightS;
}
