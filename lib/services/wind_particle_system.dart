import 'dart:math';

import 'wind_particle.dart';

/// Manages a pool of wind particles — spawning, updating, and recycling.
///
/// All positions are in screen-space pixels. The caller converts the wind
/// direction from geographic bearing to screen-space velocity by accounting
/// for the current map bearing.
class WindParticleSystem {
  final int maxParticles;
  final Random _rng = Random();
  final List<Particle> _particles = [];
  bool _seeded = false;

  WindParticleSystem({this.maxParticles = 600});

  List<Particle> get particles => _particles;

  /// Advance the simulation by [dt] seconds.
  ///
  /// [screenSize] — current overlay size in pixels.
  /// [windScreenAngleRad] — wind "towards" direction in screen-space radians
  ///   (0 = right, pi/2 = down), already adjusted for map bearing.
  /// [pxPerSec] — wind speed in screen pixels per second.
  void update(
    double dt,
    Size screenSize,
    double windScreenAngleRad,
    double pxPerSec,
  ) {
    final vx = cos(windScreenAngleRad) * pxPerSec;
    final vy = sin(windScreenAngleRad) * pxPerSec;

    // Update existing particles
    for (var i = _particles.length - 1; i >= 0; i--) {
      final p = _particles[i];
      p.prevX = p.x;
      p.prevY = p.y;
      p.x += vx * dt;
      p.y += vy * dt;
      p.age += dt;

      // Recycle if expired or off-screen (with margin)
      if (p.age >= p.maxAge || _isOffScreen(p, screenSize)) {
        _particles.removeAt(i);
      }
    }

    // Spawn new particles to fill the pool
    final deficit = maxParticles - _particles.length;
    final scatter = !_seeded;
    for (var i = 0; i < deficit; i++) {
      _particles.add(_spawn(screenSize, windScreenAngleRad, scatter: scatter));
    }
    _seeded = true;
  }

  /// Offset all particles by a screen-space delta (e.g. when the map pans).
  void offset(double dx, double dy) {
    for (final p in _particles) {
      p.x += dx;
      p.y += dy;
    }
  }

  void clear() {
    _particles.clear();
    _seeded = false;
  }

  // ── private ──────────────────────────────────────────────────────────

  bool _isOffScreen(Particle p, Size size) {
    const margin = 60.0;
    return p.x < -margin ||
        p.x > size.width + margin ||
        p.y < -margin ||
        p.y > size.height + margin;
  }

  /// Spawn a particle along the upwind edge of the screen so it flows inward.
  /// When [scatter] is true (initial fill), place it randomly across the screen.
  Particle _spawn(Size size, double windAngleRad, {bool scatter = false}) {
    if (scatter) {
      final x = _rng.nextDouble() * size.width;
      final y = _rng.nextDouble() * size.height;
      final maxAge = 3.0 + _rng.nextDouble() * 4.0;
      final age = _rng.nextDouble() * maxAge; // spread across full lifetime
      return Particle(x: x, y: y, age: age, maxAge: maxAge);
    }

    // Normalised wind direction components (unit vector — towards direction)
    final wx = cos(windAngleRad);
    final wy = sin(windAngleRad);

    double x, y;

    // Pick a random point on the upwind edges. The upwind edge is opposite
    // to the wind-towards direction.
    if (_rng.nextBool()) {
      // Spawn on the vertical edge opposite to horizontal wind component
      x = wx > 0
          ? -_rng.nextDouble() * 40
          : size.width + _rng.nextDouble() * 40;
      y = _rng.nextDouble() * size.height;
    } else {
      // Spawn on the horizontal edge opposite to vertical wind component
      x = _rng.nextDouble() * size.width;
      y = wy > 0
          ? -_rng.nextDouble() * 40
          : size.height + _rng.nextDouble() * 40;
    }

    // Randomise age so particles don't all appear at once on first frame
    final maxAge = 3.0 + _rng.nextDouble() * 4.0; // 3–7 seconds
    final age =
        _rng.nextDouble() * maxAge * 0.3; // start up to 30% through life

    return Particle(x: x, y: y, age: age, maxAge: maxAge);
  }
}

/// Size stub — imported from dart:ui by the overlay, but the particle system
/// only needs width/height, so we use a minimal typedef here to avoid a
/// Flutter import in a pure-Dart file.
class Size {
  final double width;
  final double height;
  const Size(this.width, this.height);
}
