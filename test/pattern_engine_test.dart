import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:atlix/ballistics/pattern_engine.dart';
import 'package:atlix/models/calibration_record.dart';
import 'package:atlix/models/shotgun_setup.dart';

// ── Helpers ────────────────────────────────────────────────────────

/// Derive Rayleigh σ at 40 yards from a pattern efficiency value.
double _sigma40(double pe) => 15.0 / sqrt(-2.0 * log(1.0 - pe));

/// Rayleigh CDF: fraction of pellets within [radius] given [sigma].
double _rayleighCDF(double radius, double sigma) {
  if (sigma <= 0) return 1.0;
  return 1.0 - exp(-radius * radius / (2.0 * sigma * sigma));
}

// ── Published pattern efficiency values ────────────────────────────

const _pe = <ChokeType, double>{
  ChokeType.cylinder: 0.40,
  ChokeType.skeet: 0.45,
  ChokeType.improvedCylinder: 0.50,
  ChokeType.modified: 0.60,
  ChokeType.improvedModified: 0.65,
  ChokeType.full: 0.70,
  ChokeType.extraFull: 0.73,
};

// ── Test setups ────────────────────────────────────────────────────

/// Default 12 ga Modified choke, #6 Lead, plastic wad, standard ammo.
final _default12ga = ShotgunSetup(
  name: 'Test 12ga Mod',
  gauge: Gauge.g12,
  barrelLengthInches: 28,
  chokeType: ChokeType.modified,
  loadName: '#6 Lead',
  shotCategory: ShotCategory.lead,
  shotSize: ShotSize.s6,
  pelletCount: 281,
  muzzleVelocityFps: 1330,
  wadType: WadType.plastic,
  ammoSpreadClass: AmmoSpreadClass.standard,
);

/// Cylinder bore → widest pattern.
final _cylinder = ShotgunSetup(
  name: 'Cylinder',
  gauge: Gauge.g12,
  barrelLengthInches: 26,
  chokeType: ChokeType.cylinder,
  loadName: 'Buck',
  shotCategory: ShotCategory.lead,
  shotSize: ShotSize.s4,
  pelletCount: 135,
  muzzleVelocityFps: 1325,
  wadType: WadType.plastic,
  ammoSpreadClass: AmmoSpreadClass.standard,
);

/// Full choke → tightest common pattern.
final _full = ShotgunSetup(
  name: 'Full',
  gauge: Gauge.g12,
  barrelLengthInches: 30,
  chokeType: ChokeType.full,
  loadName: 'Target',
  shotCategory: ShotCategory.lead,
  shotSize: ShotSize.s8,
  pelletCount: 410,
  muzzleVelocityFps: 1200,
  wadType: WadType.plastic,
  ammoSpreadClass: AmmoSpreadClass.standard,
);

