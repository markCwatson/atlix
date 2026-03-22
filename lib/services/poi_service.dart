import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/poi.dart';

/// Persists point-of-interest pins using Hive.
class PoiService {
  static const _boxName = 'poi_pins';
  static const _listKey = 'pins';

  Future<Box<String>> _openBox() => Hive.openBox<String>(_boxName);

  /// Load all saved POIs.
  Future<List<Poi>> loadAll() async {
    final box = await _openBox();
    final raw = box.get(_listKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(Poi.fromJson).toList();
  }

  /// Save a new POI.
  Future<void> save(Poi poi) async {
    final all = await loadAll();
    all.insert(0, poi);
    await _saveAll(all);
  }

  /// Delete a POI by ID.
  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((p) => p.id == id);
    await _saveAll(all);
  }

  Future<void> _saveAll(List<Poi> pois) async {
    final box = await _openBox();
    final json = jsonEncode(pois.map((p) => p.toJson()).toList());
    await box.put(_listKey, json);
  }
}
