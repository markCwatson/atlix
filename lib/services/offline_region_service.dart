import 'dart:async';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart'
    hide Size, ImageSource;

import '../config.dart';

/// Progress callback for offline tile region downloads.
typedef OfflineProgressCallback =
    void Function(
      int completedResources,
      int requiredResources,
      int completedBytes,
    );

/// A saved offline region record (persisted via Hive in the future, for now
/// just a runtime representation of what TileStore knows about).
class OfflineRegionInfo {
  final String id;
  final int completedResourceCount;
  final int requiredResourceCount;
  final int completedBytes;
  final bool isComplete;

  OfflineRegionInfo({
    required this.id,
    required this.completedResourceCount,
    required this.requiredResourceCount,
    required this.completedBytes,
    required this.isComplete,
  });

  /// Human-readable download size.
  String get sizeLabel {
    if (completedBytes < 1024) return '$completedBytes B';
    if (completedBytes < 1 << 20) return '${completedBytes >> 10} KB';
    return '${(completedBytes / (1 << 20)).toStringAsFixed(1)} MB';
  }

  double get progress => requiredResourceCount > 0
      ? completedResourceCount / requiredResourceCount
      : 0;
}

/// Service wrapping Mapbox TileStore and OfflineManager for downloading
/// map tiles (satellite/streets + land overlay) for offline use.
class OfflineRegionService {
  TileStore? _tileStore;
  OfflineManager? _offlineManager;

  Future<void> _ensureInit() async {
    _tileStore ??= await TileStore.createDefault();
    _offlineManager ??= await OfflineManager.create();
  }

  /// Download an offline tile region for the given bounding box.
  ///
  /// [id] — unique region identifier (e.g. "ns-hunting-area-1").
  /// [bounds] — bounding box as [south, west, north, east].
  /// [minZoom] / [maxZoom] — zoom range to download.
  /// [onProgress] — called as tiles are fetched.
  ///
  /// Downloads both the satellite-streets style tiles AND the custom land
  /// overlay tileset (if configured).
  Future<TileRegion> downloadRegion({
    required String id,
    required List<double> bounds, // [south, west, north, east]
    int minZoom = 0,
    int maxZoom = 14,
    OfflineProgressCallback? onProgress,
  }) async {
    await _ensureInit();

    // Build the bounding-box polygon geometry (GeoJSON-like map)
    final south = bounds[0];
    final west = bounds[1];
    final north = bounds[2];
    final east = bounds[3];
    final geometry = <String, Object?>{
      'type': 'Polygon',
      'coordinates': [
        [
          [west, south],
          [east, south],
          [east, north],
          [west, north],
          [west, south],
        ],
      ],
    };

    // Tileset descriptors — the satellite streets style
    final descriptors = <TilesetDescriptorOptions>[
      TilesetDescriptorOptions(
        styleURI: MapboxStyles.SATELLITE_STREETS,
        minZoom: minZoom,
        maxZoom: maxZoom,
        stylePackOptions: StylePackLoadOptions(acceptExpired: false),
      ),
    ];

    // If a custom land overlay tileset is configured, include it
    final landTileset = AppConfig.landTilesetId;
    if (landTileset.isNotEmpty) {
      descriptors.add(
        TilesetDescriptorOptions(
          styleURI: '',
          minZoom: minZoom,
          maxZoom: maxZoom,
          tilesets: ['mapbox://$landTileset'],
        ),
      );
    }

    // If a setback (no-hunt zone) tileset is configured, include it
    final setbackTileset = AppConfig.setbackTilesetId;
    if (setbackTileset.isNotEmpty) {
      descriptors.add(
        TilesetDescriptorOptions(
          styleURI: '',
          minZoom: minZoom,
          maxZoom: maxZoom,
          tilesets: ['mapbox://$setbackTileset'],
        ),
      );
    }

    final loadOptions = TileRegionLoadOptions(
      geometry: geometry,
      descriptorsOptions: descriptors,
      acceptExpired: false,
      networkRestriction: NetworkRestriction.NONE,
      metadata: {'name': id, 'createdAt': DateTime.now().toIso8601String()},
    );

    return _tileStore!.loadTileRegion(
      id,
      loadOptions,
      onProgress != null
          ? (progress) {
              onProgress(
                progress.completedResourceCount,
                progress.requiredResourceCount,
                progress.completedResourceSize,
              );
            }
          : null,
    );
  }

  /// List all downloaded tile regions.
  Future<List<OfflineRegionInfo>> listRegions() async {
    await _ensureInit();
    final regions = await _tileStore!.allTileRegions();
    return regions.map((r) {
      return OfflineRegionInfo(
        id: r.id,
        completedResourceCount: r.completedResourceCount,
        requiredResourceCount: r.requiredResourceCount,
        completedBytes: r.completedResourceSize,
        isComplete: r.completedResourceCount >= r.requiredResourceCount,
      );
    }).toList();
  }

  /// Delete a downloaded tile region.
  Future<void> removeRegion(String id) async {
    await _ensureInit();
    await _tileStore!.removeRegion(id);
  }

  /// Clear all map data — ambient tile cache, tile regions, style packs.
  /// Everything must be re-downloaded afterwards.
  Future<void> clearAllData() async {
    await MapboxMapsOptions.clearData();
    // clearData invalidates existing TileStore/OfflineManager instances
    _tileStore = null;
    _offlineManager = null;
  }
}
