part of 'map_screen.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

/// 2D / 3D terrain toggle + elevation exaggeration slider
/// for [_MapScreenState].
extension _MapScreenTerrain on _MapScreenState {
  static const _demSourceId = 'mapbox-dem';
  static const _skyLayerId = 'sky-layer-3d';

  /// Enable 3D terrain: add DEM source, set terrain, add sky, pitch camera.
  Future<void> _enable3D() async {
    if (_mapboxMap == null) return;
    final style = _mapboxMap!.style;

    try {
      // 1. Add raster DEM source (Mapbox Terrain v1)
      final exists = await style.styleSourceExists(_demSourceId);
      if (!exists) {
        await style.addSource(
          RasterDemSource(
            id: _demSourceId,
            url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
            tileSize: 514,
          ),
        );
      }

      // 2. Enable terrain with current exaggeration
      await style.setStyleTerrain(
        '{"source":"$_demSourceId","exaggeration":$_elevationExaggeration}',
      );

      // 3. Add sky layer for atmosphere effect
      final skyExists = await style.styleLayerExists(_skyLayerId);
      if (!skyExists) {
        await style.addLayer(
          SkyLayer(
            id: _skyLayerId,
            skyType: SkyType.ATMOSPHERE,
            skyAtmosphereSun: [0.0, 0.0],
            skyAtmosphereSunIntensity: 15.0,
          ),
        );
      }

      // 4. Animate camera to pitched view
      await _mapboxMap!.flyTo(
        CameraOptions(pitch: 60),
        MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      debugPrint('[Terrain] Failed to enable 3D: $e');
    }
  }

  /// Disable 3D terrain: remove terrain, sky, source, un-pitch camera.
  Future<void> _disable3D() async {
    if (_mapboxMap == null) return;
    final style = _mapboxMap!.style;

    // Each step is independent — one failing must not block the others.
    try {
      await style.setStyleTerrain('{}');
    } catch (e) {
      debugPrint('[Terrain] clear terrain: $e');
    }
    try {
      if (await style.styleLayerExists(_skyLayerId)) {
        await style.removeStyleLayer(_skyLayerId);
      }
    } catch (e) {
      debugPrint('[Terrain] remove sky: $e');
    }
    try {
      if (await style.styleSourceExists(_demSourceId)) {
        await style.removeStyleSource(_demSourceId);
      }
    } catch (e) {
      debugPrint('[Terrain] remove DEM: $e');
    }
    try {
      await _mapboxMap!.flyTo(
        CameraOptions(pitch: 0),
        MapAnimationOptions(duration: 1000),
      );
    } catch (e) {
      debugPrint('[Terrain] reset pitch: $e');
    }
  }

  /// Update terrain exaggeration in real time (slider callback).
  Future<void> _updateExaggeration(double value) async {
    if (_mapboxMap == null) return;
    try {
      await _mapboxMap!.style.setStyleTerrainProperty('exaggeration', value);
    } catch (e) {
      debugPrint('[Terrain] Failed to update exaggeration: $e');
    }
  }

  /// Toggle 3D mode on/off.
  Future<void> _toggle3D() async {
    if (_is3DEnabled) {
      await _disable3D();
    } else {
      await _enable3D();
    }
    setState(() => _is3DEnabled = !_is3DEnabled);
  }

  /// 2D/3D toggle button (matches existing 44×44 FAB pattern).
  Widget _terrainButton() {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'terrain_3d',
        mini: true,
        backgroundColor: _is3DEnabled ? Colors.orangeAccent : Colors.black87,
        onPressed: _toggle3D,
        child: Icon(
          Icons.terrain,
          color: _is3DEnabled ? Colors.black : Colors.white,
          size: 20,
        ),
      ),
    );
  }

  /// Vertical elevation exaggeration slider (visible in 3D mode only).
  Widget _exaggerationSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.landscape, color: Colors.white54, size: 16),
          const SizedBox(height: 2),
          RotatedBox(
            quarterTurns: -1,
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: Colors.orangeAccent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.orangeAccent,
                overlayColor: Colors.orangeAccent.withValues(alpha: 0.2),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: SizedBox(
                width: 120,
                child: Slider(
                  value: _elevationExaggeration,
                  min: 1.0,
                  max: 10.0,
                  onChanged: (v) {
                    setState(() => _elevationExaggeration = v);
                    _updateExaggeration(v);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_elevationExaggeration.toStringAsFixed(1)}×',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
