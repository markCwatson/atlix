import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/wind_data.dart';
import '../services/wind_particle.dart';
import '../services/wind_particle_system.dart' as engine;

/// Animated wind-particle overlay rendered on top of the Mapbox map.
///
/// Particles stream across the screen following the wind direction from
/// [windField]. The overlay accounts for the current [mapBearingDeg] so
/// particles stay geographically consistent when the map rotates, and
/// [zoom] so particle speed feels natural at any zoom level.
///
/// Wrap in [IgnorePointer] (handled internally) so map gestures pass through.
class WindOverlay extends StatefulWidget {
  final WindField windField;

  /// Current map bearing in degrees (0 = north-up).
  final double mapBearingDeg;

  /// Current map zoom level (0–22).
  final double zoom;

  const WindOverlay({
    super.key,
    required this.windField,
    this.mapBearingDeg = 0,
    this.zoom = 14,
  });

  @override
  State<WindOverlay> createState() => _WindOverlayState();
}

class _WindOverlayState extends State<WindOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final engine.WindParticleSystem _system;
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    _system = engine.WindParticleSystem(maxParticles: 600);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == Duration.zero) {
      _lastTick = elapsed;
      return;
    }
    final dt = (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;

    final size = context.size;
    if (size == null) return;

    // Get wind vector at map centre (for uniform field, location is irrelevant)
    final wind = widget.windField.getWind(0, 0);

    // Convert meteorological bearing → screen-space angle.
    // Meteorological bearing: 0 = from north, clockwise.
    // "Towards" direction = bearing + 180.
    // Screen angle: 0 = right, pi/2 = down.
    // Screen-y is inverted (down is positive), so from-north (towards-south)
    // means screen angle = pi/2 when map is north-up.
    final towardsGeoRad = wind.towardsDeg * pi / 180;
    final mapBearingRad = widget.mapBearingDeg * pi / 180;
    // In screen space, geographic north points UP (negative y).
    // Rotate by map bearing: when map bearing > 0, the map is rotated CW,
    // so geographic features appear rotated CCW on screen.
    final screenAngle = towardsGeoRad - mapBearingRad - pi / 2;

    // Speed in px/sec — scale by zoom so particles feel natural.
    // At zoom 14, 1 km/h ≈ 4 px/sec. Double for each zoom level up.
    final baseSpeed = wind.speedKmh * 4.0;
    final zoomFactor = pow(2, widget.zoom - 14).toDouble();
    final pxPerSec = baseSpeed * zoomFactor;

    _system.update(
      dt,
      engine.Size(size.width, size.height),
      screenAngle,
      pxPerSec,
    );

    // Trigger repaint
    (context as Element).markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _WindPainter(particles: _system.particles),
        ),
      ),
    );
  }
}

/// Draws each particle as a short semi-transparent white trail line.
class _WindPainter extends CustomPainter {
  final List<Particle> particles;

  _WindPainter({required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    final trailPaint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint();

    for (final p in particles) {
      final alpha = (p.opacity * 0.65).clamp(0.0, 1.0);
      if (alpha < 0.01) continue;

      // Extend the trail behind the head by 3× the single-frame delta
      final dx = p.x - p.prevX;
      final dy = p.y - p.prevY;
      final tailX = p.x - dx * 3.0;
      final tailY = p.y - dy * 3.0;

      trailPaint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawLine(Offset(tailX, tailY), Offset(p.x, p.y), trailPaint);

      // Bright dot at the head
      dotPaint.color = Colors.white.withValues(
        alpha: (alpha * 1.3).clamp(0.0, 1.0),
      );
      canvas.drawCircle(Offset(p.x, p.y), 1.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_WindPainter oldDelegate) => true; // repaints every frame
}
