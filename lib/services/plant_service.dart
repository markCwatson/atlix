import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../models/plant_result.dart';

/// Persists plant identification results using Hive + local image files.
class PlantService {
  static const _boxName = 'plant_results';
  static const _listKey = 'results';

  Future<Box<String>> _openBox() => Hive.openBox<String>(_boxName);

  /// Save a plant result. Copies the image to app documents.
  Future<PlantResult> saveResult(PlantResult result) async {
    debugPrint('[PlantService] saveResult called for id=${result.id}');
    final appDir = await getApplicationDocumentsDirectory();
    final plantsDir = Directory('${appDir.path}/plants');
    if (!plantsDir.existsSync()) {
      plantsDir.createSync(recursive: true);
    }

    // Copy image to permanent storage
    final imgPath = result.imagePath;
    final ext = imgPath.contains('.')
        ? imgPath.substring(imgPath.lastIndexOf('.'))
        : '.jpg';
    final destPath = '${plantsDir.path}/${result.id}$ext';
    debugPrint('[PlantService] Copying image from $imgPath to $destPath');
    await File(result.imagePath).copy(destPath);

    final saved = PlantResult(
      id: result.id,
      imagePath: destPath,
      plantPart: result.plantPart,
      predictions: result.predictions,
      timestamp: result.timestamp,
      imageWidth: result.imageWidth,
      imageHeight: result.imageHeight,
      latitude: result.latitude,
      longitude: result.longitude,
    );

    // Persist metadata
    final results = await _loadAll();
    results.insert(0, saved);
    await _saveAll(results);
    debugPrint('[PlantService] Saved. Total results now: ${results.length}');

    return saved;
  }

  /// Load all saved results, newest first.
  Future<List<PlantResult>> loadResults() async {
    return _loadAll();
  }

  /// Delete a saved result by ID.
  Future<void> deleteResult(String id) async {
    final results = await _loadAll();
    final idx = results.indexWhere((r) => r.id == id);
    if (idx == -1) return;

    final result = results[idx];

    // Delete image file
    final file = File(result.imagePath);
    if (await file.exists()) {
      await file.delete();
    }

    results.removeAt(idx);
    await _saveAll(results);
  }

  // ── Private ────────────────────────────────────────────────────────

  Future<List<PlantResult>> _loadAll() async {
    final box = await _openBox();
    final raw = box.get(_listKey);
    debugPrint(
      '[PlantService] _loadAll: raw=${raw == null ? 'null' : '${raw.length} chars'}',
    );
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    debugPrint('[PlantService] _loadAll: parsed ${list.length} results');
    return list.map(PlantResult.fromJson).toList();
  }

  Future<void> _saveAll(List<PlantResult> results) async {
    final box = await _openBox();
    final json = jsonEncode(results.map((r) => r.toJson()).toList());
    await box.put(_listKey, json);
  }
}
