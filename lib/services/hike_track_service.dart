import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/hike_track.dart';

/// Persists hike tracks using Hive.
class HikeTrackService {
  static const _boxName = 'hike_tracks';
  static const _listKey = 'tracks';

  Future<Box<String>> _openBox() => Hive.openBox<String>(_boxName);

  /// Save a new hike track. Inserts at the front (newest first).
  Future<void> save(HikeTrack track) async {
    final all = await _loadAll();
    all.insert(0, track);
    await _saveAll(all);
    debugPrint(
      '[HikeTrackService] Saved track ${track.id}. Total: ${all.length}',
    );
  }

  /// Load all saved tracks, newest first.
  Future<List<HikeTrack>> loadAll() async {
    return _loadAll();
  }

  /// Delete a track by ID.
  Future<void> delete(String id) async {
    final all = await _loadAll();
    all.removeWhere((t) => t.id == id);
    await _saveAll(all);
  }

  /// Update an existing track (matched by id).
  Future<void> update(HikeTrack track) async {
    final all = await _loadAll();
    final idx = all.indexWhere((t) => t.id == track.id);
    if (idx >= 0) {
      all[idx] = track;
      await _saveAll(all);
    }
  }

  Future<List<HikeTrack>> _loadAll() async {
    final box = await _openBox();
    final raw = box.get(_listKey);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return list.map(HikeTrack.fromJson).toList();
  }

  Future<void> _saveAll(List<HikeTrack> tracks) async {
    final box = await _openBox();
    final json = jsonEncode(tracks.map((t) => t.toJson()).toList());
    await box.put(_listKey, json);
  }
}
