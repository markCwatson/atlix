import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// Which part of the plant the user photographed.
enum PlantPart { leaf, flower, bark, fruit, wholePlant }

/// A single species prediction from the plant classifier.
class PlantPrediction extends Equatable {
  /// Species name predicted by the model (scientific name).
  final String className;

  /// Raw confidence score from the model (0.0–1.0).
  final double confidence;

  /// Common name populated from metadata (Phase 2).
  final String? commonName;

  /// Reranked score after metadata adjustments (Phase 2).
  final double? adjustedScore;

  const PlantPrediction({
    required this.className,
    required this.confidence,
    this.commonName,
    this.adjustedScore,
  });

  /// The display score — uses adjusted score if available, else raw confidence.
  double get displayScore => adjustedScore ?? confidence;

  PlantPrediction copyWith({
    String? className,
    double? confidence,
    String? commonName,
    double? adjustedScore,
  }) => PlantPrediction(
    className: className ?? this.className,
    confidence: confidence ?? this.confidence,
    commonName: commonName ?? this.commonName,
    adjustedScore: adjustedScore ?? this.adjustedScore,
  );

  Map<String, dynamic> toJson() => {
    'className': className,
    'confidence': confidence,
    if (commonName != null) 'commonName': commonName,
    if (adjustedScore != null) 'adjustedScore': adjustedScore,
  };

  factory PlantPrediction.fromJson(Map<String, dynamic> json) =>
      PlantPrediction(
        className: json['className'] as String,
        confidence: (json['confidence'] as num).toDouble(),
        commonName: json['commonName'] as String?,
        adjustedScore: (json['adjustedScore'] as num?)?.toDouble(),
      );

  @override
  List<Object?> get props => [className, confidence, commonName, adjustedScore];
}

/// A saved plant identification result.
class PlantResult extends Equatable {
  final String id;
  final String imagePath;
  final PlantPart plantPart;
  final List<PlantPrediction> predictions;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;

  /// Original image dimensions.
  final int imageWidth;
  final int imageHeight;

  const PlantResult({
    required this.id,
    required this.imagePath,
    required this.plantPart,
    required this.predictions,
    required this.timestamp,
    required this.imageWidth,
    required this.imageHeight,
    this.latitude,
    this.longitude,
  });

  /// The top prediction by display score, or null if none.
  PlantPrediction? get topPrediction =>
      predictions.isEmpty ? null : predictions.first;

  /// Display name for the plant part.
  String get partLabel => switch (plantPart) {
    PlantPart.leaf => 'Leaf',
    PlantPart.flower => 'Flower',
    PlantPart.bark => 'Bark',
    PlantPart.fruit => 'Fruit',
    PlantPart.wholePlant => 'Whole Plant',
  };

  /// Emoji for the plant part.
  String get partEmoji => switch (plantPart) {
    PlantPart.leaf => '🍃',
    PlantPart.flower => '🌸',
    PlantPart.bark => '🌳',
    PlantPart.fruit => '🍎',
    PlantPart.wholePlant => '🌿',
  };

  /// Icon for the plant part.
  IconData get partIcon => switch (plantPart) {
    PlantPart.leaf => Icons.eco,
    PlantPart.flower => Icons.local_florist,
    PlantPart.bark => Icons.park,
    PlantPart.fruit => Icons.apple,
    PlantPart.wholePlant => Icons.grass,
  };

  /// Formats a species name from model class (e.g. "acer_saccharum" → "Acer Saccharum").
  static String formatSpeciesName(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    'plantPart': plantPart.name,
    'predictions': predictions.map((p) => p.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'latitude': latitude,
    'longitude': longitude,
  };

  factory PlantResult.fromJson(Map<String, dynamic> json) => PlantResult(
    id: json['id'] as String,
    imagePath: json['imagePath'] as String,
    plantPart: PlantPart.values.byName(json['plantPart'] as String),
    predictions: (json['predictions'] as List)
        .map((p) => PlantPrediction.fromJson(p as Map<String, dynamic>))
        .toList(),
    timestamp: DateTime.parse(json['timestamp'] as String),
    imageWidth: json['imageWidth'] as int,
    imageHeight: json['imageHeight'] as int,
    latitude: (json['latitude'] as num?)?.toDouble(),
    longitude: (json['longitude'] as num?)?.toDouble(),
  );

  @override
  List<Object?> get props => [id];
}
