import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../services/offline_region_service.dart';

/// Screen for managing offline map regions: view downloads, trigger new
/// downloads, delete existing regions.
class OfflineRegionsScreen extends StatefulWidget {
  /// Current map viewport bounds [south, west, north, east] — used as the
  /// default area for a new download.
  final List<double>? currentBounds;

  const OfflineRegionsScreen({super.key, this.currentBounds});

  @override
  State<OfflineRegionsScreen> createState() => _OfflineRegionsScreenState();
}

class _OfflineRegionsScreenState extends State<OfflineRegionsScreen> {
  final OfflineRegionService _service = OfflineRegionService();
  List<OfflineRegionInfo> _regions = [];
  bool _loading = true;

  // Download in progress state
  bool _downloading = false;
  int _completedResources = 0;
  int _totalResources = 0;
  int _completedBytes = 0;
  final _nameController = TextEditingController();

  // The bounds that will actually be downloaded — updated as user pans/zooms
  List<double>? _downloadBounds;
  MapboxMap? _previewMap;
  bool _forceOffline = false;

  @override
  void initState() {
    super.initState();
    _downloadBounds = widget.currentBounds != null
        ? List<double>.from(widget.currentBounds!)
        : null;
    _loadRegions();
    _loadOfflineSwitch();
  }

  Future<void> _loadOfflineSwitch() async {
    final connected = await OfflineSwitch.shared.isMapboxStackConnected;
    if (mounted) setState(() => _forceOffline = !connected);
  }

