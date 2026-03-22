import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/plant_result.dart';
import '../services/plant_classifier.dart';
import '../services/plant_reranker.dart';
import '../services/plant_service.dart';

// ── States ──────────────────────────────────────────────────────────────

abstract class PlantState extends Equatable {
  const PlantState();
  @override
  List<Object?> get props => [];
}

class PlantIdle extends PlantState {
  const PlantIdle();
}

class PlantClassifying extends PlantState {
  const PlantClassifying();
}

class PlantDone extends PlantState {
  final PlantResult result;
  final bool saved;
  const PlantDone(this.result, {this.saved = false});
  @override
  List<Object?> get props => [result, saved];
}

class PlantError extends PlantState {
  final String message;
  const PlantError(this.message);
  @override
  List<Object?> get props => [message];
}

// ── Cubit ───────────────────────────────────────────────────────────────

class PlantCubit extends Cubit<PlantState> {
  final PlantClassifier _classifier;
  final PlantService _service;
  final PlantReranker _reranker;
  final ImagePicker _picker;
  static const _uuid = Uuid();

  PlantCubit({
    required PlantClassifier classifier,
    required PlantService service,
    required PlantReranker reranker,
    ImagePicker? picker,
  }) : _classifier = classifier,
       _service = service,
       _reranker = reranker,
       _picker = picker ?? ImagePicker(),
       super(const PlantIdle());

  /// Pick or capture a photo, then run plant classification.
  Future<void> capture(
    PlantPart plantPart, {
    ImageSource source = ImageSource.camera,
    double? latitude,
    double? longitude,
  }) async {
    try {
      final photo = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1920,
      );
      if (photo == null) return; // user cancelled

      emit(const PlantClassifying());

      // Initialise classifier
      await _classifier.init();

      // Get image dimensions
      final file = File(photo.path);
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        emit(const PlantError('Could not decode image'));
        return;
      }

      // Run classification
      var predictions = await _classifier.classify(file);

      // Apply metadata reranking (Phase 2)
      predictions = await _reranker.rerank(
        predictions,
        latitude: latitude,
        longitude: longitude,
        month: DateTime.now().month,
        plantPart: plantPart,
      );

      final result = PlantResult(
        id: _uuid.v4(),
        imagePath: photo.path,
        plantPart: plantPart,
        predictions: predictions,
        timestamp: DateTime.now(),
        imageWidth: decoded.width,
        imageHeight: decoded.height,
        latitude: latitude,
        longitude: longitude,
      );

      debugPrint(
        '[PlantCubit] emitting PlantDone: ${result.predictions.length} predictions, '
        'image=${result.imageWidth}x${result.imageHeight}, path=${result.imagePath}',
      );
      emit(PlantDone(result));
    } catch (e) {
      emit(PlantError('Classification failed: $e'));
    }
  }

  /// Save the current result to local storage.
  Future<void> saveResult() async {
    final current = state;
    debugPrint('[PlantCubit] saveResult called, state=$current');
    if (current is! PlantDone) return;

    try {
      final saved = await _service.saveResult(current.result);
      debugPrint(
        '[PlantCubit] save succeeded, new imagePath=${saved.imagePath}',
      );
      emit(PlantDone(saved, saved: true));
    } catch (e) {
      debugPrint('[PlantCubit] save FAILED: $e');
      emit(PlantError('Save failed: $e'));
    }
  }

  /// Reset to idle.
  void clear() => emit(const PlantIdle());

  /// Load saved results list.
  Future<List<PlantResult>> loadSaved() => _service.loadResults();

  /// Delete a saved result.
  Future<void> deleteSaved(String id) => _service.deleteResult(id);
}
