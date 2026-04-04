import 'weapon_profile.dart';

// ── Enums ──────────────────────────────────────────────────────────

enum Gauge {
  g12('12 ga'),
  g20('20 ga'),
  g28('28 ga'),
  g410('.410 bore');

  final String label;
  const Gauge(this.label);
}

enum ChokeType {
  cylinder('Cylinder', 0.000),
  skeet('Skeet', 0.005),
  improvedCylinder('Improved Cylinder', 0.010),
  modified('Modified', 0.020),
  improvedModified('Improved Modified', 0.025),
  full('Full', 0.030),
  extraFull('Extra Full', 0.040);

  final String label;
  final double constrictionInches;
  const ChokeType(this.label, this.constrictionInches);
}

enum ShotCategory {
  lead('Lead', 11.34),
  steel('Steel', 7.86),
  bismuth('Bismuth', 9.60),
  tungsten('Tungsten', 18.00),
  tss('TSS', 18.10);

  final String label;
  final double densityGcc; // g/cm³
  const ShotCategory(this.label, this.densityGcc);
}

enum ShotSize {
  // Birdshot
  s9('#9', 0.080),
  s8('#8', 0.090),
  s7h('#7½', 0.095),
  s7('#7', 0.100),
  s6('#6', 0.110),
  s5('#5', 0.120),
  s4('#4', 0.130),
  s3('#3', 0.140),
  s2('#2', 0.150),
  s1('#1', 0.160),
  bb('BB', 0.180),
  bbb('BBB', 0.190),
  t('T', 0.200),
  // Buckshot
  buck4('#4 Buck', 0.240),
  buck3('#3 Buck', 0.250),
  buck1('#1 Buck', 0.300),
  buck0('0 Buck', 0.320),
  buck00('00 Buck', 0.330),
  buck000('000 Buck', 0.360);

  final String label;
  final double diameterInches;
  const ShotSize(this.label, this.diameterInches);
}

enum WadType {
  plastic('Plastic', 0.90),
  fiber('Fiber', 1.15);

  final String label;
  final double spreadModifier;
  const WadType(this.label, this.spreadModifier);
}

enum AmmoSpreadClass {
  tight('Tight', 0.85),
  standard('Standard', 1.00),
  wide('Wide', 1.20);

  final String label;
  final double sigmaMultiplier;
  const AmmoSpreadClass(this.label, this.sigmaMultiplier);
}

/// The animal being hunted. Controls effective-range calculation via per-pellet
/// energy threshold and total energy that must reach the vital zone.
enum GameTarget {
  dove('Dove / Quail', 3.5, 2.5, 3.0),
  duck('Duck / Teal', 3.0, 4.0, 5.0),
  pheasant('Pheasant', 3.0, 4.0, 5.0),
  goose('Goose', 3.0, 5.0, 8.0),
  turkey('Turkey', 1.0, 3.0, 15.0),
  rabbit('Rabbit / Squirrel', 3.5, 3.0, 3.0),
  coyote('Coyote', 35.0, 7.0, 60.0),
  deer('Deer', 35.0, 10.0, 300.0),
  hog('Hog', 40.0, 8.0, 350.0);

  final String label;

  /// Minimum per-pellet kinetic energy (ft-lbs) for adequate penetration.
  final double minPelletEnergyFtLbs;

  /// Diameter of the vital zone (inches).
  final double vitalDiameterInches;

  /// Minimum total kinetic energy (ft-lbs) that must reach the vital zone.
  final double minVitalEnergyFtLbs;

  const GameTarget(
    this.label,
    this.minPelletEnergyFtLbs,
    this.vitalDiameterInches,
    this.minVitalEnergyFtLbs,
  );
}

// ── Model ──────────────────────────────────────────────────────────

class ShotgunSetup extends WeaponProfile {
  // Gun
  final Gauge gauge;
  final double barrelLengthInches;

  // Choke
  final ChokeType chokeType;

  // Load
  final String loadName;
  final ShotCategory shotCategory;
  final ShotSize shotSize;
  final int pelletCount;
  final double muzzleVelocityFps;
  final WadType wadType;
  final AmmoSpreadClass ammoSpreadClass;

  // Hunting target
  final GameTarget gameTarget;

  /// Approximate pellet count for a standard payload weight given gauge and
  /// shot size. Derived from payload weight (oz) / single-pellet weight.
  ///
  /// Payload weights: 12 ga → 1.125 oz, 20 ga → 0.875 oz,
  /// 28 ga → 0.75 oz, .410 → 0.5 oz.
  static int estimatePelletCount(Gauge gauge, ShotSize size) {
    // Standard payload weight in ounces (lead, 2¾" shell).
    final payloadOz = switch (gauge) {
      Gauge.g12 => 1.125,
      Gauge.g20 => 0.875,
      Gauge.g28 => 0.75,
      Gauge.g410 => 0.5,
    };
    // Single lead pellet weight in ounces.
    // Volume = (4/3)π(d/2)³ in inches; density of lead ≈ 6.544 oz/in³.
    final r = size.diameterInches / 2.0;
    final pelletOz = (4.0 / 3.0) * 3.141592653589793 * r * r * r * 6.544;
    if (pelletOz <= 0) return 1;
    return (payloadOz / pelletOz).round().clamp(1, 9999);
  }

