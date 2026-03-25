import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Size;

import '../models/hike_track.dart';

/// Full-screen hike summary with a Mapbox map showing the track and stats.
class HikeSummaryScreen extends StatefulWidget {
  final HikeTrack track;
  final bool viewOnly;
  final Future<void> Function(String name)? onSave;
  final VoidCallback? onDiscard;
  final Future<void> Function(String name)? onRename;

  const HikeSummaryScreen({
    super.key,
    required this.track,
    this.viewOnly = false,
    this.onSave,
    this.onDiscard,
    this.onRename,
  });

  @override
  State<HikeSummaryScreen> createState() => _HikeSummaryScreenState();
}

class _HikeSummaryScreenState extends State<HikeSummaryScreen> {
  final _nameController = TextEditingController();
  bool _layerReady = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.track.name;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── Bounding box for the track ──────────────────────────────────────

  ({double minLat, double maxLat, double minLon, double maxLon}) _bounds() {
    double minLat = 90, maxLat = -90, minLon = 180, maxLon = -180;
    for (final p in widget.track.points) {
      minLat = min(minLat, p.lat);
      maxLat = max(maxLat, p.lat);
      minLon = min(minLon, p.lon);
      maxLon = max(maxLon, p.lon);
    }
    // Expand by 20% so the track doesn't hug the edges
    final latPad = (maxLat - minLat) * 0.20;
    final lonPad = (maxLon - minLon) * 0.20;
    return (
      minLat: minLat - latPad,
      maxLat: maxLat + latPad,
      minLon: minLon - lonPad,
      maxLon: maxLon + lonPad,
    );
  }

  CameraOptions _initialCamera() {
    if (widget.track.points.isEmpty) {
      return CameraOptions(
        center: Point(coordinates: Position(-98.58, 39.83)),
        zoom: 4,
      );
    }
    final b = _bounds();
    final centerLat = (b.minLat + b.maxLat) / 2;
    final centerLon = (b.minLon + b.maxLon) / 2;
    return CameraOptions(
      center: Point(coordinates: Position(centerLon, centerLat)),
      zoom: 14,
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    // Fit to track bounds with padding
    if (widget.track.points.length >= 2) {
      final b = _bounds();
      await map.flyTo(
        CameraOptions(
          center: Point(
            coordinates: Position(
              (b.minLon + b.maxLon) / 2,
              (b.minLat + b.maxLat) / 2,
            ),
          ),
        ),
        MapAnimationOptions(duration: 0),
      );

      // Use coordinate bounds to fit
      final cameraForBounds = await map.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(b.minLon, b.minLat)),
          northeast: Point(coordinates: Position(b.maxLon, b.maxLat)),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
        null,
        null,
        null,
        null,
      );
      await map.flyTo(cameraForBounds, MapAnimationOptions(duration: 800));
    }

    // Draw the track on the map
    await _drawTrack(map);
  }

  String _pointsGeoJson() {
    final features = widget.track.points
        .map(
          (p) =>
              '{"type":"Feature","geometry":{"type":"Point","coordinates":[${p.lon},${p.lat}]},"properties":{}}',
        )
        .join(',');
    return '{"type":"FeatureCollection","features":[$features]}';
  }

  Future<void> _drawTrack(MapboxMap map) async {
    if (_layerReady || widget.track.points.length < 2) return;

    final coords = widget.track.points
        .map((p) => Position(p.lon, p.lat))
        .toList();
    final lineString = LineString(coordinates: coords);
    final geojson =
        '{"type":"Feature","geometry":${lineString.toJson()},"properties":{}}';

    await map.style.addSource(
      GeoJsonSource(id: 'hike-track-source', data: geojson),
    );
    await map.style.addLayer(
      LineLayer(
        id: 'hike-track-line',
        sourceId: 'hike-track-source',
        lineColor: Colors.teal.toARGB32(),
        lineWidth: 3.0,
        lineOpacity: 0.5,
      ),
    );
    await map.style.addSource(
      GeoJsonSource(id: 'hike-track-pts', data: _pointsGeoJson()),
    );
    await map.style.addLayer(
      CircleLayer(
        id: 'hike-track-circles',
        sourceId: 'hike-track-pts',
        circleRadius: 4.0,
        circleColor: Colors.teal.toARGB32(),
        circleStrokeWidth: 1.5,
        circleStrokeColor: Colors.white.toARGB32(),
        circleOpacity: 0.9,
      ),
    );
    _layerReady = true;
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final distMi = track.totalDistanceMiles;
    final distKm = track.totalDistanceMeters / 1000.0;
    final gainFt = track.elevationGainFeet;
    final lossFt = track.elevationLossFeet;
    final gainM = track.elevationGainMeters;
    final lossM = track.elevationLossMeters;
    final paceMi = track.paceMinPerMile;
    final paceKm = track.paceMinPerKm;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        title: Text(widget.viewOnly ? 'Hike Summary' : 'Hike Complete!'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            if (widget.viewOnly) {
              Navigator.pop(context);
            } else {
              _confirmDiscard();
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Map taking roughly the top half
          Expanded(
            flex: 3,
            child: ClipRRect(
              child: MapWidget(
                key: const ValueKey('hikeSummaryMap'),
                cameraOptions: _initialCamera(),
                styleUri: MapboxStyles.SATELLITE_STREETS,
                onMapCreated: _onMapCreated,
                gestureRecognizers: const {},
              ),
            ),
          ),

          // Stats + actions in the bottom section
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.directions_walk,
                    color: Colors.teal,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  // Stats grid
                  Row(
                    children: [
                      _stat(
                        'Distance',
                        '${distMi.toStringAsFixed(2)} mi',
                        '(${distKm.toStringAsFixed(2)} km)',
                      ),
                      _stat('Time', track.formattedDuration, ''),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _stat(
                        'Elev Gain',
                        '↑ ${gainFt.round()} ft',
                        '(${gainM.round()} m)',
                      ),
                      _stat(
                        'Elev Loss',
                        '↓ ${lossFt.round()} ft',
                        '(${lossM.round()} m)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _stat(
                        'Avg Pace',
                        '${_formatPace(paceMi)} /mi',
                        '(${_formatPace(paceKm)} /km)',
                      ),
                      _stat('Points', '${track.points.length}', ''),
                    ],
                  ),

                  // Editable name — always shown
                  const SizedBox(height: 20),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Hike Name',
                      labelStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.teal),
                      ),
                    ),
                  ),

                  if (!widget.viewOnly) ...[
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                      onPressed: () async {
                        await widget.onSave?.call(_nameController.text);
                        if (context.mounted) Navigator.pop(context, true);
                      },
                      child: const Text('Save Hike'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _confirmDiscard,
                      child: const Text(
                        'Discard',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                  ],

                  if (widget.viewOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.onRename != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () async {
                                  await widget.onRename?.call(
                                    _nameController.text,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Name updated'),
                                        backgroundColor: Colors.teal,
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Save Name'),
                              ),
                            ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Done',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: Colors.grey[850],
        title: const Text(
          'Discard Hike?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This hike will not be saved.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onDiscard?.call();
      Navigator.pop(context, false);
    }
  }

  Widget _stat(String label, String value, String secondary) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (secondary.isNotEmpty)
              Text(
                secondary,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatPace(double? p) {
    if (p == null || p.isInfinite || p.isNaN) return '--';
    final mins = p.floor();
    final secs = ((p - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