  Future<void> _toggleForceOffline(bool value) async {
    await OfflineSwitch.shared.setMapboxStackConnected(!value);
    setState(() => _forceOffline = value);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadRegions() async {
    setState(() => _loading = true);
    try {
      final regions = await _service.listRegions();
      if (mounted) setState(() => _regions = regions);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load regions: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startDownload() async {
    // Sync bounds from the preview map one last time before downloading
    await _syncBoundsFromPreview();

    final bounds = _downloadBounds;
    if (bounds == null || bounds.length < 4) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No map area available. Open this from the map screen.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a name for this region.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Use name as ID (sanitized)
    final id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

    setState(() {
      _downloading = true;
      _completedResources = 0;
      _totalResources = 0;
      _completedBytes = 0;
    });

    try {
      await _service.downloadRegion(
        id: id,
        bounds: bounds,
        minZoom: 10,
        maxZoom: 16,
        onProgress: (completed, required, bytes) {
          if (mounted) {
            setState(() {
              _completedResources = completed;
              _totalResources = required;
              _completedBytes = bytes;
            });
          }
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded "$name" for offline use'),
            backgroundColor: Colors.teal,
          ),
        );
        _nameController.clear();
        _loadRegions();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  /// Rough zoom estimate from bounds span so the preview frames the area.
  double _estimateZoom(List<double> bounds) {
    final latSpan = (bounds[2] - bounds[0]).abs();
    final lonSpan = (bounds[3] - bounds[1]).abs();
    final span = latSpan > lonSpan ? latSpan : lonSpan;
    if (span <= 0) return 12;
    // ~360° at zoom 0, halves each zoom level
    final z = 360 / span;
    return (math.log(z) / math.ln2 - 1).clamp(1.0, 16.0);
  }

  void _onPreviewMapCreated(MapboxMap map) {
    _previewMap = map;
  }

  Future<void> _syncBoundsFromPreview() async {
    if (_previewMap == null) return;
    try {
      final bounds = await _previewMap!.coordinateBoundsForCamera(
        await _previewMap!.getCameraState().then(
          (cam) => CameraOptions(
            center: cam.center,
            zoom: cam.zoom,
            bearing: cam.bearing,
            pitch: cam.pitch,
          ),
        ),
      );
      _downloadBounds = [
        bounds.southwest.coordinates.lat.toDouble(),
        bounds.southwest.coordinates.lng.toDouble(),
        bounds.northeast.coordinates.lat.toDouble(),
        bounds.northeast.coordinates.lng.toDouble(),
      ];
    } catch (_) {}
  }

  Future<void> _clearCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Clear Tile Cache',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This clears the ambient tile cache (tiles cached during '
          'normal browsing). Your explicitly downloaded regions will '
          'need to be re-downloaded.\n\n'
          'Use this to verify offline downloads work correctly.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.clearAllData();
      _loadRegions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cache cleared. Re-download regions for offline use.',
            ),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear cache: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  Future<void> _deleteRegion(OfflineRegionInfo region) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Delete Region',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Delete "${region.id}" and free ${region.sizeLabel}?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _service.removeRegion(region.id);
      _loadRegions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        title: const Text('Offline Maps'),
        backgroundColor: Colors.grey[850],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear all map data',
            onPressed: _clearCache,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Force Offline toggle ─────────────────────────────────
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _forceOffline ? Colors.red[900] : Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    _forceOffline ? Icons.airplanemode_active : Icons.wifi,
                    color: _forceOffline ? Colors.redAccent : Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _forceOffline
                              ? 'Offline Mode Active'
                              : 'Force Offline',
                          style: TextStyle(
                            color: _forceOffline
                                ? Colors.redAccent
                                : Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _forceOffline
                              ? 'Mapbox SDK blocked from network'
                              : 'Block Mapbox SDK network access to test offline',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _forceOffline,
                    onChanged: _toggleForceOffline,
                    activeThumbColor: Colors.redAccent,
                  ),
                ],
              ),
            ),
            // ── Download new region ──────────────────────────────────
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Download Map Area',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pan and zoom the map to select the area you want '
                    'to download for offline use (satellite imagery + land overlay).',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  // Interactive map preview — pan/zoom to select download area
                  if (_downloadBounds != null && _downloadBounds!.length >= 4)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: Stack(
                          children: [
                            MapWidget(
                              cameraOptions: CameraOptions(
                                center: Point(
                                  coordinates: Position(
                                    (_downloadBounds![1] +
                                            _downloadBounds![3]) /
                                        2,
                                    (_downloadBounds![0] +
                                            _downloadBounds![2]) /
                                        2,
                                  ),
                                ),
                                zoom: _estimateZoom(_downloadBounds!),
                              ),
                              styleUri: MapboxStyles.SATELLITE_STREETS,
                              onMapCreated: _onPreviewMapCreated,
                            ),
                            // Crosshair / area hint
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.orangeAccent.withAlpha(180),
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                            // Label
                            Positioned(
                              bottom: 6,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Pan & zoom to select area',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_downloadBounds != null) const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    enabled: !_downloading,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Region name (e.g. "NS Hunting Camp")',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_downloading) ...[
                    LinearProgressIndicator(
                      value: _totalResources > 0
                          ? _completedResources / _totalResources
                          : null,
                      backgroundColor: Colors.grey[700],
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _totalResources > 0
                          ? '$_completedResources / $_totalResources tiles  •  '
                                '${(_completedBytes / (1 << 20)).toStringAsFixed(1)} MB'
                          : 'Preparing download…',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _downloadBounds != null
                            ? _startDownload
                            : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Existing regions list ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text(
                    'Downloaded Regions',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (!_loading)
                    Text(
                      '${_regions.length} region${_regions.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.orangeAccent,
                      ),
                    )
                  : _regions.isEmpty
                  ? const Center(
                      child: Text(
                        'No offline regions yet.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _regions.length,
                      itemBuilder: (context, index) {
                        final region = _regions[index];
                        return Card(
                          color: Colors.grey[850],
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Icon(
                              region.isComplete
                                  ? Icons.check_circle
                                  : Icons.downloading,
                              color: region.isComplete
                                  ? Colors.teal
                                  : Colors.orangeAccent,
                            ),
                            title: Text(
                              region.id,
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '${region.sizeLabel}  •  '
                              '${region.completedResourceCount} / '
                              '${region.requiredResourceCount} tiles',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _deleteRegion(region),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
