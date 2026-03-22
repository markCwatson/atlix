import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/plant_result.dart';

/// On-device plant species classifier using TFLite.
///
/// Loads an EfficientNet-Lite0 model and runs classification entirely
/// on-device with no internet required. Unlike [TrackDetector], this is
/// a whole-image classifier — no bounding boxes or NMS.
class PlantClassifier {
  static const int _inputSize = 224;
  static const double _confThreshold = 0.01;
  static const int _topK = 10;

  // ImageNet normalisation constants
  static const _mean = [0.485, 0.456, 0.406];
  static const _std = [0.229, 0.224, 0.225];

  Interpreter? _interpreter;
  Map<int, String>? _classNames;
  int _numClasses = 0;

  /// Initialise the classifier.
  Future<void> init() async {
    dispose();

    _interpreter = await Interpreter.fromAsset(
      'assets/models/plant_classifier_float16.tflite',
    );

    final classJson = await rootBundle.loadString(
      'assets/models/plant_classes.json',
    );
    final raw = jsonDecode(classJson) as Map<String, dynamic>;
    _classNames = raw.map((k, v) => MapEntry(int.parse(k), v as String));
    _numClasses = _classNames!.length;
  }

  /// Run classification on an image file.
  ///
  /// Returns predictions sorted by confidence (highest first).
  Future<List<PlantPrediction>> classify(File imageFile) async {
    if (_interpreter == null || _classNames == null) {
      throw StateError('PlantClassifier not initialised — call init() first');
    }

    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw ArgumentError('Could not decode image');

    // Resize to model input size
    final resized = img.copyResize(
      image,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    // Convert to float32 tensor with ImageNet normalisation
    final input = _imageToTensor(resized);

    // Allocate output: [1, numClasses] logits
    final output = List.generate(1, (_) => List.filled(_numClasses, 0.0));

    _interpreter!.run(input, output);

    debugPrint('[PlantClassifier] Model ran. numClasses=$_numClasses');

    // Apply softmax and build predictions
    final logits = output[0];
    final probs = _softmax(logits);

    return _buildPredictions(probs);
  }

  /// Release resources.
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _classNames = null;
  }

  // ── Private helpers ──────────────────────────────────────────────────

  /// Convert image to [1, 224, 224, 3] float32 tensor with ImageNet normalisation.
  List<List<List<List<double>>>> _imageToTensor(img.Image image) {
    final tensor = List.generate(
      1,
      (_) => List.generate(
        _inputSize,
        (_) => List.generate(_inputSize, (_) => List.filled(3, 0.0)),
      ),
    );

    for (int y = 0; y < _inputSize; y++) {
      for (int x = 0; x < _inputSize; x++) {
        final pixel = image.getPixel(x, y);
        tensor[0][y][x][0] = (pixel.r / 255.0 - _mean[0]) / _std[0];
        tensor[0][y][x][1] = (pixel.g / 255.0 - _mean[1]) / _std[1];
        tensor[0][y][x][2] = (pixel.b / 255.0 - _mean[2]) / _std[2];
      }
    }

    return tensor;
  }

  /// Numerically stable softmax.
  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(max);
    final exps = logits.map((l) => exp(l - maxLogit)).toList();
    final sumExps = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sumExps).toList();
  }

  /// Build sorted predictions from probability distribution.
  List<PlantPrediction> _buildPredictions(List<double> probs) {
    final predictions = <PlantPrediction>[];

    for (int i = 0; i < _numClasses; i++) {
      if (probs[i] >= _confThreshold) {
        predictions.add(
          PlantPrediction(
            className: _classNames![i] ?? 'unknown',
            confidence: probs[i],
          ),
        );
      }
    }

    predictions.sort((a, b) => b.confidence.compareTo(a.confidence));

    // Return top K
    if (predictions.length > _topK) {
      return predictions.sublist(0, _topK);
    }
    return predictions;
  }
}
