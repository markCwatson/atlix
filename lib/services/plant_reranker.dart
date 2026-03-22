import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models/plant_metadata.dart';
import '../models/plant_result.dart';
import 'region_lookup.dart';

/// Reranks plant classifier predictions using species metadata,
/// user location, current season, and selected plant part.
///
/// This is the Phase 2 intelligence layer — pure Dart, no model needed.
class PlantReranker {
  Map<String, PlantSpeciesMeta>? _metaByName;
  bool _initAttempted = false;

  /// Load species metadata from bundled asset.
  /// Fails silently — if metadata is unavailable, reranking is a no-op.
  Future<void> init() async {
    if (_initAttempted) return;
    _initAttempted = true;

    try {
      final json = await rootBundle.loadString(
        'assets/models/plant_metadata.json',
      );
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      _metaByName = {};
      for (final entry in list) {
        final meta = PlantSpeciesMeta.fromJson(entry);
        // Key by scientific name (lowercase, underscored — matches model class names)
        _metaByName![meta.scientificName.toLowerCase().replaceAll(' ', '_')] =
            meta;
      }
      debugPrint(
        '[PlantReranker] Loaded metadata for ${_metaByName!.length} species',
      );
    } catch (e) {
      debugPrint('[PlantReranker] Metadata not available: $e');
      _metaByName = null;
    }
  }

  /// Rerank predictions using contextual signals.
  ///
  /// If metadata is not loaded, returns predictions unchanged but enriched
  /// with common names where available.
  Future<List<PlantPrediction>> rerank(
    List<PlantPrediction> predictions, {
    double? latitude,
    double? longitude,
    int? month,
    PlantPart? plantPart,
  }) async {
    await init();

    if (_metaByName == null || _metaByName!.isEmpty) {
      return predictions;
    }

    // Resolve region from GPS
    String? region;
    if (latitude != null && longitude != null) {
      region = RegionLookup.lookup(latitude, longitude);
    }

    final reranked = predictions.map((pred) {
      final key = pred.className.toLowerCase().replaceAll(' ', '_');
      final meta = _metaByName![key];

      if (meta == null) {
        // No metadata — return with raw confidence as adjusted score
        return pred.copyWith(adjustedScore: pred.confidence);
      }

      // Region weight
      double regionWeight = 1.0;
      if (region != null && meta.regions.isNotEmpty) {
        regionWeight = meta.regions.contains(region) ? 1.5 : 0.2;
      }

      // Season weight
      double seasonWeight = 1.0;
      if (month != null && meta.activeMonths.isNotEmpty) {
        seasonWeight = meta.activeMonths.contains(month) ? 1.3 : 0.5;
      }

      // Plant part weight
      double partWeight = 1.0;
      if (plantPart != null && meta.commonParts.isNotEmpty) {
        partWeight = meta.commonParts.contains(plantPart) ? 1.2 : 0.8;
      }

      final adjustedScore =
          pred.confidence * regionWeight * seasonWeight * partWeight;

      return pred.copyWith(
        commonName: meta.commonName,
        adjustedScore: adjustedScore,
      );
    }).toList();

    // Re-sort by adjusted score
    reranked.sort(
      (a, b) => (b.adjustedScore ?? b.confidence).compareTo(
        a.adjustedScore ?? a.confidence,
      ),
    );

    return reranked;
  }
}
