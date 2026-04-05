part of 'map_screen.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

/// Hunting setback (no-hunt zone) overlay methods for [_MapScreenState].
///
/// Renders a semi-transparent red fill showing areas within the provincial
/// setback distance of buildings. Built from buffered Microsoft Building
/// Footprints data, uploaded as a Mapbox vector tileset.
///
/// Nova Scotia: 201 m (660 ft) from any dwelling for all firearms.
extension _MapScreenSetbackOverlay on _MapScreenState {
  // ── Source / layer IDs ──────────────────────────────────────────────
  static const _sourceId = 'setback-overlay-source';
  static const _fillLayerId = 'setback-overlay-fill';
  static const _lineLayerId = 'setback-overlay-line';
  static const _sourceLayerName = 'setback_zone'; // matches tippecanoe -l

  // ── Hive key for one-time disclaimer ──────────────────────────────
  static const _disclaimerKey = 'setback_disclaimer_accepted';

  // ── Add overlay layers to the map ─────────────────────────────────
  Future<void> _addSetbackOverlayLayers() async {
    if (_mapboxMap == null) return;
    final tilesetId = AppConfig.setbackTilesetId;
    debugPrint('[SetbackOverlay] tilesetId="$tilesetId"');
    if (tilesetId.isEmpty) {
      debugPrint('[SetbackOverlay] tileset ID is empty — skipping');
      return;
    }

    try {
      await _mapboxMap!.style.addSource(
        VectorSource(id: _sourceId, url: 'mapbox://$tilesetId'),
      );
      debugPrint('[SetbackOverlay] source added: mapbox://$tilesetId');

      // Semi-transparent red fill
      await _mapboxMap!.style.addLayer(
        FillLayer(
          id: _fillLayerId,
          sourceId: _sourceId,
          sourceLayer: _sourceLayerName,
          fillColor: const Color(0xFFC62828).toARGB32(),
          fillOpacity: 0.25,
        ),
      );
      debugPrint('[SetbackOverlay] fill layer added');

      // Boundary line
      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: _lineLayerId,
          sourceId: _sourceId,
          sourceLayer: _sourceLayerName,
          lineColor: const Color(0xFFD32F2F).toARGB32(),
          lineWidth: 1.0,
          lineOpacity: 0.6,
        ),
      );
      debugPrint('[SetbackOverlay] line layer added');
      debugPrint('[SetbackOverlay] all layers added successfully');
    } catch (e) {
      debugPrint('[SetbackOverlay] ERROR adding layers: $e');
    }
  }

  // ── Remove overlay layers ─────────────────────────────────────────
  Future<void> _removeSetbackOverlayLayers() async {
    if (_mapboxMap == null) return;
    try {
      await _mapboxMap!.style.removeStyleLayer(_fillLayerId);
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleLayer(_lineLayerId);
    } catch (_) {}
    try {
      await _mapboxMap!.style.removeStyleSource(_sourceId);
    } catch (_) {}
  }

  // ── Toggle overlay on/off ─────────────────────────────────────────
  Future<void> _toggleSetbackOverlay() async {
    if (_setbackOverlayEnabled) {
      await _removeSetbackOverlayLayers();
      setState(() => _setbackOverlayEnabled = false);
    } else {
      // Show one-time disclaimer before enabling
      final box = await Hive.openBox('settings');
      final accepted = box.get(_disclaimerKey, defaultValue: false) as bool;
      if (!accepted) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Setback Zones', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: const Text(
              'Setback zones are approximate and for reference only. '
              'Always verify you are complying with local hunting regulations. '
              'GPS accuracy and building data may not reflect current conditions.',
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'I Understand',
                  style: TextStyle(color: Colors.orangeAccent),
                ),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await box.put(_disclaimerKey, true);
      }

      await _addSetbackOverlayLayers();
      setState(() => _setbackOverlayEnabled = true);
    }
  }

  // ── Sidebar button ────────────────────────────────────────────────
  Widget _setbackOverlayButton({required bool isPro}) {
    return SizedBox(
      width: 44,
      height: 44,
      child: FloatingActionButton(
        heroTag: 'setback_overlay',
        mini: true,
        backgroundColor: _setbackOverlayEnabled
            ? Colors.redAccent
            : (isPro ? Colors.black87 : Colors.grey[800]!),
        onPressed: isPro
            ? _toggleSetbackOverlay
            : () => _showUpgradeSheet(context),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.shield,
              color: _setbackOverlayEnabled
                  ? Colors.white
                  : (isPro ? Colors.white : Colors.white38),
              size: 20,
            ),
            if (!isPro)
              const Positioned(
                right: -2,
                bottom: -2,
                child: Icon(Icons.lock, color: Colors.white54, size: 10),
              ),
          ],
        ),
      ),
    );
  }
}