  ShotgunSetup({
    super.id,
    required super.name,
    required this.gauge,
    required this.barrelLengthInches,
    required this.chokeType,
    required this.loadName,
    required this.shotCategory,
    required this.shotSize,
    required this.pelletCount,
    required this.muzzleVelocityFps,
    required this.wadType,
    required this.ammoSpreadClass,
    this.gameTarget = GameTarget.coyote,
  });

  /// Sensible default: 12 ga, Modified choke, #6 lead
  factory ShotgunSetup.default12gaMod() => ShotgunSetup(
    name: '12 ga Modified — #6 Lead',
    gauge: Gauge.g12,
    barrelLengthInches: 28,
    chokeType: ChokeType.modified,
    loadName: '#6 Lead 1¼ oz',
    shotCategory: ShotCategory.lead,
    shotSize: ShotSize.s6,
    pelletCount: 281,
    muzzleVelocityFps: 1330,
    wadType: WadType.plastic,
    ammoSpreadClass: AmmoSpreadClass.standard,
  );

  /// 12 ga, Cylinder bore, 00 Buckshot — 9 pellets
  factory ShotgunSetup.default12ga00Buck() => ShotgunSetup(
    name: '12 ga Cylinder — 00 Buck',
    gauge: Gauge.g12,
    barrelLengthInches: 18,
    chokeType: ChokeType.cylinder,
    loadName: '00 Buck 2¾"',
    shotCategory: ShotCategory.lead,
    shotSize: ShotSize.buck00,
    pelletCount: 9,
    muzzleVelocityFps: 1325,
    wadType: WadType.plastic,
    ammoSpreadClass: AmmoSpreadClass.standard,
  );

  @override
  WeaponType get weaponType => WeaponType.shotgun;

  @override
  Map<String, dynamic> toJson() => {
    'weaponType': weaponType.name,
    'id': id,
    'name': name,
    'gauge': gauge.name,
    'barrelLengthInches': barrelLengthInches,
    'chokeType': chokeType.name,
    'loadName': loadName,
    'shotCategory': shotCategory.name,
    'shotSize': shotSize.name,
    'pelletCount': pelletCount,
    'muzzleVelocityFps': muzzleVelocityFps,
    'wadType': wadType.name,
    'ammoSpreadClass': ammoSpreadClass.name,
    'gameTarget': gameTarget.name,
  };

  factory ShotgunSetup.fromJson(Map<String, dynamic> json) => ShotgunSetup(
    id: json['id'] as String?,
    name: json['name'] as String,
    gauge: Gauge.values.byName(json['gauge'] as String),
    barrelLengthInches: (json['barrelLengthInches'] as num).toDouble(),
    chokeType: ChokeType.values.byName(json['chokeType'] as String),
    loadName: json['loadName'] as String,
    shotCategory: ShotCategory.values.byName(json['shotCategory'] as String),
    shotSize: ShotSize.values.byName(json['shotSize'] as String),
    pelletCount: (json['pelletCount'] as num).toInt(),
    muzzleVelocityFps: (json['muzzleVelocityFps'] as num).toDouble(),
    wadType: WadType.values.byName(json['wadType'] as String),
    ammoSpreadClass: AmmoSpreadClass.values.byName(
      json['ammoSpreadClass'] as String,
    ),
    gameTarget: json.containsKey('gameTarget')
        ? GameTarget.values.byName(json['gameTarget'] as String)
        : GameTarget.duck,
  );

  ShotgunSetup copyWith({
    String? id,
    String? name,
    Gauge? gauge,
    double? barrelLengthInches,
    ChokeType? chokeType,
    String? loadName,
    ShotCategory? shotCategory,
    ShotSize? shotSize,
    int? pelletCount,
    double? muzzleVelocityFps,
    WadType? wadType,
    AmmoSpreadClass? ammoSpreadClass,
    GameTarget? gameTarget,
  }) => ShotgunSetup(
    id: id ?? this.id,
    name: name ?? this.name,
    gauge: gauge ?? this.gauge,
    barrelLengthInches: barrelLengthInches ?? this.barrelLengthInches,
    chokeType: chokeType ?? this.chokeType,
    loadName: loadName ?? this.loadName,
    shotCategory: shotCategory ?? this.shotCategory,
    shotSize: shotSize ?? this.shotSize,
    pelletCount: pelletCount ?? this.pelletCount,
    muzzleVelocityFps: muzzleVelocityFps ?? this.muzzleVelocityFps,
    wadType: wadType ?? this.wadType,
    ammoSpreadClass: ammoSpreadClass ?? this.ammoSpreadClass,
    gameTarget: gameTarget ?? this.gameTarget,
  );

  @override
  List<Object?> get props => [
    weaponType,
    id,
    name,
    gauge,
    barrelLengthInches,
    chokeType,
    loadName,
    shotCategory,
    shotSize,
    pelletCount,
    muzzleVelocityFps,
    wadType,
    ammoSpreadClass,
    gameTarget,
  ];
}