void main() {
  final engine = PatternEngine();

  // ── PE verification (the anchor test) ────────────────────────────

  group('Pattern efficiency verification at 40 yards', () {
    for (final choke in ChokeType.values) {
      test('${choke.label}: pellets in 30" ≈ published PE', () {
        final setup = ShotgunSetup(
          name: choke.label,
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: choke,
          loadName: 'Test',
          shotCategory: ShotCategory.lead,
          shotSize: ShotSize.s6,
          pelletCount: 1000, // large count for better resolution
          muzzleVelocityFps: 1330,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.standard,
        );
        final r = engine.predict(setup: setup, distanceYards: 40);
        // pelletsIn30Circle / total should match PE within ±1%.
        // Use Rayleigh CDF at 15" radius directly.
        final pe = _pe[choke]!;
        final sigma = _sigma40(pe); // at 40 yd, modifiers are all 1.0
        final expectedFraction = _rayleighCDF(15.0, sigma);
        expect(expectedFraction, closeTo(pe, 0.01));

        // Also verify the engine's pellet count matches
        // Use the returned sigma to compute it from R50.
        final resultSigma = r.r50Inches / sqrt(log(4));
        final actualFraction = _rayleighCDF(15.0, resultSigma);
        expect(actualFraction, closeTo(pe, 0.01));
      });
    }
  });

  // ── Spread diameter (99% containment) ────────────────────────────

  group('Spread diameter', () {
    test('12ga Modified at 40yds: spread = 2σ√(−2ln0.01)', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 40);
      final sigma40 = _sigma40(0.60); // Modified PE
      final expected = 2.0 * sigma40 * sqrt(-2.0 * log(0.01));
      expect(r.spreadDiameterInches, closeTo(expected, 0.01));
    });

    test('spread scales linearly with distance', () {
      final r20 = engine.predict(setup: _default12ga, distanceYards: 20);
      final r40 = engine.predict(setup: _default12ga, distanceYards: 40);
      expect(
        r40.spreadDiameterInches,
        closeTo(r20.spreadDiameterInches * 2, 0.01),
      );
    });

    test('tighter choke → smaller spread at same distance', () {
      final rCyl = engine.predict(setup: _cylinder, distanceYards: 30);
      final rMod = engine.predict(setup: _default12ga, distanceYards: 30);
      final rFull = engine.predict(setup: _full, distanceYards: 30);
      expect(rCyl.spreadDiameterInches, greaterThan(rMod.spreadDiameterInches));
      expect(
        rMod.spreadDiameterInches,
        greaterThan(rFull.spreadDiameterInches),
      );
    });
  });

  // ── Wad and ammo modifiers ───────────────────────────────────────

  group('Wad & ammo modifiers', () {
    test('fiber wad increases spread vs plastic', () {
      final plastic = engine.predict(setup: _default12ga, distanceYards: 30);
      final fiber = engine.predict(
        setup: ShotgunSetup(
          name: 'Fiber',
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: ChokeType.modified,
          loadName: '#6 Lead',
          shotCategory: ShotCategory.lead,
          shotSize: ShotSize.s6,
          pelletCount: 281,
          muzzleVelocityFps: 1330,
          wadType: WadType.fiber,
          ammoSpreadClass: AmmoSpreadClass.standard,
        ),
        distanceYards: 30,
      );
      expect(
        fiber.spreadDiameterInches,
        greaterThan(plastic.spreadDiameterInches),
      );
      // Exact ratio: fiber(1.10) / plastic(1.00) = 1.10
      expect(
        fiber.spreadDiameterInches / plastic.spreadDiameterInches,
        closeTo(1.10 / 1.00, 0.001),
      );
    });

    test('wide ammo class increases spread vs standard', () {
      final standard = engine.predict(setup: _default12ga, distanceYards: 30);
      final wide = engine.predict(
        setup: ShotgunSetup(
          name: 'Wide',
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: ChokeType.modified,
          loadName: '#6 Lead',
          shotCategory: ShotCategory.lead,
          shotSize: ShotSize.s6,
          pelletCount: 281,
          muzzleVelocityFps: 1330,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.wide,
        ),
        distanceYards: 30,
      );
      expect(
        wide.spreadDiameterInches,
        greaterThan(standard.spreadDiameterInches),
      );
      expect(
        wide.spreadDiameterInches / standard.spreadDiameterInches,
        closeTo(1.20 / 1.00, 0.001),
      );
    });
  });

  // ── R50 / R75 / Rayleigh consistency ─────────────────────────────

  group('R50 / R75 Rayleigh distribution', () {
    test('R75 > R50', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 30);
      expect(r.r75Inches, greaterThan(r.r50Inches));
    });

    test('R75 / R50 = √2 (Rayleigh invariant)', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 30);
      expect(r.r75Inches / r.r50Inches, closeTo(sqrt(2), 0.001));
    });

    test('R75/R50 = √2 holds for all chokes', () {
      for (final choke in ChokeType.values) {
        final setup = ShotgunSetup(
          name: choke.label,
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: choke,
          loadName: 'Test',
          shotCategory: ShotCategory.lead,
          shotSize: ShotSize.s6,
          pelletCount: 281,
          muzzleVelocityFps: 1330,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.standard,
        );
        final r = engine.predict(setup: setup, distanceYards: 35);
        expect(
          r.r75Inches / r.r50Inches,
          closeTo(sqrt(2), 0.001),
          reason: '${choke.label} R75/R50 should be √2',
        );
      }
    });
  });

  // ── Pellet counts in circles ─────────────────────────────────────

  group('Pellet counts in circles', () {
    test('20" circle captures more pellets than 10"', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 30);
      expect(r.pelletsIn20Circle, greaterThan(r.pelletsIn10Circle));
    });

    test('both counts ≤ total pellets', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 30);
      expect(r.pelletsIn10Circle, lessThanOrEqualTo(r.totalPellets));
      expect(r.pelletsIn20Circle, lessThanOrEqualTo(r.totalPellets));
    });

    test('very close distance → almost all pellets in 20"', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 5);
      // At 5 yds sigma is tiny, so a 20" circle should capture nearly all.
      expect(r.pelletsIn20Circle, equals(r.totalPellets));
    });

    test('Rayleigh CDF matches pellet count at 10" circle', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 30);
      final sigma = r.r50Inches / sqrt(log(4));
      const radius = 5.0; // 10" diameter
      final p = _rayleighCDF(radius, sigma);
      expect(r.pelletsIn10Circle, equals((281 * p).round()));
    });

    test('Modified 25yd: ~90% in 30" circle (sanity)', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 25);
      final sigma = r.r50Inches / sqrt(log(4));
      final fractionIn30 = _rayleighCDF(15.0, sigma);
      // At 25 yd with Modified choke, expect ~86-95% in 30"
      expect(fractionIn30, greaterThan(0.80));
      expect(fractionIn30, lessThan(1.00));
    });
  });

  // ── Gauge and hardness modifiers ─────────────────────────────────

  group('Gauge and hardness modifiers', () {
    test('20ga spreads wider than 12ga (same named choke)', () {
      final ga12 = engine.predict(setup: _default12ga, distanceYards: 30);
      final ga20 = engine.predict(
        setup: ShotgunSetup(
          name: '20ga',
          gauge: Gauge.g20,
          barrelLengthInches: 26,
          chokeType: ChokeType.modified,
          loadName: '#6 Lead',
          shotCategory: ShotCategory.lead,
          shotSize: ShotSize.s6,
          pelletCount: 218,
          muzzleVelocityFps: 1300,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.standard,
        ),
        distanceYards: 30,
      );
      expect(ga20.spreadDiameterInches, greaterThan(ga12.spreadDiameterInches));
    });

    test('steel patterns tighter than lead (same choke)', () {
      final lead = engine.predict(setup: _default12ga, distanceYards: 30);
      final steel = engine.predict(
        setup: ShotgunSetup(
          name: 'Steel',
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: ChokeType.modified,
          loadName: '#6 Steel',
          shotCategory: ShotCategory.steel,
          shotSize: ShotSize.s6,
          pelletCount: 281,
          muzzleVelocityFps: 1330,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.standard,
        ),
        distanceYards: 30,
      );
      expect(steel.spreadDiameterInches, lessThan(lead.spreadDiameterInches));
    });

    test('steel + Modified ≈ lead + Full ("two chokes tighter")', () {
      // Steel Modified should be roughly similar to Lead Full
      final steelMod = engine.predict(
        setup: ShotgunSetup(
          name: 'Steel Mod',
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: ChokeType.modified,
          loadName: 'Steel',
          shotCategory: ShotCategory.steel,
          shotSize: ShotSize.s6,
          pelletCount: 281,
          muzzleVelocityFps: 1330,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.standard,
        ),
        distanceYards: 40,
      );
      final leadFull = engine.predict(
        setup: ShotgunSetup(
          name: 'Lead Full',
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: ChokeType.full,
          loadName: 'Lead',
          shotCategory: ShotCategory.lead,
          shotSize: ShotSize.s6,
          pelletCount: 281,
          muzzleVelocityFps: 1330,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.standard,
        ),
        distanceYards: 40,
      );
      // Steel Modified sigma: σ₄₀(0.60) × 0.85 = 11.08 × 0.85 ≈ 9.42
      // Lead Full sigma: σ₄₀(0.70) × 1.00 = 9.66
      // Within ~3% — close enough for the "two chokes tighter" rule
      final steelSigma = steelMod.r50Inches / sqrt(log(4));
      final leadSigma = leadFull.r50Inches / sqrt(log(4));
      expect(steelSigma / leadSigma, closeTo(1.0, 0.05));
    });
  });

  // ── Uncalibrated defaults ────────────────────────────────────────

  group('Uncalibrated defaults', () {
    test('isCalibrated = false when no calibration record', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 20);
      expect(r.isCalibrated, isFalse);
    });

    test('POI offset is zero without calibration', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 20);
      expect(r.poiOffsetXInches, equals(0.0));
      expect(r.poiOffsetYInches, equals(0.0));
    });

    test('distanceYards is echoed in result', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 35);
      expect(r.distanceYards, equals(35));
    });

    test('totalPellets matches setup', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 20);
      expect(r.totalPellets, equals(281));
    });

    test('patternEfficiency matches choke PE', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 20);
      expect(r.patternEfficiency, equals(0.60));
    });
  });

  // ── Calibration record ───────────────────────────────────────────

  group('Calibration multipliers', () {
    const cal = CalibrationRecord(
      setupId: 'Test 12ga Mod',
      diameterMultiplier: 1.2,
      sigmaMultiplier: 1.1,
      poiOffsetXInches: 0.5,
      poiOffsetYInches: -0.3,
      sampleCount: 3,
      aggregateConfidence: 0.85,
    );

    test('isCalibrated = true with calibration', () {
      final r = engine.predict(
        setup: _default12ga,
        distanceYards: 20,
        calibration: cal,
      );
      expect(r.isCalibrated, isTrue);
    });

    test('calibration scales sigma (and thus R50)', () {
      final uncal = engine.predict(setup: _default12ga, distanceYards: 20);
      final caled = engine.predict(
        setup: _default12ga,
        distanceYards: 20,
        calibration: cal,
      );
      // In the PE model, σ_final = σ × calDiamMod × calSigMod
      // R50 = σ_final × √(ln4), so R50_cal / R50_uncal = 1.2 × 1.1
      expect(caled.r50Inches / uncal.r50Inches, closeTo(1.2 * 1.1, 0.001));
    });

    test('calibration scales spread diameter by same factor', () {
      final uncal = engine.predict(setup: _default12ga, distanceYards: 20);
      final caled = engine.predict(
        setup: _default12ga,
        distanceYards: 20,
        calibration: cal,
      );
      // spreadDiameter = 2σ√(−2ln0.01), so same ratio
      expect(
        caled.spreadDiameterInches / uncal.spreadDiameterInches,
        closeTo(1.2 * 1.1, 0.001),
      );
    });

    test('POI offset is passed through from calibration', () {
      final r = engine.predict(
        setup: _default12ga,
        distanceYards: 20,
        calibration: cal,
      );
      expect(r.poiOffsetXInches, equals(0.5));
      expect(r.poiOffsetYInches, equals(-0.3));
    });

    test('identity calibration (1.0, 1.0) matches uncalibrated exactly', () {
      const identity = CalibrationRecord(
        setupId: 'Test 12ga Mod',
        diameterMultiplier: 1.0,
        sigmaMultiplier: 1.0,
        poiOffsetXInches: 0.0,
        poiOffsetYInches: 0.0,
        sampleCount: 1,
        aggregateConfidence: 0.5,
      );
      final uncal = engine.predict(setup: _default12ga, distanceYards: 25);
      final caled = engine.predict(
        setup: _default12ga,
        distanceYards: 25,
        calibration: identity,
      );
      expect(caled.spreadDiameterInches, equals(uncal.spreadDiameterInches));
      expect(caled.r50Inches, equals(uncal.r50Inches));
      expect(caled.r75Inches, equals(uncal.r75Inches));
      expect(caled.pelletsIn10Circle, equals(uncal.pelletsIn10Circle));
      expect(caled.pelletsIn20Circle, equals(uncal.pelletsIn20Circle));
    });
  });

  // ── All choke types covered ──────────────────────────────────────

  group('All choke types produce valid results', () {
    for (final choke in ChokeType.values) {
      test('${choke.label} at 25yds', () {
        final setup = ShotgunSetup(
          name: choke.label,
          gauge: Gauge.g12,
          barrelLengthInches: 28,
          chokeType: choke,
          loadName: 'Test',
          shotCategory: ShotCategory.lead,
          shotSize: ShotSize.s6,
          pelletCount: 281,
          muzzleVelocityFps: 1330,
          wadType: WadType.plastic,
          ammoSpreadClass: AmmoSpreadClass.standard,
        );
        final r = engine.predict(setup: setup, distanceYards: 25);
        expect(r.spreadDiameterInches, isPositive);
        expect(r.r50Inches, isPositive);
        expect(r.r75Inches, isPositive);
        expect(r.pelletsIn10Circle, greaterThanOrEqualTo(0));
        expect(r.pelletsIn20Circle, greaterThanOrEqualTo(r.pelletsIn10Circle));
        expect(r.totalPellets, equals(281));
        expect(r.patternEfficiency, greaterThan(0));
        expect(r.patternEfficiency, lessThan(1));
      });
    }
  });

  // ── Edge cases ───────────────────────────────────────────────────

  group('Edge cases', () {
    test('zero distance → zero spread, all pellets in any circle', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 0);
      expect(r.spreadDiameterInches, equals(0.0));
      expect(r.pelletsIn10Circle, equals(r.totalPellets));
      expect(r.pelletsIn20Circle, equals(r.totalPellets));
    });

    test('very long distance (60yds) still produces valid results', () {
      final r = engine.predict(setup: _default12ga, distanceYards: 60);
      expect(r.spreadDiameterInches, isPositive);
      expect(r.pelletsIn20Circle, lessThanOrEqualTo(r.totalPellets));
    });
  });

  // ── ShotgunSetup serialization ───────────────────────────────────

  group('ShotgunSetup JSON round-trip', () {
    test('fromJson(toJson()) == original', () {
      final json = _default12ga.toJson();
      final restored = ShotgunSetup.fromJson(json);
      expect(restored, equals(_default12ga));
    });

    test('default factory matches expected values', () {
      final d = ShotgunSetup.default12gaMod();
      expect(d.gauge, equals(Gauge.g12));
      expect(d.chokeType, equals(ChokeType.modified));
      expect(d.pelletCount, equals(281));
      expect(d.wadType, equals(WadType.plastic));
      expect(d.ammoSpreadClass, equals(AmmoSpreadClass.standard));
    });
  });

  // ── CalibrationRecord serialization ──────────────────────────────

  group('CalibrationRecord JSON round-trip', () {
    test('round-trip without optional fields', () {
      const rec = CalibrationRecord(
        setupId: 'test',
        diameterMultiplier: 1.1,
        sigmaMultiplier: 0.95,
        poiOffsetXInches: 0.3,
        poiOffsetYInches: -0.2,
        sampleCount: 2,
        aggregateConfidence: 0.7,
      );
      final restored = CalibrationRecord.fromJson(rec.toJson());
      expect(restored, equals(rec));
    });

    test('round-trip with ellipse fields', () {
      const rec = CalibrationRecord(
        setupId: 'test',
        diameterMultiplier: 1.0,
        sigmaMultiplier: 1.0,
        poiOffsetXInches: 0.0,
        poiOffsetYInches: 0.0,
        sampleCount: 1,
        aggregateConfidence: 0.5,
        ellipseRatio: 1.3,
        ellipseAngleDeg: 45.0,
      );
      final restored = CalibrationRecord.fromJson(rec.toJson());
      expect(restored, equals(rec));
      expect(restored.ellipseRatio, equals(1.3));
      expect(restored.ellipseAngleDeg, equals(45.0));
    });
  });
}
