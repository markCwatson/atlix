part of 'map_screen.dart';

// ignore_for_file: invalid_use_of_protected_member, library_private_types_in_public_api

/// Hunting setback (no-hunt zone) overlay methods for [_MapScreenState].
///
/// Renders two concentric zone layers around buildings:
///   RED  (0–182 m)   — all weapons restricted  (NS s.11(3)/(4))
///   YELLOW (182–402 m) — rifle/slug restricted  (NS s.11(2))
///
/// Built from buffered Microsoft Building Footprints data, uploaded as a
/// Mapbox vector tileset. The `zone_type` feature property drives colours.
extension _MapScreenSetbackOverlay on _MapScreenState {
  // ── Source / layer IDs ──────────────────────────────────────────────
  static const _sourceId = 'setback-overlay-source';
  static const _fillAllId = 'setback-fill-all-weapons';
  static const _lineAllId = 'setback-line-all-weapons';
  static const _fillRifleId = 'setback-fill-rifle-slug';
  static const _lineRifleId = 'setback-line-rifle-slug';
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

      // ── Red zone: all weapons restricted (0–182 m) ──────────────
      await _mapboxMap!.style.addLayer(
        FillLayer(
          id: _fillAllId,
          sourceId: _sourceId,
          sourceLayer: _sourceLayerName,
          fillColor: const Color(0xFFC62828).toARGB32(), // red
          fillOpacity: 0.25,
        ),
      );
      await _mapboxMap!.style.setStyleLayerProperty(_fillAllId, 'filter', [
        '==',
        ['get', 'zone_type'],
        'all_weapons',
      ]);

      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: _lineAllId,
          sourceId: _sourceId,
          sourceLayer: _sourceLayerName,
          lineColor: const Color(0xFFD32F2F).toARGB32(), // red
          lineWidth: 1.0,
          lineOpacity: 0.6,
        ),
      );
      await _mapboxMap!.style.setStyleLayerProperty(_lineAllId, 'filter', [
        '==',
        ['get', 'zone_type'],
        'all_weapons',
      ]);

      // ── Yellow zone: rifle/slug restricted (182–402 m) ──────────
      await _mapboxMap!.style.addLayer(
        FillLayer(
          id: _fillRifleId,
          sourceId: _sourceId,
          sourceLayer: _sourceLayerName,
          fillColor: const Color(0xFFFFA000).toARGB32(), // amber
          fillOpacity: 0.20,
        ),
      );
      await _mapboxMap!.style.setStyleLayerProperty(_fillRifleId, 'filter', [
        '==',
        ['get', 'zone_type'],
        'rifle_slug',
      ]);

      await _mapboxMap!.style.addLayer(
        LineLayer(
          id: _lineRifleId,
          sourceId: _sourceId,
          sourceLayer: _sourceLayerName,
          lineColor: const Color(0xFFFFA000).toARGB32(), // amber
          lineWidth: 1.0,
          lineOpacity: 0.5,
        ),
      );
      await _mapboxMap!.style.setStyleLayerProperty(_lineRifleId, 'filter', [
        '==',
        ['get', 'zone_type'],
        'rifle_slug',
      ]);

      debugPrint('[SetbackOverlay] all layers added successfully');
    } catch (e) {
      debugPrint('[SetbackOverlay] ERROR adding layers: $e');
    }
  }

  // ── Remove overlay layers ─────────────────────────────────────────
  Future<void> _removeSetbackOverlayLayers() async {
    if (_mapboxMap == null) return;
    for (final id in [_fillAllId, _lineAllId, _fillRifleId, _lineRifleId]) {
      try {
        await _mapboxMap!.style.removeStyleLayer(id);
      } catch (_) {}
    }
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

  // ── Map legend (visible when overlay is active) ───────────────────
  Widget _setbackLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Setback Zones',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          _legendRow(const Color(0xFFC62828), 'All weapons (< 182 m)'),
          const SizedBox(height: 4),
          _legendRow(const Color(0xFFFFA000), 'Rifle / slug (182–402 m)'),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.5),
            border: Border.all(color: color, width: 1.5),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}
